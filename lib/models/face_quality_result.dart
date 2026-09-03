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

/// Which way the operator should move to bring their face back toward the
/// center of the acceptance region, in on-screen (upright, unmirrored)
/// terms — set only alongside [FaceQualityIssue.offCenter].
enum FaceOffsetDirection { up, down, left, right }

extension FaceOffsetDirectionMessage on FaceOffsetDirection {
  String get guidance => switch (this) {
    FaceOffsetDirection.up => 'Move your face up',
    FaceOffsetDirection.down => 'Move your face down',
    FaceOffsetDirection.left => 'Move your face left',
    FaceOffsetDirection.right => 'Move your face right',
  };
}

/// Result of evaluating one detection frame against enrollment/
/// authentication quality requirements.
class FaceQualityResult {
  const FaceQualityResult({
    required this.passed,
    this.issues = const [],
    this.offsetDirection,
    this.centerOffsetFraction,
    this.widthFraction,
  });

  const FaceQualityResult.ok()
    : passed = true,
      issues = const [],
      offsetDirection = null,
      centerOffsetFraction = null,
      widthFraction = null;

  final bool passed;
  final List<FaceQualityIssue> issues;

  /// Set only when [issues] contains [FaceQualityIssue.offCenter] — the
  /// direction to move to correct it.
  final FaceOffsetDirection? offsetDirection;

  /// The face-center-to-image-center distance actually measured, as a
  /// fraction of the (upright) shorter side — set whenever a face was
  /// detected, pass or fail, so callers (the debug diagnostics panel) can
  /// show how close a frame is to `FaceDetectionService
  /// .maxCenterOffsetFraction`, not just the pass/fail bit.
  final double? centerOffsetFraction;

  /// The face bounding-box width actually measured, as a fraction of the
  /// (upright) image width — set whenever a face was detected, pass or
  /// fail. Same rationale as [centerOffsetFraction].
  final double? widthFraction;

  /// The single most relevant issue to show the operator, or null if
  /// [passed].
  FaceQualityIssue? get primaryIssue => issues.isEmpty ? null : issues.first;

  String? get primaryMessage =>
      offsetDirection?.guidance ?? primaryIssue?.guidance;
}
