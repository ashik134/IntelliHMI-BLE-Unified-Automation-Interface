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
  /// A required facial landmark (per `PoseLandmarkRequirements` for the
  /// current pose) sits outside `FaceGeometryValidator`'s safe region —
  /// distinct from [offCenter], which only looks at the bounding box.
  landmarksOutsideSafeRegion,
  /// A required landmark wasn't reported by ML Kit at all for this frame
  /// (e.g. eyes not resolved) — distinct from
  /// [landmarksOutsideSafeRegion], which is about position, not presence.
  missingLandmarks,
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
    FaceQualityIssue.landmarksOutsideSafeRegion =>
      'Center your face fully inside the oval',
    FaceQualityIssue.missingLandmarks => 'Face partially out of frame',
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

  // ── Per-condition breakdown ──────────────────────────────────────────
  //
  // [issues] already carries every failing condition for this frame, not
  // just [primaryIssue] — these are just named readouts of it, for the
  // debug diagnostics panel to show *all* conditions instead of only the
  // one condition the operator-facing caption prioritizes. A frame can
  // legitimately fail several of these at once (e.g. too small *and*
  // off-center); `passed` is the only field that means "every check in
  // this group passed."

  bool get faceDetected =>
      !issues.contains(FaceQualityIssue.noFaceDetected) &&
      !issues.contains(FaceQualityIssue.multipleFacesDetected);

  bool get sizePassed =>
      !issues.contains(FaceQualityIssue.faceTooSmall) &&
      !issues.contains(FaceQualityIssue.faceTooLarge);

  /// Centering is judged as a single radial (Euclidean) distance from the
  /// image center, not independent X/Y budgets — so there's no meaningful
  /// separate centerXPassed/centerYPassed distinction to report without
  /// misrepresenting the algorithm. [offsetDirection] already names
  /// whichever axis dominates the offset when this is false.
  bool get centerPassed => !issues.contains(FaceQualityIssue.offCenter);

  bool get posePassed => !issues.contains(FaceQualityIssue.extremePose);

  bool get eyesPassed => !issues.contains(FaceQualityIssue.eyesNotVisible);
}
