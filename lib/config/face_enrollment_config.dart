/// Single source of truth for every threshold the face-enrollment/
/// verification pipeline gates on — face size/centering/pose fractions,
/// pixel-quality floors, timing, and the new pose-target windows.
///
/// Previously these were `static const` fields scattered across
/// `FaceDetectionService`, `FrameQualityAnalyzer`, `FaceLivenessService`
/// and `FaceEnrollmentService`. Collecting them here means a threshold
/// change is a one-line edit in one file, and the per-pose yaw/pitch
/// windows (which didn't exist before this class) live next to the
/// checks they parameterize instead of being buried in state-machine
/// logic.
///
/// Every consumer takes a [FaceEnrollmentConfig] as an optional parameter
/// defaulting to [FaceEnrollmentConfig.defaults] — existing call sites
/// (verification screens included) keep working unchanged.
class FaceEnrollmentConfig {
  const FaceEnrollmentConfig({
    this.minFaceWidthFraction = 0.25,
    this.maxFaceWidthFraction = 0.85,
    this.maxCenterOffsetFraction = 0.28,
    this.safeRegionFraction = 0.20,
    this.maxFrontalPoseAngle = 20.0,
    this.minBrightness = 60,
    this.maxBrightness = 235,
    this.minSharpness = 30,
    this.stabilizeDuration = const Duration(milliseconds: 600),
    this.poseCaptureWindow = const Duration(milliseconds: 1000),
    this.minSampleInterval = const Duration(milliseconds: 350),
    this.maxPoseDisruption = const Duration(milliseconds: 900),
    this.livenessTimeout = const Duration(seconds: 10),
    this.outlierSimilarityFloor = 0.75,
    this.minSurvivingPoseFraction = 0.75,
    // ML Kit's documented convention (also asserted by
    // `DetectedFace.headEulerAngleY`'s doc comment): positive yaw =
    // turned toward the subject's own left. `LivenessSession` previously
    // contradicted this — see that file's fix. Flip this one flag if a
    // real device shows the opposite.
    this.yawLeftIsPositive = true,
    // Unverified on real hardware — flip after on-device testing if
    // "look up" registers as a negative pitch instead.
    this.pitchUpIsPositive = true,
  });

  static const defaults = FaceEnrollmentConfig();

  /// Minimum/maximum detected-face bounding-box width, as a fraction of
  /// the upright frame width. Rejects faces that are too far away or too
  /// close.
  final double minFaceWidthFraction;
  final double maxFaceWidthFraction;

  /// Maximum face-center-to-image-center distance, as a fraction of the
  /// upright frame's shorter side, before a face reads as off-center.
  /// This is also what sizes the on-screen guide oval — see
  /// `FaceDetectionService.centerToleranceRadiusPx`.
  final double maxCenterOffsetFraction;

  /// The "safe inner region" nested inside the guide oval that facial
  /// landmarks must stay within — strictly smaller than
  /// [maxCenterOffsetFraction] so a face can be "centered enough" per the
  /// bounding-box check yet still have a landmark (e.g. a cheek during a
  /// turn) flagged as too close to the oval's edge. See
  /// `FaceGeometryValidator`.
  final double safeRegionFraction;

  /// Maximum |yaw| or |pitch| tolerated for the frontal pose, and the
  /// generic "extreme pose" gate used outside pose-specific capture.
  final double maxFrontalPoseAngle;

  final double minBrightness;
  final double maxBrightness;
  final double minSharpness;

  /// How long a frame must continuously clear every quality gate before
  /// a pose's capture window opens.
  final Duration stabilizeDuration;

  /// Once a pose is stably held, how long the best-frame-selection window
  /// stays open collecting scored candidate frames before the best one is
  /// embedded and accepted.
  final Duration poseCaptureWindow;

  /// Minimum time between two evaluated candidate frames during a capture
  /// window — throttles how often the (comparatively expensive) pixel
  /// decode + scoring runs.
  final Duration minSampleInterval;

  /// How long a disruption (face lost, multiple faces, pose lost, poor
  /// pixel quality) must persist during a pose's stability/capture phase
  /// before that pose restarts from scratch.
  final Duration maxPoseDisruption;

  final Duration livenessTimeout;

  /// Minimum cosine similarity a candidate sample must have to the
  /// running identity centroid to be accepted, both live (per pose) and
  /// during final template outlier-trimming.
  final double outlierSimilarityFloor;

  /// Minimum fraction of the configured pose sequence that must survive
  /// outlier-trimming for a template to be built (e.g. 0.75 of 4 poses =
  /// need at least 3).
  final double minSurvivingPoseFraction;

  final bool yawLeftIsPositive;
  final bool pitchUpIsPositive;

  /// Signed yaw threshold (degrees) a frame must clear to count as
  /// "turned toward the subject's left", honoring [yawLeftIsPositive].
  double get leftTurnYawThreshold =>
      yawLeftIsPositive ? 15.0 : -15.0;

  /// Signed yaw threshold (degrees) a frame must clear to count as
  /// "turned toward the subject's right".
  double get rightTurnYawThreshold =>
      yawLeftIsPositive ? -15.0 : 15.0;

  /// Signed pitch threshold (degrees) a frame must clear to count as
  /// "looking up".
  double get lookUpPitchThreshold =>
      pitchUpIsPositive ? 12.0 : -12.0;
}
