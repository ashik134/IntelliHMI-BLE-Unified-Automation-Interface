import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';

const _imageSize = Size(400, 400);

/// A landscape-mounted-sensor raw frame (e.g. captured while the phone is
/// held portrait) — width/height genuinely differ from the upright
/// on-screen orientation, unlike the square [_imageSize] used above,
/// which can't distinguish "rotation-aware" from "rotation-naive" math.
const _rawImageSize = Size(400, 300);

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

  // The raw sensor frame is landscape (400x300) even though the phone is
  // held portrait; a 90 degree rotation is needed to reach the upright,
  // on-screen orientation the operator actually sees and the guide oval
  // is measured against. These checks must reason in that upright space,
  // not raw sensor space, or the width/center axes get crossed.
  group('rotation-aware geometry (landscape sensor, portrait display)', () {
    test(
      'a face on-screen-centered and on-screen-correctly-sized passes',
      () {
        // Upright (on-screen) box: 100x140 centered in a 300x400 upright
        // frame -> raw box, in the 400x300 raw frame, works out to
        // width=140,height=100 at raw (130,100)-(270,200).
        final result = FaceDetectionService.evaluateQuality(
          [_face(box: const Rect.fromLTRB(130, 100, 270, 200))],
          _rawImageSize,
          rotationDegrees: 90,
        );
        expect(result.passed, isTrue);
        expect(result.issues, isEmpty);
      },
    );

    test(
      'faceTooSmall/faceTooLarge is judged on the upright width, not the '
      'raw sensor width',
      () {
        // Raw box is 200 wide (50% of the 400 raw width — looks fine if
        // width fraction is naively computed against raw width) but only
        // 60 tall; rotated upright that becomes 60 wide out of an upright
        // 300 width = 20%, below minFaceWidthFraction.
        final result = FaceDetectionService.evaluateQuality(
          [_face(box: const Rect.fromLTRB(100, 120, 300, 180))],
          _rawImageSize,
          rotationDegrees: 90,
        );
        expect(result.issues, contains(FaceQualityIssue.faceTooSmall));
      },
    );

    test(
      'offCenter direction is reported in upright (on-screen) terms',
      () {
        // Upright box centered at (150, 100) in a 300x400 upright frame —
        // well above the upright center (150, 200), so the operator
        // needs to move down. Equivalent raw box: (70,100)-(130,200).
        final result = FaceDetectionService.evaluateQuality(
          [_face(box: const Rect.fromLTRB(70, 100, 130, 200))],
          _rawImageSize,
          rotationDegrees: 90,
        );
        expect(result.issues, contains(FaceQualityIssue.offCenter));
        expect(result.offsetDirection, FaceOffsetDirection.down);
        expect(result.primaryMessage, 'Move your face down');
      },
    );
  });
}
