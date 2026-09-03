import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/face_alignment_service.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';

/// Orchestrates one enrollment session: turns a stream of camera frames
/// into a handful of accepted face-embedding samples, then a single
/// representative [FaceTemplate].
///
/// Deliberately has no dependency on `camera` or
/// `google_mlkit_face_detection` — only on [DetectedFace]/`img.Image` and
/// the other face services — so it's unit-testable with fakes, and the
/// MobileFaceNet implementation underneath stays swappable later without
/// touching this class (see `FaceEmbeddingService`'s own doc comment on
/// why that matters).
///
/// Never logs or prints a frame or an embedding — matches the discipline
/// already established in `AuthAuditLogService`/`AuthLogEntry`, which
/// never carry biometric payloads either.
///
/// Persistence is deliberately NOT this class's job: [finalizeEnrollment]
/// returns a [FaceTemplate] but never writes it. The caller
/// (`AddOperatorScreen`/`OperatorDetailScreen`) owns the atomic
/// template-then-operator write, so "don't create a partial operator
/// record" stays enforced in one place.
class FaceEnrollmentService {
  FaceEnrollmentService({
    required this.embeddingService,
    required this.templateRepository,
    this.requiredSamples = 10,
    this.minSurvivingSamples = 7,
  });

  final FaceEmbeddingService embeddingService;
  final FaceTemplateRepository templateRepository;

  /// Target number of accepted samples before enrollment auto-finalizes —
  /// within the spec's "5-10 good samples" range.
  final int requiredSamples;

  /// Minimum accepted samples that must survive outlier-trimming in
  /// [finalizeEnrollment] for the resulting template to be trusted. Kept
  /// at the same ~70% ratio of [requiredSamples] as before (5/7), not a
  /// fixed absolute floor, so raising [requiredSamples] doesn't quietly
  /// loosen how many samples are allowed to be trimmed as outliers.
  final int minSurvivingSamples;

  /// Minimum time between two accepted samples, so [requiredSamples]
  /// samples reflect natural micro-movement rather than near-identical
  /// consecutive frames.
  static const Duration _minSampleInterval = Duration(milliseconds: 400);

  /// A candidate sample must be at least this cosine-similar to the
  /// running centroid of already-accepted samples (once there are enough
  /// to have one) to be accepted — guards against a bad frame that
  /// slipped past the earlier quality checks. Deliberately looser than
  /// `FaceMatchingService.defaultThreshold` (0.87): these are same-
  /// session, same-person samples, which should already cluster tightly,
  /// so this only needs to catch genuine outliers, not add pose-tolerance
  /// margin on top of the tolerance the quality gates already allow.
  static const double outlierSimilarityFloor = 0.75;

  /// Consecutive good frames required before the *first* sample is
  /// accepted, so a single noisy frame that happens to clear every check
  /// out of a resting/positioning state can't trigger capture on its own —
  /// without this, one lucky frame decides acceptance, which is what
  /// produces the "waits several seconds, then suddenly captures" feel.
  /// Only gates the first sample: once enrollment has begun the existing
  /// [_minSampleInterval] cooldown already spaces later samples apart, and
  /// the operator is by then already correctly positioned.
  static const int _requiredStableFrames = 3;

  final List<List<double>> _accepted = [];
  DateTime? _lastAcceptedAt;
  int _stableGoodFrames = 0;

  int get samplesCaptured => _accepted.length;

  /// How many consecutive good frames have been seen toward
  /// [_requiredStableFrames] — exposed for the debug diagnostics panel
  /// only; [evaluateAndCapture] uses the private counter directly.
  int get stableGoodFrames => _stableGoodFrames;
  int get requiredStableFrames => _requiredStableFrames;

  /// Clears all in-memory samples — used on cancel/retry. Nothing was
  /// ever written to disk, so there's nothing else to undo.
  void reset() {
    _accepted.clear();
    _lastAcceptedAt = null;
    _stableGoodFrames = 0;
  }

  /// Evaluates one already-detected frame and, if it clears every quality
  /// gate and enough time has passed since the last accepted sample,
  /// embeds and accepts it. Always returns a state to render — never
  /// throws for an ordinary "this frame isn't good enough" outcome.
  ///
  /// [frameProvider] is only invoked once this frame has already passed
  /// the ML-Kit-only checks (face count/size/center/pose/eyes) — i.e.
  /// never for the common "no face" / "multiple faces" frames while the
  /// operator is still positioning themselves. Decoding a camera frame
  /// into an RGB `img.Image` is real, non-trivial work (see
  /// `CameraFrameConverter.toRgbImage`'s own doc comment); this keeps the
  /// caller from paying that cost on frames that were never going to be
  /// used anyway.
  Future<FaceEnrollmentState> evaluateAndCapture({
    required img.Image Function() frameProvider,
    required List<DetectedFace> faces,
    required Size imageSize,
    int rotationDegrees = 0,
  }) async {
    if (_accepted.length >= requiredSamples) {
      return _state(FaceEnrollmentStatus.processing);
    }

    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotationDegrees,
    );
    final earlyStatus = _statusForIssue(quality.primaryIssue);
    if (earlyStatus != null) {
      _stableGoodFrames = 0;
      return _state(
        earlyStatus,
        offsetDirection: earlyStatus == FaceEnrollmentStatus.offCenter
            ? quality.offsetDirection
            : null,
      );
    }

    final face = faces.single;
    final frame = frameProvider();
    final pixelIssue = FrameQualityAnalyzer.evaluate(frame, face.boundingBox);
    final pixelStatus = _statusForIssue(pixelIssue);
    if (pixelStatus != null) {
      _stableGoodFrames = 0;
      return _state(pixelStatus);
    }

    if (_accepted.isEmpty) {
      _stableGoodFrames++;
      if (_stableGoodFrames < _requiredStableFrames) {
        return _state(FaceEnrollmentStatus.holdStill);
      }
    }

    final now = DateTime.now();
    if (_lastAcceptedAt != null &&
        now.difference(_lastAcceptedAt!) < _minSampleInterval) {
      return _state(FaceEnrollmentStatus.holdStill);
    }

    final aligned = FaceAlignmentService.align(
      sourceImage: frame,
      face: face,
    );
    final embedding = await embeddingService.embed(aligned);

    if (_accepted.length >= 2 && _cosineToCentroid(embedding) < outlierSimilarityFloor) {
      return _state(FaceEnrollmentStatus.holdStill);
    }

    _accepted.add(embedding);
    _lastAcceptedAt = now;

    return _state(
      _accepted.length >= requiredSamples
          ? FaceEnrollmentStatus.processing
          : FaceEnrollmentStatus.capturing,
    );
  }

  /// Builds the final representative template from accepted samples and
  /// checks it for duplicates. Thin wrapper around [buildTemplate] — see
  /// that method's doc comment for the actual logic. Split out mainly so
  /// [buildTemplate] can be unit-tested directly with synthetic
  /// embeddings: `FaceEmbeddingService` needs a real on-device TFLite
  /// interpreter (see its own doc comment on why that can't run in this
  /// dev environment), so nothing that depends on live [embed] calls —
  /// i.e. [_accepted] itself — can be exercised outside a real device.
  Future<FaceEnrollmentResult> finalizeEnrollment({
    required String operatorId,
  }) {
    return buildTemplate(
      operatorId: operatorId,
      samples: _accepted,
      templateRepository: templateRepository,
      requiredSamples: requiredSamples,
      minSurvivingSamples: minSurvivingSamples,
    );
  }

  /// Pure(ish) core of enrollment finalization, independent of any live
  /// capture session: drops residual outliers in [samples] relative to
  /// their own centroid, averages + L2-normalizes the survivors, then
  /// checks the result against every *other* operator's template in
  /// [templateRepository] — [operatorId]'s own prior template (if any,
  /// e.g. during re-enrollment) is excluded, since matching yourself is
  /// expected, not a "registered to someone else" conflict. Returns
  /// [FaceEnrollmentFailureReason.duplicateFace] on a hit. Never writes
  /// anything — persistence is the caller's job (see this class's doc
  /// comment).
  static Future<FaceEnrollmentResult> buildTemplate({
    required String operatorId,
    required List<List<double>> samples,
    required FaceTemplateRepository templateRepository,
    int requiredSamples = 7,
    int minSurvivingSamples = 5,
  }) async {
    if (samples.length < requiredSamples) {
      return const FaceEnrollmentResult.failure(
        FaceEnrollmentFailureReason.insufficientSamples,
      );
    }

    final centroid = FaceEmbeddingService.l2Normalize(_mean(samples));
    final survivors = samples
        .where(
          (e) =>
              FaceMatchingService.cosineSimilarity(e, centroid) >=
              outlierSimilarityFloor,
        )
        .toList();

    if (survivors.length < minSurvivingSamples) {
      return const FaceEnrollmentResult.failure(
        FaceEnrollmentFailureReason.insufficientSamples,
      );
    }

    final representative = FaceEmbeddingService.l2Normalize(_mean(survivors));

    final otherTemplates = (await templateRepository.getAll())
        .where((t) => t.operatorId != operatorId)
        .toList();
    final match = FaceMatchingService.match(
      liveEmbedding: representative,
      candidates: otherTemplates,
      currentModelVersion: FaceEmbeddingService.modelVersion,
    );
    if (match.isMatch) {
      return const FaceEnrollmentResult.failure(
        FaceEnrollmentFailureReason.duplicateFace,
      );
    }

    final template = FaceTemplate(
      templateId: const Uuid().v4(),
      operatorId: operatorId,
      embedding: representative,
      modelVersion: FaceEmbeddingService.modelVersion,
      createdAt: DateTime.now(),
    );
    return FaceEnrollmentResult.success(template);
  }

  double _cosineToCentroid(List<double> embedding) {
    final centroid = FaceEmbeddingService.l2Normalize(_mean(_accepted));
    return FaceMatchingService.cosineSimilarity(embedding, centroid);
  }

  static List<double> _mean(List<List<double>> vectors) {
    final length = vectors.first.length;
    final sums = List<double>.filled(length, 0);
    for (final vector in vectors) {
      for (var i = 0; i < length; i++) {
        sums[i] += vector[i];
      }
    }
    return [for (final s in sums) s / vectors.length];
  }

  FaceEnrollmentState _state(
    FaceEnrollmentStatus status, {
    FaceOffsetDirection? offsetDirection,
  }) => FaceEnrollmentState(
    status: status,
    samplesCaptured: _accepted.length,
    samplesRequired: requiredSamples,
    offsetDirection: offsetDirection,
  );

  static FaceEnrollmentStatus? _statusForIssue(FaceQualityIssue? issue) {
    return switch (issue) {
      null => null,
      FaceQualityIssue.noFaceDetected => FaceEnrollmentStatus.positioning,
      FaceQualityIssue.multipleFacesDetected =>
        FaceEnrollmentStatus.multipleFaces,
      FaceQualityIssue.faceTooSmall => FaceEnrollmentStatus.tooFar,
      FaceQualityIssue.faceTooLarge => FaceEnrollmentStatus.tooClose,
      FaceQualityIssue.offCenter => FaceEnrollmentStatus.offCenter,
      FaceQualityIssue.extremePose => FaceEnrollmentStatus.lookStraight,
      FaceQualityIssue.eyesNotVisible => FaceEnrollmentStatus.lookStraight,
      FaceQualityIssue.poorLighting => FaceEnrollmentStatus.poorLighting,
      FaceQualityIssue.tooBlurry => FaceEnrollmentStatus.holdStill,
    };
  }
}
