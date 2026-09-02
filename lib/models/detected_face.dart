import 'dart:math';
import 'dart:ui';

/// App-neutral face-detection result. Constructed only inside
/// `face_detection_service.dart` via its ML-Kit-to-DetectedFace
/// conversion — this file has no dependency on `google_mlkit_face_detection`
/// itself, so swapping detection engines later only touches one file.
class DetectedFace {
  const DetectedFace({
    required this.boundingBox,
    required this.imageSize,
    this.headEulerAngleX,
    this.headEulerAngleY,
    this.headEulerAngleZ,
    this.leftEyeOpenProbability,
    this.rightEyeOpenProbability,
    this.smilingProbability,
    this.leftEyePosition,
    this.rightEyePosition,
  });

  /// Face bounding box in image pixel coordinates.
  final Rect boundingBox;

  /// Full camera-frame size the bounding box is relative to.
  final Size imageSize;

  /// Head tilt up/down, in degrees. Null if classification wasn't enabled
  /// or the detector didn't report it for this frame.
  final double? headEulerAngleX;

  /// Head turn left/right, in degrees. Positive = turned toward the
  /// subject's left (viewer's right), matching ML Kit's convention.
  final double? headEulerAngleY;

  /// Head tilt sideways (ear toward shoulder), in degrees.
  final double? headEulerAngleZ;

  final double? leftEyeOpenProbability;
  final double? rightEyeOpenProbability;
  final double? smilingProbability;

  /// Eye landmark positions in image pixel coordinates (same space as
  /// [boundingBox]). Null if landmarks weren't enabled or the detector
  /// didn't report them for this frame. Used by `FaceAlignmentService` to
  /// level the face before cropping — not used by [FaceQualityIssue]
  /// checks, which only look at [leftEyeOpenProbability]/
  /// [rightEyeOpenProbability].
  final Point<int>? leftEyePosition;
  final Point<int>? rightEyePosition;
}
