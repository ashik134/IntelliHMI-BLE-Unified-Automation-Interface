import 'package:rev_crane_control_ops/models/face_pose.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';

/// Coarse phase of the enrollment state machine (spec section 14).
///
/// `SEARCHING_FOR_FACE` and `VALIDATING_FACE` from the spec's conceptual
/// diagram are both represented by [acquiringFace] here, distinguished by
/// [FaceEnrollmentState.blockingIssue] (`noFaceDetected` == searching,
/// anything else == validating) rather than as separate enum cases —
/// [FaceQualityIssue] already names exactly what's blocking readiness, so
/// duplicating that distinction into a second enum would just be two
/// names for the same fact.
///
/// `GENERATING_EMBEDDINGS`/`VALIDATING_TEMPLATE` are likewise both
/// represented by [generatingTemplate]: both happen synchronously in
/// `FaceEnrollmentService.finalizeEnrollment` with no live camera frames
/// in between (typically well under a second), so there is nothing
/// meaningful to show the operator between them — see that method.
enum FaceEnrollmentPhase {
  initializing,
  requestingPermission,
  permissionDenied,
  cameraError,
  acquiringFace,
  livenessCheck,
  waitingForStability,
  capturingPose,
  generatingTemplate,
  duplicateDetected,
  complete,
  failed,
}

/// One entry in the on-screen pose checklist (spec section 10).
class PoseProgress {
  const PoseProgress({
    required this.pose,
    required this.accepted,
    required this.isCurrent,
  });

  final FacePose pose;
  final bool accepted;
  final bool isCurrent;

  String get label => pose.label;
}

/// Per-frame result of `FaceEnrollmentService.evaluateAndCapture`,
/// rendered by the capture screen on every processed frame.
class FaceEnrollmentState {
  const FaceEnrollmentState({
    required this.phase,
    this.blockingIssue,
    this.offsetDirection,
    this.livenessInstruction,
    this.currentPose,
    this.progress,
    this.poses = const [],
    this.failureMessage,
  });

  const FaceEnrollmentState.initial()
    : phase = FaceEnrollmentPhase.initializing,
      blockingIssue = null,
      offsetDirection = null,
      livenessInstruction = null,
      currentPose = null,
      progress = null,
      poses = const [],
      failureMessage = null;

  final FaceEnrollmentPhase phase;

  /// Set only during [FaceEnrollmentPhase.acquiringFace] — the specific
  /// condition currently blocking readiness (no face / multiple faces /
  /// too far / off-center / outside the safe region / poor lighting /
  /// blurry / etc).
  final FaceQualityIssue? blockingIssue;

  /// Set only when [blockingIssue] is [FaceQualityIssue.offCenter] — which
  /// way the operator should move to recenter.
  final FaceOffsetDirection? offsetDirection;

  /// Set only during [FaceEnrollmentPhase.livenessCheck] — the active
  /// challenge's instruction (e.g. "Blink").
  final String? livenessInstruction;

  /// Set during [FaceEnrollmentPhase.waitingForStability] and
  /// [FaceEnrollmentPhase.capturingPose] — which pose is currently being
  /// captured.
  final FacePose? currentPose;

  /// Fraction (0.0..1.0) of progress through whichever timed sub-phase is
  /// active: the liveness challenge's hold/blink progress during
  /// [FaceEnrollmentPhase.livenessCheck], or the per-pose capture
  /// window's elapsed fraction during [FaceEnrollmentPhase.capturingPose].
  final double? progress;

  /// The full pose checklist and its current accept state — always
  /// populated once capture begins (spec section 10's "✓ Front ✓ Left
  /// ○ Right ○ Up" progress display).
  final List<PoseProgress> poses;

  /// Set only for [FaceEnrollmentPhase.failed] /
  /// [FaceEnrollmentPhase.duplicateDetected] — a specific reason, falling
  /// back to a generic message if unset.
  final String? failureMessage;

  int get acceptedPoseCount => poses.where((p) => p.accepted).length;

  /// User-facing guidance text: directional when available, then the
  /// active liveness instruction, then the current pose's instruction,
  /// then the blocking quality issue's guidance, otherwise a phase-level
  /// fallback.
  String get caption {
    final direction = offsetDirection?.guidance;
    if (direction != null) return direction;

    switch (phase) {
      case FaceEnrollmentPhase.initializing:
        return 'Starting camera…';
      case FaceEnrollmentPhase.requestingPermission:
        return 'Camera permission required';
      case FaceEnrollmentPhase.permissionDenied:
        return 'Camera permission required to enroll a face';
      case FaceEnrollmentPhase.cameraError:
        return 'Camera unavailable';
      case FaceEnrollmentPhase.acquiringFace:
        return blockingIssue?.guidance ?? 'Position your face inside the oval';
      case FaceEnrollmentPhase.livenessCheck:
        return livenessInstruction ?? 'Follow the on-screen instruction';
      case FaceEnrollmentPhase.waitingForStability:
        return currentPose?.instruction ?? 'Hold still';
      case FaceEnrollmentPhase.capturingPose:
        return 'Good — capturing';
      case FaceEnrollmentPhase.generatingTemplate:
        return 'Processing…';
      case FaceEnrollmentPhase.duplicateDetected:
        return failureMessage ??
            'This face is already registered to another operator.';
      case FaceEnrollmentPhase.complete:
        return 'Enrollment complete';
      case FaceEnrollmentPhase.failed:
        return failureMessage ?? 'Enrollment failed';
    }
  }
}
