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
    );
  }

  // ── Quality evaluation — pure function, see class doc ───────────────────

  static const double minFaceWidthFraction = 0.25;
  static const double maxFaceWidthFraction = 0.85;
  static const double maxCenterOffsetFraction = 0.18;
  static const double maxPoseAngle = 20.0;

  static FaceQualityResult evaluateQuality(
    List<DetectedFace> faces,
    Size imageSize,
  ) {
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

    final widthFraction = face.boundingBox.width / imageSize.width;
    if (widthFraction < minFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooSmall);
    } else if (widthFraction > maxFaceWidthFraction) {
      issues.add(FaceQualityIssue.faceTooLarge);
    }

    final faceCenter = face.boundingBox.center;
    final imageCenter = Offset(imageSize.width / 2, imageSize.height / 2);
    final shortestSide = imageSize.shortestSide == 0
        ? 1.0
        : imageSize.shortestSide;
    final offsetFraction = (faceCenter - imageCenter).distance / shortestSide;
    if (offsetFraction > maxCenterOffsetFraction) {
      issues.add(FaceQualityIssue.offCenter);
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

    return issues.isEmpty
        ? const FaceQualityResult.ok()
        : FaceQualityResult(passed: false, issues: issues);
  }
}
