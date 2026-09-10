import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_pose.dart';
import 'package:rev_crane_control_ops/services/face_geometry_validator.dart';

const _imageSize = Size(400, 400);
const _center = Point(200, 200);

DetectedFace _face({
  Point<int>? leftEye,
  Point<int>? rightEye,
  Point<int>? nose,
  Point<int>? leftCheek,
  Point<int>? rightCheek,
}) {
  return DetectedFace(
    boundingBox: const Rect.fromLTWH(150, 150, 100, 100),
    imageSize: _imageSize,
    leftEyePosition: leftEye,
    rightEyePosition: rightEye,
    noseBasePosition: nose,
    leftCheekPosition: leftCheek,
    rightCheekPosition: rightCheek,
  );
}

void main() {
  group('FaceGeometryValidator.evaluate', () {
    test('passes when every required landmark sits at the image center', () {
      final face = _face(
        leftEye: _center,
        rightEye: _center,
        nose: _center,
        leftCheek: _center,
        rightCheek: _center,
      );
      final result = FaceGeometryValidator.evaluate(
        face: face,
        imageSize: _imageSize,
        rotationDegrees: 0,
        pose: FacePose.frontal,
      );
      expect(result.passed, isTrue);
      expect(result.landmarksPresent, isTrue);
      expect(result.landmarksContained, isTrue);
    });

    test(
      'fails when a required landmark sits outside the safe region',
      () {
        // safeRegionFraction defaults to 0.20 of the 400px shortest side
        // => an 80px safe radius from center. 150px away is well outside.
        final face = _face(
          leftEye: _center,
          rightEye: _center,
          nose: const Point(350, 200),
          leftCheek: _center,
          rightCheek: _center,
        );
        final result = FaceGeometryValidator.evaluate(
          face: face,
          imageSize: _imageSize,
          rotationDegrees: 0,
          pose: FacePose.frontal,
        );
        expect(result.landmarksPresent, isTrue);
        expect(result.landmarksContained, isFalse);
        expect(result.passed, isFalse);
      },
    );

    test(
      'flags missing landmarks distinctly from out-of-region landmarks',
      () {
        final face = _face(leftEye: _center, rightEye: _center, nose: null);
        final result = FaceGeometryValidator.evaluate(
          face: face,
          imageSize: _imageSize,
          rotationDegrees: 0,
          pose: FacePose.frontal,
        );
        expect(result.landmarksPresent, isFalse);
        expect(result.passed, isFalse);
      },
    );

    test(
      'a left-turn pose does not require the far (left) cheek landmark',
      () {
        final face = _face(
          leftEye: _center,
          rightEye: _center,
          nose: _center,
          leftCheek: null,
          rightCheek: _center,
        );
        final result = FaceGeometryValidator.evaluate(
          face: face,
          imageSize: _imageSize,
          rotationDegrees: 0,
          pose: FacePose.left,
        );
        expect(result.landmarksPresent, isTrue);
        expect(result.passed, isTrue);
      },
    );

    test(
      'that same missing-left-cheek frame still fails the frontal pose, '
      'which does require it',
      () {
        final face = _face(
          leftEye: _center,
          rightEye: _center,
          nose: _center,
          leftCheek: null,
          rightCheek: _center,
        );
        final result = FaceGeometryValidator.evaluate(
          face: face,
          imageSize: _imageSize,
          rotationDegrees: 0,
          pose: FacePose.frontal,
        );
        expect(result.landmarksPresent, isFalse);
      },
    );
  });

  group('matchesPoseTarget sign convention', () {
    const config = FaceEnrollmentConfig.defaults;

    DetectedFace angled({double? yaw, double? pitch}) => DetectedFace(
      boundingBox: const Rect.fromLTWH(150, 150, 100, 100),
      imageSize: _imageSize,
      headEulerAngleY: yaw,
      headEulerAngleX: pitch,
    );

    test('positive yaw matches the left pose (subject turned left)', () {
      expect(matchesPoseTarget(FacePose.left, angled(yaw: 25, pitch: 0), config), isTrue);
      expect(matchesPoseTarget(FacePose.right, angled(yaw: 25, pitch: 0), config), isFalse);
    });

    test('negative yaw matches the right pose', () {
      expect(matchesPoseTarget(FacePose.right, angled(yaw: -25, pitch: 0), config), isTrue);
      expect(matchesPoseTarget(FacePose.left, angled(yaw: -25, pitch: 0), config), isFalse);
    });

    test('positive pitch matches the up pose', () {
      expect(matchesPoseTarget(FacePose.up, angled(yaw: 0, pitch: 20), config), isTrue);
    });

    test('frontal only matches near-zero yaw and pitch', () {
      expect(matchesPoseTarget(FacePose.frontal, angled(yaw: 2, pitch: -2), config), isTrue);
      expect(matchesPoseTarget(FacePose.frontal, angled(yaw: 25, pitch: 0), config), isFalse);
    });
  });
}
