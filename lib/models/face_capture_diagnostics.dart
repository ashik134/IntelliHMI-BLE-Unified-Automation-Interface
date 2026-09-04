/// Live, on-screen-only diagnostic readout for the enrollment capture
/// screen's debug overlay (`kDebugMode` only — never shown in a release
/// build). Purely derived geometry/exposure metrics — never the
/// embedding vector or raw pixel data, so displaying this is not the
/// "never print embeddings or biometric data" concern the rest of this
/// feature is careful about. Nothing here is logged or persisted; it only
/// ever flows into a widget's `build`.
class FaceCaptureDiagnostics {
  const FaceCaptureDiagnostics({
    required this.faceCount,
    this.yawDegrees,
    this.pitchDegrees,
    this.faceWidthFraction,
    this.centerOffsetFraction,
    this.brightness,
    this.sharpness,
    this.sizePassed,
    this.centerPassed,
    this.posePassed,
    this.eyesPassed,
    this.brightnessPassed,
    this.sharpnessPassed,
    this.stableProgress,
    this.scanning = false,
    this.scanProgress,
    this.identityLocked = false,
    this.samplesAccepted,
    this.readyForCapture = false,
    this.failedReason,
  });

  const FaceCaptureDiagnostics.empty()
    : faceCount = 0,
      yawDegrees = null,
      pitchDegrees = null,
      faceWidthFraction = null,
      centerOffsetFraction = null,
      brightness = null,
      sharpness = null,
      sizePassed = null,
      centerPassed = null,
      posePassed = null,
      eyesPassed = null,
      brightnessPassed = null,
      sharpnessPassed = null,
      stableProgress = null,
      scanning = false,
      scanProgress = null,
      identityLocked = false,
      samplesAccepted = null,
      readyForCapture = false,
      failedReason = null;

  final int faceCount;

  /// Degrees; matches `DetectedFace.headEulerAngleY`.
  final double? yawDegrees;

  /// Degrees; matches `DetectedFace.headEulerAngleX`.
  final double? pitchDegrees;

  /// Detected face bounding-box width as a fraction of the (upright,
  /// on-screen) frame width — the exact same value
  /// `FaceDetectionService.evaluateQuality` gates on (see
  /// `FaceQualityResult.widthFraction`), not a separately-computed
  /// approximation.
  final double? faceWidthFraction;

  /// Face-center-to-image-center distance as a fraction of the (upright)
  /// shorter side — same value `FaceDetectionService.evaluateQuality`
  /// gates on (`FaceQualityResult.centerOffsetFraction`), for comparison
  /// against `FaceDetectionService.maxCenterOffsetFraction`.
  final double? centerOffsetFraction;

  /// 0..255, from `FrameQualityAnalyzer.estimateBrightness`.
  final double? brightness;

  /// From `FrameQualityAnalyzer.estimateSharpness` — unitless, only
  /// meaningful relative to `FrameQualityAnalyzer.minSharpness`.
  final double? sharpness;

  /// Per-condition breakdown, all independently computed (a frame can
  /// fail several at once) — null when [faceCount] != 1, since none of
  /// these are meaningful without exactly one detected face.
  final bool? sizePassed;
  final bool? centerPassed;
  final bool? posePassed;
  final bool? eyesPassed;
  final bool? brightnessPassed;
  final bool? sharpnessPassed;

  /// Fraction (0.0..1.0) toward clearing the pre-scan stability gate, from
  /// `FaceEnrollmentService.stableProgress` — how close this capture
  /// session is to entering the continuous scan. Meaningless once
  /// [scanning] is true.
  final double? stableProgress;

  /// Whether the continuous scan (`FaceEnrollmentService.isScanning`) has
  /// been entered.
  final bool scanning;

  /// Fraction (0.0..1.0) of the scan window elapsed, from
  /// `FaceEnrollmentService`'s internal scan clock — only meaningful when
  /// [scanning] is true.
  final double? scanProgress;

  /// Whether the enrollment identity has locked yet
  /// (`FaceEnrollmentService.identityLocked`) — before this, accepted
  /// samples are still unconfirmed seeds.
  final bool identityLocked;

  /// Accepted sample count so far (`FaceEnrollmentService.samplesCaptured`)
  /// — debug-only; never shown to the operator (see this feature's
  /// continuous-scan design, which deliberately has no visible "N of M"
  /// counter).
  final int? samplesAccepted;

  /// Whether this exact frame would be accepted right now — every check
  /// above passed, pixel checks included. Distinct from any single
  /// `*Passed` field: this is the actual gating decision, not just one
  /// condition of it.
  final bool readyForCapture;

  /// The single condition currently blocking capture — the same value the
  /// operator-facing caption is driven from (`FaceQualityResult
  /// .primaryMessage`/`FrameQualityIssue`), shown here alongside the full
  /// breakdown so it's clear which failing condition, if several are
  /// failing at once, is the one actually producing the caption.
  final String? failedReason;
}
