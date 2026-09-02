/// A single reason a frame failed quality validation (spec section 8).
///
/// [poorLighting] and [tooBlurry] are evaluated separately from the rest —
/// see `FrameQualityAnalyzer`, which operates on the raw pixel buffer
/// (ML Kit's `Face` doesn't expose either) — but they share this enum so
/// downstream code (the enrollment capture screen) has one issue type to
/// render regardless of which stage caught the problem.
enum FaceQualityIssue {
  noFaceDetected,
  multipleFacesDetected,
  faceTooSmall,
  faceTooLarge,
  offCenter,
  extremePose,
  eyesNotVisible,
  poorLighting,
  tooBlurry,
}

extension FaceQualityIssueMessage on FaceQualityIssue {
  /// User-facing guidance text (spec section 8's examples).
  String get guidance => switch (this) {
    FaceQualityIssue.noFaceDetected => 'Position your face inside the frame',
    FaceQualityIssue.multipleFacesDetected =>
      'Only one person should be visible',
    FaceQualityIssue.faceTooSmall => 'Move closer',
    FaceQualityIssue.faceTooLarge => 'Move farther away',
    FaceQualityIssue.offCenter => 'Center your face',
    FaceQualityIssue.extremePose => 'Look straight at the camera',
    FaceQualityIssue.eyesNotVisible => 'Keep your eyes visible',
    FaceQualityIssue.poorLighting => 'Improve lighting',
    FaceQualityIssue.tooBlurry => 'Hold still',
  };
}

/// Result of evaluating one detection frame against enrollment/
/// authentication quality requirements.
class FaceQualityResult {
  const FaceQualityResult({required this.passed, this.issues = const []});

  const FaceQualityResult.ok() : passed = true, issues = const [];

  final bool passed;
  final List<FaceQualityIssue> issues;

  /// The single most relevant issue to show the operator, or null if
  /// [passed].
  FaceQualityIssue? get primaryIssue => issues.isEmpty ? null : issues.first;

  String? get primaryMessage => primaryIssue?.guidance;
}
