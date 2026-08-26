import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';

const _imageSize = Size(400, 400);

DetectedFace _face({
  Rect? box,
  double? yaw,
  double? pitch,
  bool eyesVisible = true,
}) {
  return DetectedFace(
    boundingBox: box ?? const Rect.fromLTWH(120, 120, 160, 160), // centered, 40% width
    imageSize: _imageSize,
    headEulerAngleY: yaw ?? 0,
    headEulerAngleX: pitch ?? 0,
    leftEyeOpenProbability: eyesVisible ? 0.9 : null,
    rightEyeOpenProbability: eyesVisible ? 0.9 : null,
  );
}

void main() {
  test('a well-framed centered face passes', () {
    final result = FaceDetectionService.evaluateQuality([_face()], _imageSize);
    expect(result.passed, isTrue);
    expect(result.issues, isEmpty);
  });

  test('no face detected fails with noFaceDetected', () {
    final result = FaceDetectionService.evaluateQuality([], _imageSize);
    expect(result.passed, isFalse);
    expect(result.issues, [FaceQualityIssue.noFaceDetected]);
  });

  test('more than one face fails with multipleFacesDetected', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(), _face()],
      _imageSize,
    );
    expect(result.passed, isFalse);
    expect(result.issues, [FaceQualityIssue.multipleFacesDetected]);
  });

  test('a small face fails with faceTooSmall ("move closer")', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(box: const Rect.fromLTWH(180, 180, 40, 40))], // 10% width
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.faceTooSmall));
    expect(result.primaryMessage, 'Move closer');
  });

  test('a face filling the frame fails with faceTooLarge ("move farther")', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(box: const Rect.fromLTWH(0, 0, 400, 400))], // 100% width
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.faceTooLarge));
  });

  test('an off-center face fails with offCenter', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(box: const Rect.fromLTWH(0, 0, 160, 160))], // pushed to a corner
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.offCenter));
  });

  test('an extreme head-turn fails with extremePose', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(yaw: 45)],
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.extremePose));
  });

  test('missing eye-open data fails with eyesNotVisible', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(eyesVisible: false)],
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.eyesNotVisible));
  });

  test('multiple simultaneous issues are all reported', () {
    final result = FaceDetectionService.evaluateQuality(
      [_face(box: const Rect.fromLTWH(0, 0, 40, 40), yaw: 45)],
      _imageSize,
    );
    expect(result.issues, contains(FaceQualityIssue.faceTooSmall));
    expect(result.issues, contains(FaceQualityIssue.offCenter));
    expect(result.issues, contains(FaceQualityIssue.extremePose));
  });
}
