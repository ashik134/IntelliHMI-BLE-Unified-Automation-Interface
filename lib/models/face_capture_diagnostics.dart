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
  });

  const FaceCaptureDiagnostics.empty()
    : faceCount = 0,
      yawDegrees = null,
      pitchDegrees = null,
      faceWidthFraction = null,
      centerOffsetFraction = null,
      brightness = null,
      sharpness = null;

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
}
