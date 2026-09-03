import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';

/// Thin wrapper over `google_mlkit_face_detection`'s `FaceDetector`, plus
/// pure quality evaluation on its output (spec section 8).
///
/// [evaluateQuality] is deliberately independent of [detectFaces] itself
/// — it operates only on the already-converted [DetectedFace] data — so
/// it's unit-testable without ML Kit's real native detector, which needs
/// Android + Google Play Services and cannot run in this dev environment.
/// [detectFaces] itself can only be verified on an actual device.
///
/// Not checked here (scoped out of Stage 3, not an oversight): lighting
/// and blur. ML Kit's `Face` doesn't expose either, and a real check
/// needs the raw pixel buffer, which fits Stage 4's capture flow more
/// naturally (it already has the buffer in scope for cropping/embedding).
class FaceDetectionService {
  FaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          enableLandmarks: true,
          performanceMode: FaceDetectorMode.accurate,
        ),
      );

  final FaceDetector _detector;

  Future<List<DetectedFace>> detectFaces(
    InputImage image,
    Size imageSize,
  ) async {
    final faces = await _detector.processImage(image);
    return faces.map((f) => _fromMlKitFace(f, imageSize)).toList();
  }

  Future<void> close() => _detector.close();

  static DetectedFace _fromMlKitFace(Face face, Size imageSize) {
    return DetectedFace(
      boundingBox: face.boundingBox,
      imageSize: imageSize,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      leftEyePosition: face.landmarks[FaceLandmarkType.leftEye]?.position,
      rightEyePosition: face.landmarks[FaceLandmarkType.rightEye]?.position,
    );
  }

  // ── Quality evaluation — pure function, see class doc ───────────────────

  static const double minFaceWidthFraction = 0.25;
  static const double maxFaceWidthFraction = 0.85;
  static const double maxCenterOffsetFraction = 0.18;
  static const double maxPoseAngle = 20.0;

  /// [rotationDegrees] is the same rotation-compensation angle passed to
  /// ML Kit for detection (`CameraFrameConverter.rotationDegrees`/
  /// `toInputImage`). `DetectedFace.boundingBox`/[imageSize] are in raw,
  /// unrotated sensor space (e.g. landscape on a phone whose sensor is
  /// mounted landscape, even while the phone is held portrait) — every
  /// geometry check below needs to reason in the *upright*, on-screen
  /// orientation instead, or a 90°/270° rotation silently swaps the
  /// width/height and left-right/up-down axes against what the operator
  /// actually sees (and what the on-screen guide oval is measured
  /// against). Defaults to 0 (no-op) so existing unrotated callers/tests
  /// are unaffected.
  static FaceQualityResult evaluateQuality(
    List<DetectedFace> faces,
    Size imageSize, {
    int rotationDegrees = 0,
  }) {
    if (faces.isEmpty) {
      return const FaceQualityResult(
        passed: false,
        issues: [FaceQualityIssue.noFaceDetected],
      );
    }
    if (faces.length > 1) {
      return const FaceQualityResult(
        passed: false,
        issues: [FaceQualityIssue.multipleFacesDetected],
      );
    }

    final face = faces.single;
    final issues = <FaceQualityIssue>[];
    FaceOffsetDirection? offsetDirection;

    final uprightImageSize = uprightSize(imageSize, rotationDegrees);
    final uprightBox = uprightRect(
      face.boundingBox,
      imageSize,
      rotationDegrees,
    );

    final widthFraction = uprightBox.width / uprightImageSize.width;
    if (widthFraction < minFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooSmall);
    } else if (widthFraction > maxFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooLarge);
    }

    final faceCenter = uprightBox.center;
    final imageCenter = Offset(
      uprightImageSize.width / 2,
      uprightImageSize.height / 2,
    );
    final shortestSide = uprightImageSize.shortestSide == 0
        ? 1.0
        : uprightImageSize.shortestSide;
    final centerDelta = faceCenter - imageCenter;
    final offsetFraction = centerDelta.distance / shortestSide;
    if (offsetFraction > maxCenterOffsetFraction) {
      issues.add(FaceQualityIssue.offCenter);
      offsetDirection = centerDelta.dx.abs() >= centerDelta.dy.abs()
          ? (centerDelta.dx > 0
                ? FaceOffsetDirection.left
                : FaceOffsetDirection.right)
          : (centerDelta.dy > 0
                ? FaceOffsetDirection.up
                : FaceOffsetDirection.down);
    }

    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    if ((yaw != null && yaw.abs() > maxPoseAngle) ||
        (pitch != null && pitch.abs() > maxPoseAngle)) {
      issues.add(FaceQualityIssue.extremePose);
    }

    if (face.leftEyeOpenProbability == null ||
        face.rightEyeOpenProbability == null) {
      issues.add(FaceQualityIssue.eyesNotVisible);
    }

    return FaceQualityResult(
      passed: issues.isEmpty,
      issues: issues,
      offsetDirection: offsetDirection,
      centerOffsetFraction: offsetFraction,
      widthFraction: widthFraction,
    );
  }

  /// [imageSize] rotated into the upright orientation: a 90°/270°
  /// compensation swaps width and height (landscape sensor → portrait
  /// display); 0°/180° leaves them as-is.
  static Size uprightSize(Size imageSize, int rotationDegrees) {
    return rotationDegrees == 90 || rotationDegrees == 270
        ? Size(imageSize.height, imageSize.width)
        : imageSize;
  }

  /// Maps an axis-aligned [rect] in raw sensor space (sized [rawSize])
  /// into the axis-aligned rect it becomes once rotated clockwise by
  /// [rotationDegrees] to the upright orientation — the same convention
  /// `InputImageRotation`/`CameraFrameConverter.rotationDegrees` use.
  static Rect uprightRect(Rect rect, Size rawSize, int rotationDegrees) {
    switch (rotationDegrees) {
      case 90:
        return Rect.fromLTRB(
          rawSize.height - rect.bottom,
          rect.left,
          rawSize.height - rect.top,
          rect.right,
        );
      case 180:
        return Rect.fromLTRB(
          rawSize.width - rect.right,
          rawSize.height - rect.bottom,
          rawSize.width - rect.left,
          rawSize.height - rect.top,
        );
      case 270:
        return Rect.fromLTRB(
          rect.top,
          rawSize.width - rect.right,
          rect.bottom,
          rawSize.width - rect.left,
        );
      default:
        return rect;
    }
  }
}
