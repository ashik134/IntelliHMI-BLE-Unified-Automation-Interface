/// On-screen state for the live face-enrollment capture flow
/// (`FaceEnrollmentScreen`/`FaceEnrollmentService`). Distinct from
/// [FaceQualityIssue], which only describes *why* a single frame was
/// rejected — this enum also covers states that aren't per-frame quality
/// problems (permissions, camera lifecycle, capture progress, the
/// duplicate-face outcome).
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
  capturing,
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
    FaceEnrollmentStatus.poorLighting => 'Improve lighting',
    FaceEnrollmentStatus.holdStill => 'Hold still',
    FaceEnrollmentStatus.capturing => 'Capturing',
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
    required this.samplesCaptured,
    required this.samplesRequired,
  });

  const FaceEnrollmentState.initial({this.samplesRequired = 7})
    : status = FaceEnrollmentStatus.initializing,
      samplesCaptured = 0;

  final FaceEnrollmentStatus status;
  final int samplesCaptured;
  final int samplesRequired;
}
