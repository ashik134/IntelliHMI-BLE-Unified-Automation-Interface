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

enum _Phase { stabilizing, scanning }

/// Orchestrates one enrollment session as a single continuous biometric
/// scan: [_Phase.stabilizing] waits for the operator to hold a good frame
/// for [stabilizeDuration], then [_Phase.scanning] runs for a fixed
/// [scanDuration] wall-clock window, silently sampling embeddings from
/// whichever frames clear quality, before [finalizeEnrollment] reduces
/// whatever was collected to a single representative [FaceTemplate].
///
/// The on-screen status during [_Phase.scanning] never leaves
/// [FaceEnrollmentStatus.scanning] for a merely transient problem — see
/// [_maxScanDisruption] — which is what turns the old per-frame
/// capturing/holdStill/invalid flicker into one locked "Scanning your
/// face…" state with a smoothly advancing [FaceEnrollmentState.scanProgress].
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
/// never carry biometric payloads either. Only the accepted embeddings
/// (never a raw frame, and never the camera stream itself) are ever held
/// in memory, and even those are discarded once [finalizeEnrollment]
/// returns — nothing from a scan is ever written to disk except the
/// single final template the caller chooses to persist.
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
    this.requiredSamples = 8,
    this.minSurvivingSamples = 6,
  });

  final FaceEmbeddingService embeddingService;
  final FaceTemplateRepository templateRepository;

  /// Minimum total accepted samples (pre-outlier-trim) [finalizeEnrollment]
  /// will even attempt to build a template from. Since samples now
  /// accumulate throughout [scanDuration] rather than being the scan's
  /// stopping condition, this is a floor on scan quality, not a target the
  /// scan runs until it hits — a scan can end with fewer than this if the
  /// operator moved too much or lighting was too unstable, and
  /// [finalizeEnrollment] then correctly fails instead of building a weak
  /// template from too little evidence.
  final int requiredSamples;

  /// Minimum accepted samples that must survive outlier-trimming in
  /// [finalizeEnrollment] for the resulting template to be trusted. Kept
  /// at the same ~70-75% ratio of [requiredSamples] as before, not a fixed
  /// absolute floor, so raising [requiredSamples] doesn't quietly loosen
  /// how many samples are allowed to be trimmed as outliers.
  final int minSurvivingSamples;

  /// How long a frame must continuously clear every quality gate before
  /// the scan begins — long enough that a single lucky frame out of a
  /// resting/positioning state can't trigger it (the old
  /// "waits, then suddenly captures" problem), short enough to still read
  /// as "hold still" rather than a stall. Matches
  /// `LivenessSession._requiredHoldDuration`'s pose-hold duration, the
  /// existing precedent elsewhere in this codebase for "how long counts as
  /// deliberately held, not incidental."
  static const Duration stabilizeDuration = Duration(milliseconds: 600);

  /// Total continuous scan window, within the spec's "about 4-5 seconds."
  static const Duration scanDuration = Duration(milliseconds: 4500);

  /// Minimum time between two accepted samples, so samples collected
  /// across [scanDuration] reflect natural micro-movement rather than
  /// near-identical consecutive frames, and so the (comparatively
  /// expensive) embedding model isn't run on every single processed frame
  /// — this is the "throttled rate" the continuous scan analyzes at.
  static const Duration _minSampleInterval = Duration(milliseconds: 400);

  /// How long a disruption (no face / multiple faces / bad pose / poor
  /// pixel quality / an embedding that doesn't match the locked identity)
  /// must persist *during* [_Phase.scanning] before the scan aborts and
  /// restarts from [_Phase.stabilizing]. A single bad frame — a blink, a
  /// momentary autofocus hunt, one blurry frame — is silently skipped and
  /// never reaches this; only a genuinely sustained problem (face actually
  /// lost, a second person actually stepped in, someone else actually
  /// replacing the enrolling operator) restarts the scan. Deliberately
  /// longer than [stabilizeDuration]: aborting a scan already in progress
  /// should take more convincing than starting one, or a scan that's 90%
  /// done would restart on the same kind of noise stabilizing already
  /// tolerates.
  static const Duration _maxScanDisruption = Duration(milliseconds: 900);

  /// A candidate sample must be at least this cosine-similar to the
  /// relevant running centroid to be accepted — used both to decide
  /// whether an early sample is mutually consistent enough to join the
  /// identity-locking seed pool (see [_seeds]), and, once locked, whether
  /// a later sample still matches the locked identity. Deliberately looser
  /// than `FaceMatchingService.defaultThreshold` (0.87): these are same-
  /// session, same-person samples, which should already cluster tightly,
  /// so this only needs to catch genuine outliers/impostors, not add
  /// pose-tolerance margin on top of the tolerance the quality gates
  /// already allow.
  static const double outlierSimilarityFloor = 0.75;

  /// Number of mutually-consistent early embeddings required to lock the
  /// enrollment identity (see [_seeds]/[_identityLocked]) — chosen so a
  /// single early outlier embedding can't lock onto the wrong identity by
  /// itself, without requiring so many that identity lock meaningfully
  /// delays sample collection within the fixed [scanDuration] window.
  static const int _identityLockSeedCount = 3;

  _Phase _phase = _Phase.stabilizing;
  DateTime? _stableSince;
  DateTime? _scanStartedAt;
  DateTime? _disruptionStartedAt;

  /// Early scanning-phase embeddings not yet confirmed mutually consistent
  /// enough to lock the enrollment identity — see [_tryAccept]. Promoted
  /// into [_accepted] all at once the moment identity locks, so a sample
  /// collected before lock is held to exactly the same consistency bar as
  /// one collected after (it must already have matched the other seeds),
  /// not silently grandfathered in.
  final List<List<double>> _seeds = [];
  bool _identityLocked = false;

  final List<List<double>> _accepted = [];
  DateTime? _lastAcceptedAt;

  int get samplesCaptured => _accepted.length;

  /// Debug-diagnostics-only: whether the scan phase has been entered.
  bool get isScanning => _phase == _Phase.scanning;

  /// Debug-diagnostics-only: fraction (0.0..1.0) of [stabilizeDuration]
  /// elapsed so far, or 0 if no continuous good frame is currently being
  /// held. Meaningless once [isScanning] is true.
  double get stableProgress {
    final since = _stableSince;
    if (since == null) return 0;
    final elapsed = DateTime.now().difference(since).inMilliseconds;
    return (elapsed / stabilizeDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Debug-diagnostics-only: whether enough mutually-consistent early
  /// samples have been seen to lock the enrollment identity for this scan.
  bool get identityLocked => _identityLocked;

  /// Clears all in-memory samples and returns to [_Phase.stabilizing] —
  /// used on cancel/retry and whenever a sustained scan disruption forces
  /// a restart. Nothing was ever written to disk, so there's nothing else
  /// to undo.
  void reset() {
    _phase = _Phase.stabilizing;
    _stableSince = null;
    _scanStartedAt = null;
    _disruptionStartedAt = null;
    _seeds.clear();
    _identityLocked = false;
    _accepted.clear();
    _lastAcceptedAt = null;
  }

  /// Evaluates one already-detected frame and advances the enrollment
  /// state machine by exactly one step. Always returns a state to render —
  /// never throws for an ordinary "this frame isn't good enough" outcome.
  ///
  /// [frameProvider] is only invoked once this frame has already passed
  /// the ML-Kit-only checks (face count/size/center/pose/eyes) — i.e.
  /// never for the common "no face" / "multiple faces" frames while the
  /// operator is still positioning themselves. Decoding a camera frame
  /// into an RGB `img.Image` is real, non-trivial work (see
  /// `CameraFrameConverter.toRgbImage`'s own doc comment); this keeps the
  /// caller from paying that cost on frames that were never going to be
  /// used anyway. The (more expensive still) embedding model is throttled
  /// further still by [_minSampleInterval], regardless of phase.
  Future<FaceEnrollmentState> evaluateAndCapture({
    required img.Image Function() frameProvider,
    required List<DetectedFace> faces,
    required Size imageSize,
    int rotationDegrees = 0,
  }) async {
    final now = DateTime.now();
    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotationDegrees,
    );
    final earlyStatus = _statusForIssue(quality.primaryIssue);

    if (_phase == _Phase.stabilizing) {
      final result = await _evaluateStabilizing(
        now: now,
        earlyStatus: earlyStatus,
        offsetDirection: quality.offsetDirection,
        frameProvider: frameProvider,
        faces: faces,
      );
      if (result != null) return result;
      // Stability threshold just cleared this frame — fall through and
      // spend this same frame as the scan's first frame rather than
      // discarding it and waiting for the next one.
    }

    return _evaluateScanning(
      now: now,
      earlyStatus: earlyStatus,
      frameProvider: frameProvider,
      faces: faces,
    );
  }

  /// Returns a state to render if the operator isn't ready to start
  /// scanning yet, or null once [stabilizeDuration] has just been cleared
  /// (in which case [_phase] has already been advanced to
  /// [_Phase.scanning] and the caller should immediately evaluate this
  /// same frame as a scanning frame).
  Future<FaceEnrollmentState?> _evaluateStabilizing({
    required DateTime now,
    required FaceEnrollmentStatus? earlyStatus,
    required FaceOffsetDirection? offsetDirection,
    required img.Image Function() frameProvider,
    required List<DetectedFace> faces,
  }) async {
    if (earlyStatus != null) {
      _stableSince = null;
      return _state(
        earlyStatus,
        offsetDirection: earlyStatus == FaceEnrollmentStatus.offCenter
            ? offsetDirection
            : null,
      );
    }

    final face = faces.single;
    final frame = frameProvider();
    final pixelStatus = _statusForIssue(
      FrameQualityAnalyzer.evaluate(frame, face.boundingBox),
    );
    if (pixelStatus != null) {
      _stableSince = null;
      return _state(pixelStatus);
    }

    _stableSince ??= now;
    if (now.difference(_stableSince!) < stabilizeDuration) {
      return _state(FaceEnrollmentStatus.holdStill);
    }

    _phase = _Phase.scanning;
    _scanStartedAt = now;
    _disruptionStartedAt = null;
    return null;
  }

  Future<FaceEnrollmentState> _evaluateScanning({
    required DateTime now,
    required FaceEnrollmentStatus? earlyStatus,
    required img.Image Function() frameProvider,
    required List<DetectedFace> faces,
  }) async {
    final elapsed = now.difference(_scanStartedAt!);
    if (elapsed >= scanDuration) {
      return _state(FaceEnrollmentStatus.processing, scanProgress: 1.0);
    }
    final progress =
        elapsed.inMilliseconds / scanDuration.inMilliseconds;

    // Null once this frame is set below, this is the specific guidance to
    // fall back to if disruption ends up sustained enough to restart the
    // scan (see below) — kept specific (e.g. "Improve lighting") rather
    // than collapsed to one generic "disrupted" flag, so a restart still
    // tells the operator exactly what to fix.
    var disruptionStatus = earlyStatus;
    if (disruptionStatus == null) {
      final face = faces.single;
      final frame = frameProvider();
      final pixelIssue = FrameQualityAnalyzer.evaluate(
        frame,
        face.boundingBox,
      );
      if (pixelIssue != null) {
        disruptionStatus = _statusForIssue(pixelIssue);
      } else if (_lastAcceptedAt == null ||
          now.difference(_lastAcceptedAt!) >= _minSampleInterval) {
        final aligned = FaceAlignmentService.align(
          sourceImage: frame,
          face: face,
        );
        final embedding = await embeddingService.embed(aligned);
        final consistent = _tryAccept(embedding, now);
        if (_identityLocked && !consistent) {
          disruptionStatus = FaceEnrollmentStatus.holdStill;
        }
      }
    }

    if (disruptionStatus != null) {
      _disruptionStartedAt ??= now;
      if (now.difference(_disruptionStartedAt!) >= _maxScanDisruption) {
        reset();
        return _state(disruptionStatus);
      }
    } else {
      _disruptionStartedAt = null;
    }

    return _state(FaceEnrollmentStatus.scanning, scanProgress: progress);
  }

  /// Folds one good-quality, already-embedded sample into the running
  /// identity, or rejects it. Returns false only when [embedding] fails to
  /// match an *already-locked* identity (a genuine mismatch worth counting
  /// toward [_maxScanDisruption]); an inconsistent pre-lock seed candidate
  /// is silently dropped and reported as consistent, since before lock
  /// there's no established identity yet for it to be inconsistent
  /// *with* — see [_seeds]'s doc comment.
  bool _tryAccept(List<double> embedding, DateTime now) {
    _lastAcceptedAt = now;

    if (!_identityLocked) {
      if (_seeds.isEmpty ||
          FaceMatchingService.cosineSimilarity(
                embedding,
                FaceEmbeddingService.l2Normalize(_mean(_seeds)),
              ) >=
              outlierSimilarityFloor) {
        _seeds.add(embedding);
      }
      if (_seeds.length >= _identityLockSeedCount) {
        _identityLocked = true;
        _accepted.addAll(_seeds);
      }
      return true;
    }

    final centroid = FaceEmbeddingService.l2Normalize(_mean(_accepted));
    if (FaceMatchingService.cosineSimilarity(embedding, centroid) <
        outlierSimilarityFloor) {
      return false;
    }

    _accepted.add(embedding);
    return true;
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
    double? scanProgress,
  }) => FaceEnrollmentState(
    status: status,
    offsetDirection: offsetDirection,
    scanProgress: scanProgress,
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
