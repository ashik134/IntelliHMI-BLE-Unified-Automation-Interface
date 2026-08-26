/// A single reason a frame failed quality validation (spec section 8).
/// Not checked here (scoped out of Stage 3, not an oversight — see
/// FaceDetectionService's doc comment): lighting and blur, since ML Kit's
/// `Face` doesn't expose either and a real check needs the raw pixel
/// buffer, which fits Stage 4's capture flow more naturally.
enum FaceQualityIssue {
  noFaceDetected,
  multipleFacesDetected,
  faceTooSmall,
  faceTooLarge,
  offCenter,
  extremePose,
  eyesNotVisible,
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
    FaceQualityIssue.extremePose => 'Look toward the camera',
    FaceQualityIssue.eyesNotVisible => 'Keep your eyes visible',
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
