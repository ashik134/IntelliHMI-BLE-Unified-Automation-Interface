import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_pose.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/liveness_challenge.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/face_alignment_service.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_geometry_validator.dart';
import 'package:rev_crane_control_ops/services/face_liveness_service.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';

/// Orchestrates one enrollment session as a discrete guided-pose state
/// machine (spec section 14):
///
/// ```
/// acquiringFace -> waitingForStability -> [livenessCheck, frontal only]
///   -> capturingPose -> (next pose) waitingForStability -> ...
///   -> generatingTemplate -> success | duplicate | insufficientSamples
/// ```
///
/// [poseSequence] (default: Front, Left, Right, Up) is walked one pose at
/// a time. Each pose independently requires: the shared quality gate
/// (`FaceDetectionService.evaluateQuality`), landmark safe-region
/// containment (`FaceGeometryValidator`), pixel quality
/// (`FrameQualityAnalyzer`), and — for non-frontal poses — a matching
/// head angle (`matchesPoseTarget`), all held continuously for
/// [FaceEnrollmentConfig.stabilizeDuration] before a short best-frame
/// capture window opens (spec section 8/9): every good frame in that
/// window is scored, and only the single best-scoring frame is aligned
/// and embedded — one sample per pose, not an accumulating pile of
/// near-duplicates.
///
/// Liveness (spec section 11) is integrated, not bolted on: a single
/// `blink` challenge runs once, before the frontal pose's capture window,
/// as an anti-static-photo gate; the Left/Right/Up poses' own angle-hold
/// requirement doubles as an ongoing liveness signal (a static photo
/// can't turn on cue), so there's no second redundant challenge per pose.
///
/// A disruption during a pose (face lost, second face, pose lost, poor
/// pixel quality) that persists past [FaceEnrollmentConfig.maxPoseDisruption]
/// retries *that pose only* — earlier accepted poses are never discarded
/// (spec section 14's "failure conditions should return to the
/// appropriate state instead of restarting the entire enrollment").
///
/// Deliberately has no dependency on `camera` or
/// `google_mlkit_face_detection` — only on [DetectedFace]/`img.Image` and
/// the other face services — so it's unit-testable with fakes.
///
/// Never logs or prints a frame or an embedding. Only the accepted
/// embeddings (never a raw frame) are ever held in memory, discarded once
/// [finalizeEnrollment] returns.
///
/// Persistence is deliberately NOT this class's job: [finalizeEnrollment]
/// returns a [FaceTemplate] but never writes it — the caller
/// (`AddOperatorScreen`/`OperatorDetailScreen`) owns the atomic
/// template-then-operator write.
class FaceEnrollmentService {
  FaceEnrollmentService({
    required this.embeddingService,
    required this.templateRepository,
    this.config = FaceEnrollmentConfig.defaults,
    this.poseSequence = const [
      FacePose.frontal,
      FacePose.left,
      FacePose.right,
      FacePose.up,
    ],
  }) : assert(poseSequence.isNotEmpty);

  final FaceEmbeddingService embeddingService;
  final FaceTemplateRepository templateRepository;
  final FaceEnrollmentConfig config;
  final List<FacePose> poseSequence;

  /// A candidate sample must be at least this cosine-similar to the
  /// running identity centroid to be accepted — mirrors
  /// [FaceEnrollmentConfig.outlierSimilarityFloor]; kept as a named
  /// static constant (rather than threaded through [config]) because
  /// [buildTemplate] is a static method with its own existing signature
  /// that callers/tests already depend on.
  static const double outlierSimilarityFloor = 0.75;

  FaceEnrollmentPhase _phase = FaceEnrollmentPhase.acquiringFace;
  int _poseIndex = 0;
  DateTime? _stableSince;
  bool _blinkDone = false;
  LivenessSession? _livenessSession;
  DateTime? _disruptionStartedAt;

  DateTime? _captureWindowStartedAt;
  DateTime? _lastCandidateAt;
  double? _bestScore;
  DetectedFace? _bestFace;
  img.Image? _bestFrame;

  final List<List<double>> _accepted = [];

  FacePose get _currentPose => poseSequence[_poseIndex];

  /// The pose currently being targeted, regardless of which sub-phase is
  /// active — unlike [FaceEnrollmentState.currentPose] (which is only set
  /// while actively waiting/capturing), this is always defined until
  /// every pose has been accepted. Debug-diagnostics-only.
  FacePose? get debugCurrentPose =>
      _poseIndex < poseSequence.length ? poseSequence[_poseIndex] : null;

  int get samplesCaptured => _accepted.length;

  /// Debug-diagnostics-only: whether the capture window for the current
  /// pose is open.
  bool get isCapturingPose => _phase == FaceEnrollmentPhase.capturingPose;

  /// Debug-diagnostics-only: fraction (0.0..1.0) of
  /// [FaceEnrollmentConfig.stabilizeDuration] elapsed so far, or 0 if no
  /// continuous good/pose-matched frame is currently being held.
  double get stableProgress {
    final since = _stableSince;
    if (since == null) return 0;
    final elapsed = DateTime.now().difference(since).inMilliseconds;
    return (elapsed / config.stabilizeDuration.inMilliseconds).clamp(0.0, 1.0);
  }

  /// Debug-diagnostics-only: whether at least one pose sample has been
  /// accepted yet, i.e. later poses now have an identity centroid to be
  /// checked against.
  bool get hasIdentityAnchor => _accepted.isNotEmpty;

  /// Clears all in-memory samples and returns to the first pose — used on
  /// cancel/retry.
  void reset() {
    _phase = FaceEnrollmentPhase.acquiringFace;
    _poseIndex = 0;
    _stableSince = null;
    _blinkDone = false;
    _livenessSession = null;
    _disruptionStartedAt = null;
    _captureWindowStartedAt = null;
    _lastCandidateAt = null;
    _bestScore = null;
    _bestFace = null;
    _bestFrame = null;
    _accepted.clear();
  }

  /// Evaluates one already-detected frame and advances the enrollment
  /// state machine by at most one step, returning the state to render.
  /// Never throws for an ordinary "this frame isn't good enough" outcome.
  Future<FaceEnrollmentState> evaluateAndCapture({
    required img.Image Function() frameProvider,
    required List<DetectedFace> faces,
    required Size imageSize,
    int rotationDegrees = 0,
  }) async {
    final now = DateTime.now();

    // Memoize the (real, non-trivial) decode so a single incoming frame
    // is decoded at most once per call, however many sub-checks need it.
    img.Image? cachedFrame;
    img.Image frame() => cachedFrame ??= frameProvider();

    if (_phase == FaceEnrollmentPhase.acquiringFace ||
        _phase == FaceEnrollmentPhase.waitingForStability) {
      final result = await _evaluateAcquiringOrWaiting(
        now: now,
        faces: faces,
        imageSize: imageSize,
        rotationDegrees: rotationDegrees,
        frame: frame,
      );
      if (result != null) return result;
      // Stability just cleared on this frame — fall through and spend it
      // as the next phase's first frame too, rather than discarding it.
    }

    if (_phase == FaceEnrollmentPhase.livenessCheck) {
      final result = _evaluateLiveness(
        now: now,
        faces: faces,
        imageSize: imageSize,
        rotationDegrees: rotationDegrees,
      );
      if (result != null) return result;
    }

    if (_phase == FaceEnrollmentPhase.capturingPose) {
      return _evaluateCapturing(
        now: now,
        faces: faces,
        imageSize: imageSize,
        rotationDegrees: rotationDegrees,
        frame: frame,
      );
    }

    // Terminal phases (generatingTemplate/complete/failed/duplicate) —
    // the screen stops streaming frames once one of these is reached, so
    // this is only reached by a stray already-in-flight frame.
    return _state();
  }

  // ── Acquiring / waiting for stability ────────────────────────────────

  Future<FaceEnrollmentState?> _evaluateAcquiringOrWaiting({
    required DateTime now,
    required List<DetectedFace> faces,
    required Size imageSize,
    required int rotationDegrees,
    required img.Image Function() frame,
  }) async {
    final pose = _currentPose;
    final readiness = await _evaluateReadiness(
      faces: faces,
      imageSize: imageSize,
      rotationDegrees: rotationDegrees,
      pose: pose,
      frame: frame,
    );

    if (readiness.issue != null) {
      _stableSince = null;
      _phase = FaceEnrollmentPhase.acquiringFace;
      return _state(
        blockingIssue: readiness.issue,
        offsetDirection: readiness.offsetDirection,
      );
    }

    if (!readiness.poseMatched) {
      _stableSince = null;
      _phase = FaceEnrollmentPhase.waitingForStability;
      return _state(currentPose: pose);
    }

    _phase = FaceEnrollmentPhase.waitingForStability;
    _stableSince ??= now;
    if (now.difference(_stableSince!) < config.stabilizeDuration) {
      return _state(currentPose: pose);
    }
    _stableSince = null;

    if (pose == FacePose.frontal && !_blinkDone) {
      _phase = FaceEnrollmentPhase.livenessCheck;
      _livenessSession = LivenessSession(
        LivenessChallengeType.blink,
        timeout: config.livenessTimeout,
        config: config,
      );
      _disruptionStartedAt = null;
      return null;
    }

    _beginCaptureWindow(now);
    return null;
  }

  // ── Liveness (frontal pose only, once per session) ───────────────────

  FaceEnrollmentState? _evaluateLiveness({
    required DateTime now,
    required List<DetectedFace> faces,
    required Size imageSize,
    required int rotationDegrees,
  }) {
    final session = _livenessSession!;

    if (faces.length != 1) {
      return _resolveLiveness(
        session.processFrame(faceCount: faces.length, now: now),
        now,
      );
    }

    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotationDegrees,
      config: config,
    );
    if (quality.primaryIssue != null) {
      _disruptionStartedAt ??= now;
      if (now.difference(_disruptionStartedAt!) >= config.maxPoseDisruption) {
        _livenessSession = null;
        _phase = FaceEnrollmentPhase.waitingForStability;
        return _state(
          blockingIssue: quality.primaryIssue,
          offsetDirection: quality.offsetDirection,
        );
      }
      return _state(
        livenessInstruction: session.challenge.instruction,
        progress: 0,
      );
    }
    _disruptionStartedAt = null;

    return _resolveLiveness(
      session.processFrame(faceCount: 1, face: faces.single, now: now),
      now,
    );
  }

  FaceEnrollmentState? _resolveLiveness(
    LivenessChallengeState state,
    DateTime now,
  ) {
    if (state.completed) {
      _livenessSession = null;
      _blinkDone = true;
      _beginCaptureWindow(now);
      return null;
    }

    if (state.failed || state.timedOut) {
      // Not a full-session failure — just retry this (frontal) pose's
      // stability hold, same as a sustained capture-window disruption
      // does elsewhere.
      _livenessSession = null;
      _phase = FaceEnrollmentPhase.waitingForStability;
      return _state(currentPose: _currentPose);
    }

    return _state(
      livenessInstruction: state.challenge.instruction,
      progress: state.progress,
    );
  }

  // ── Capturing (best-frame selection window) ──────────────────────────

  void _beginCaptureWindow(DateTime now) {
    _phase = FaceEnrollmentPhase.capturingPose;
    _captureWindowStartedAt = now;
    _lastCandidateAt = null;
    _bestScore = null;
    _bestFace = null;
    _bestFrame = null;
    _disruptionStartedAt = null;
  }

  Future<FaceEnrollmentState> _evaluateCapturing({
    required DateTime now,
    required List<DetectedFace> faces,
    required Size imageSize,
    required int rotationDegrees,
    required img.Image Function() frame,
  }) async {
    final pose = _currentPose;
    final elapsed = now.difference(_captureWindowStartedAt!);

    final readiness = await _evaluateReadiness(
      faces: faces,
      imageSize: imageSize,
      rotationDegrees: rotationDegrees,
      pose: pose,
      frame: frame,
    );

    if (readiness.issue == null && readiness.poseMatched) {
      _disruptionStartedAt = null;
      if (_lastCandidateAt == null ||
          now.difference(_lastCandidateAt!) >= config.minSampleInterval) {
        _lastCandidateAt = now;
        final score = FrameQualityAnalyzer.qualityScore(
          frame(),
          readiness.face!.boundingBox,
        );
        if (_bestScore == null || score > _bestScore!) {
          _bestScore = score;
          _bestFace = readiness.face;
          _bestFrame = frame();
        }
      }
    } else {
      _disruptionStartedAt ??= now;
      if (now.difference(_disruptionStartedAt!) >= config.maxPoseDisruption) {
        // Sustained disruption mid-window — abandon this window and
        // retry the same pose's stability hold, not the whole session.
        _phase = FaceEnrollmentPhase.waitingForStability;
        _captureWindowStartedAt = null;
        return _state(
          blockingIssue: readiness.issue,
          offsetDirection: readiness.offsetDirection,
          currentPose: pose,
        );
      }
    }

    if (elapsed < config.poseCaptureWindow) {
      return _state(
        currentPose: pose,
        progress:
            elapsed.inMilliseconds / config.poseCaptureWindow.inMilliseconds,
      );
    }

    return _closeCaptureWindow(pose);
  }

  Future<FaceEnrollmentState> _closeCaptureWindow(FacePose pose) async {
    final bestFace = _bestFace;
    final bestFrame = _bestFrame;
    _captureWindowStartedAt = null;

    if (bestFace == null || bestFrame == null) {
      // Never got a single good, sampled frame in the window — retry the
      // pose's stability hold rather than failing the whole session.
      _phase = FaceEnrollmentPhase.waitingForStability;
      return _state(currentPose: pose);
    }

    final aligned = FaceAlignmentService.align(
      sourceImage: bestFrame,
      face: bestFace,
    );
    final embedding = await embeddingService.embed(aligned);

    if (_accepted.isNotEmpty) {
      final centroid = FaceEmbeddingService.l2Normalize(_mean(_accepted));
      if (FaceMatchingService.cosineSimilarity(embedding, centroid) <
          outlierSimilarityFloor) {
        // Doesn't look consistent with earlier accepted poses (a person
        // swap mid-session, or a genuinely bad sample) — retry this pose
        // rather than silently accepting a mismatched sample.
        _phase = FaceEnrollmentPhase.waitingForStability;
        return _state(currentPose: pose);
      }
    }

    _accepted.add(embedding);
    _poseIndex++;

    if (_poseIndex >= poseSequence.length) {
      _phase = FaceEnrollmentPhase.generatingTemplate;
      return _state();
    }

    _phase = FaceEnrollmentPhase.waitingForStability;
    return _state(currentPose: _currentPose);
  }

  // ── Shared per-frame readiness check ─────────────────────────────────

  Future<_Readiness> _evaluateReadiness({
    required List<DetectedFace> faces,
    required Size imageSize,
    required int rotationDegrees,
    required FacePose pose,
    required img.Image Function() frame,
  }) async {
    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotationDegrees,
      config: config,
    );
    if (quality.primaryIssue != null) {
      return _Readiness(
        issue: quality.primaryIssue,
        offsetDirection: quality.offsetDirection,
      );
    }

    final face = faces.single;
    final geometry = FaceGeometryValidator.evaluate(
      face: face,
      imageSize: imageSize,
      rotationDegrees: rotationDegrees,
      pose: pose,
      config: config,
    );
    if (!geometry.landmarksPresent) {
      return _Readiness(issue: FaceQualityIssue.missingLandmarks, face: face);
    }
    if (!geometry.landmarksContained) {
      return _Readiness(
        issue: FaceQualityIssue.landmarksOutsideSafeRegion,
        face: face,
      );
    }

    final pixelIssue = FrameQualityAnalyzer.evaluate(
      frame(),
      face.boundingBox,
      config: config,
    );
    if (pixelIssue != null) {
      return _Readiness(issue: pixelIssue, face: face);
    }

    return _Readiness(
      poseMatched: matchesPoseTarget(pose, face, config),
      face: face,
    );
  }

  // ── Finalization ──────────────────────────────────────────────────────

  /// Builds the final representative template from accepted samples and
  /// checks it for duplicates — thin wrapper around [buildTemplate].
  Future<FaceEnrollmentResult> finalizeEnrollment({
    required String operatorId,
  }) {
    final minSurviving = (poseSequence.length * config.minSurvivingPoseFraction)
        .ceil()
        .clamp(1, poseSequence.length);
    return buildTemplate(
      operatorId: operatorId,
      samples: _accepted,
      templateRepository: templateRepository,
      requiredSamples: poseSequence.length,
      minSurvivingSamples: minSurviving,
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
    int requiredSamples = 4,
    int minSurvivingSamples = 3,
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

  FaceEnrollmentState _state({
    FaceQualityIssue? blockingIssue,
    FaceOffsetDirection? offsetDirection,
    String? livenessInstruction,
    FacePose? currentPose,
    double? progress,
  }) => FaceEnrollmentState(
    phase: _phase,
    blockingIssue: blockingIssue,
    offsetDirection: offsetDirection,
    livenessInstruction: livenessInstruction,
    currentPose: currentPose,
    progress: progress,
    poses: [
      for (var i = 0; i < poseSequence.length; i++)
        PoseProgress(
          pose: poseSequence[i],
          accepted: i < _poseIndex,
          isCurrent: i == _poseIndex && i < poseSequence.length,
        ),
    ],
  );
}

class _Readiness {
  const _Readiness({
    this.issue,
    this.offsetDirection,
    this.poseMatched = false,
    this.face,
  });

  final FaceQualityIssue? issue;
  final FaceOffsetDirection? offsetDirection;
  final bool poseMatched;
  final DetectedFace? face;
}
