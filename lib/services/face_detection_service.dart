import 'dart:ui';
import 'dart:math' as math;

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';

class FaceDetectionService {
  FaceDetectionService()
    : _detector = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          enableTracking: true,
          enableLandmarks: true,
          // `fast` over `accurate`: this is only a gating check (bounding
          // box/pose/eyes) — the embedding step does the real identity
          // work — and on-device profiling showed `accurate` costing
          // 400-600ms/frame on mid-range hardware, which alone made the
          // enrollment scan's sample budget unreachable in its scan
          // window (see `FaceEnrollmentService.scanDuration`).
          performanceMode: FaceDetectorMode.fast,
        ),
      );

  final FaceDetector _detector;

  static bool get _detectorPreRotatesResults =>
      defaultTargetPlatform != TargetPlatform.iOS;

  Future<List<DetectedFace>> detectFaces(
    InputImage image,
    Size imageSize, {
    int rotationDegrees = 0,
  }) async {
    final faces = await _detector.processImage(image);
    return faces
        .map((f) => _fromMlKitFace(f, imageSize, rotationDegrees))
        .toList();
  }

  Future<void> close() => _detector.close();

  static DetectedFace _fromMlKitFace(
    Face face,
    Size imageSize,
    int rotationDegrees,
  ) {
    var boundingBox = face.boundingBox;
    var leftEye = face.landmarks[FaceLandmarkType.leftEye]?.position;
    var rightEye = face.landmarks[FaceLandmarkType.rightEye]?.position;

    if (_detectorPreRotatesResults && rotationDegrees != 0) {
      boundingBox = downrightRect(boundingBox, imageSize, rotationDegrees);
      if (leftEye != null) {
        leftEye = _downrightPoint(leftEye, imageSize, rotationDegrees);
      }
      if (rightEye != null) {
        rightEye = _downrightPoint(rightEye, imageSize, rotationDegrees);
      }
    }

    return DetectedFace(
      boundingBox: boundingBox,
      imageSize: imageSize,
      headEulerAngleX: face.headEulerAngleX,
      headEulerAngleY: face.headEulerAngleY,
      headEulerAngleZ: face.headEulerAngleZ,
      leftEyeOpenProbability: face.leftEyeOpenProbability,
      rightEyeOpenProbability: face.rightEyeOpenProbability,
      smilingProbability: face.smilingProbability,
      leftEyePosition: leftEye,
      rightEyePosition: rightEye,
    );
  }

  // ── Quality evaluation — pure function, see class doc ───────────────────

  static const double minFaceWidthFraction = 0.25;
  static const double maxFaceWidthFraction = 0.85;

  static const double maxCenterOffsetFraction = 0.28;
  static const double maxPoseAngle = 20.0;

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

  static Size uprightSize(Size imageSize, int rotationDegrees) {
    return rotationDegrees == 90 || rotationDegrees == 270
        ? Size(imageSize.height, imageSize.width)
        : imageSize;
  }

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

  static Rect downrightRect(
    Rect rect,
    Size originalRawSize,
    int rotationDegrees,
  ) {
    final inverseRotation = (360 - rotationDegrees) % 360;
    final rectSpaceSize = uprightSize(originalRawSize, rotationDegrees);
    return uprightRect(rect, rectSpaceSize, inverseRotation);
  }

  static math.Point<int> _downrightPoint(
    math.Point<int> point,
    Size originalRawSize,
    int rotationDegrees,
  ) {
    final asRect = Rect.fromLTWH(point.x.toDouble(), point.y.toDouble(), 0, 0);
    final transformed = downrightRect(asRect, originalRawSize, rotationDegrees);
    return math.Point<int>(transformed.left.round(), transformed.top.round());
  }

  static double centerToleranceRadiusPx({
    required Size screenSize,
    required double cameraAspectRatio,
  }) {
    if (screenSize.isEmpty || cameraAspectRatio <= 0) return 0;

    final displayAspectRatio = 1 / cameraAspectRatio;

    final Size displayed;
    if (displayAspectRatio > screenSize.aspectRatio) {
      displayed = Size(
        screenSize.height * displayAspectRatio,
        screenSize.height,
      );
    } else {
      displayed = Size(screenSize.width, screenSize.width / displayAspectRatio);
    }

    return maxCenterOffsetFraction * displayed.shortestSide;
  }
}
