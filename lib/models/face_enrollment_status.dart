import 'package:rev_crane_control_ops/models/face_quality_result.dart';

/// On-screen state for the live face-enrollment capture flow
/// (`FaceEnrollmentScreen`/`FaceEnrollmentService`). Distinct from
/// [FaceQualityIssue], which only describes *why* a single frame was
/// rejected — this enum also covers states that aren't per-frame quality
/// problems (permissions, camera lifecycle, the continuous scan, the
/// duplicate-face outcome).
///
/// There is deliberately no per-sample "capturing" status: once
/// [scanning] is entered, `FaceEnrollmentService` stays in it for the
/// whole continuous scan window and only ever falls back to an earlier
/// guidance status on a *sustained* problem — see that class's doc
/// comment. A status that flipped back and forth every time one frame's
/// pose/lighting/blur wobbled is exactly the flicker this design replaces.
enum FaceEnrollmentStatus {
  initializing,
  requestingPermission,
  permissionDenied,
  cameraError,
  positioning,
  multipleFaces,
  tooFar,
  tooClose,
  offCenter,
  lookStraight,
  poorLighting,
  holdStill,
  livenessChallenge,
  scanning,
  processing,
  duplicateDetected,
  complete,
  failed,
}

extension FaceEnrollmentStatusCaption on FaceEnrollmentStatus {
  /// User-facing guidance text (spec's example caption list).
  String get caption => switch (this) {
    FaceEnrollmentStatus.initializing => 'Starting camera…',
    FaceEnrollmentStatus.requestingPermission => 'Camera permission required',
    FaceEnrollmentStatus.permissionDenied =>
      'Camera permission required to enroll a face',
    FaceEnrollmentStatus.cameraError => 'Camera unavailable',
    FaceEnrollmentStatus.positioning => 'Position your face',
    FaceEnrollmentStatus.multipleFaces => 'Multiple faces detected',
    FaceEnrollmentStatus.tooFar => 'Move closer',
    FaceEnrollmentStatus.tooClose => 'Move farther away',
    FaceEnrollmentStatus.offCenter => 'Center your face',
    FaceEnrollmentStatus.lookStraight => 'Look straight at the camera',
    FaceEnrollmentStatus.poorLighting =>
      'Still too dark — move to a brighter location',
    FaceEnrollmentStatus.holdStill => 'Hold still',
    // Overridden per-frame by `FaceEnrollmentState.livenessInstruction`
    // while an actual challenge is active — this is only the fallback if
    // that's somehow unset.
    FaceEnrollmentStatus.livenessChallenge => 'Follow the on-screen instruction',
    FaceEnrollmentStatus.scanning => 'Scanning your face…',
    FaceEnrollmentStatus.processing => 'Processing…',
    FaceEnrollmentStatus.duplicateDetected =>
      'This face is already registered to another operator.',
    FaceEnrollmentStatus.complete => 'Enrollment complete',
    FaceEnrollmentStatus.failed => 'Enrollment failed',
  };
}

/// Per-frame result of `FaceEnrollmentService.evaluateAndCapture`, rendered
/// by the capture screen on every processed frame.
class FaceEnrollmentState {
  const FaceEnrollmentState({
    required this.status,
    this.offsetDirection,
    this.scanProgress,
    this.livenessInstruction,
  });

  const FaceEnrollmentState.initial()
    : status = FaceEnrollmentStatus.initializing,
      offsetDirection = null,
      scanProgress = null,
      livenessInstruction = null;

  final FaceEnrollmentStatus status;

  /// Set only when [status] is [FaceEnrollmentStatus.offCenter] — which
  /// way the operator should move to recenter. Null falls back to the
  /// generic [FaceEnrollmentStatus.caption].
  final FaceOffsetDirection? offsetDirection;

  /// Fraction (0.0..1.0) of progress through whichever timed sub-phase is
  /// active — the continuous scan window when [status] is
  /// [FaceEnrollmentStatus.scanning], or the current liveness challenge's
  /// hold/blink progress when [status] is
  /// [FaceEnrollmentStatus.livenessChallenge]. The two are never active at
  /// once, so reusing one field doesn't collide. Deliberately not a sample
  /// count during scanning: the whole point of the continuous-scan design
  /// is that the operator never sees "N of M" capture counting (see
  /// `FaceEnrollmentStatus`'s class doc comment).
  final double? scanProgress;

  /// Set only when [status] is [FaceEnrollmentStatus.livenessChallenge] —
  /// the active challenge's instruction (e.g. "Blink"). Null falls back to
  /// the generic [FaceEnrollmentStatus.caption].
  final String? livenessInstruction;

  /// User-facing guidance text: directional when available (e.g. "Move
  /// your face left"), then the active liveness instruction, otherwise
  /// [status]'s generic [caption].
  String get caption =>
      offsetDirection?.guidance ?? livenessInstruction ?? status.caption;
}
