import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';

void main() {
  group('downrightRect', () {
    // `downrightRect` is the inverse of `uprightRect` — a rect rotated
    // raw->upright by R, then downrightRect'd back by R, must land exactly
    // on the original raw rect. This is the exact correction applied to
    // ML Kit's Android output (see `_detectorPreRotatesResults`'s doc
    // comment): if this round-trip doesn't hold, every centering/size
    // check silently reasons about the wrong pixels.
    const rawSize = Size(400, 300);
    const rect = Rect.fromLTRB(50, 40, 210, 260);

    for (final rotation in [0, 90, 180, 270]) {
      test('round-trips through uprightRect at $rotation degrees', () {
        final upright = FaceDetectionService.uprightRect(
          rect,
          rawSize,
          rotation,
        );
        final backToRaw = FaceDetectionService.downrightRect(
          upright,
          rawSize,
          rotation,
        );
        expect(backToRaw.left, closeTo(rect.left, 1e-9));
        expect(backToRaw.top, closeTo(rect.top, 1e-9));
        expect(backToRaw.right, closeTo(rect.right, 1e-9));
        expect(backToRaw.bottom, closeTo(rect.bottom, 1e-9));
      });
    }

    test('90 and 270 degrees are inverses of each other', () {
      // A rect already in the upright frame ML Kit would hand back for a
      // 90-degree rotation, mapped down to raw with downrightRect(..., 90),
      // should be identical to mapping it up with uprightRect(..., 270) —
      // both describe "undo a 90-degree clockwise rotation".
      const uprightSize = Size(300, 400); // rawSize rotated 90
      const uprightBox = Rect.fromLTRB(40, 130, 260, 210);
      final viaDownright = FaceDetectionService.downrightRect(
        uprightBox,
        rawSize,
        90,
      );
      final viaUpright270 = FaceDetectionService.uprightRect(
        uprightBox,
        uprightSize,
        270,
      );
      expect(viaDownright.left, closeTo(viaUpright270.left, 1e-9));
      expect(viaDownright.top, closeTo(viaUpright270.top, 1e-9));
      expect(viaDownright.right, closeTo(viaUpright270.right, 1e-9));
      expect(viaDownright.bottom, closeTo(viaUpright270.bottom, 1e-9));
    });
  });

  group('centerToleranceRadiusPx', () {
    test('matches the closed-form BoxFit.cover geometry', () {
      // Portrait screen (1080x2280), 4:3-landscape raw camera aspect
      // ratio (1.333, `CameraController.value.aspectRatio`'s raw,
      // un-inverted convention — see the doc comment on
      // `centerToleranceRadiusPx`). Cross-checked by hand against the
      // independent intrinsic-size + `_CoverCameraPreview`-style scale
      // computation: displayed size works out to 1710x2280, so the
      // shortest side is 1710.
      final radius = FaceDetectionService.centerToleranceRadiusPx(
        screenSize: const Size(1080, 2280),
        cameraAspectRatio: 4 / 3,
      );
      const expected = FaceDetectionService.maxCenterOffsetFraction * 1710;
      expect(radius, closeTo(expected, 0.5));
    });

    test('a square camera into a square screen yields shortestSide == screenSize', () {
      final radius = FaceDetectionService.centerToleranceRadiusPx(
        screenSize: const Size(500, 500),
        cameraAspectRatio: 1,
      );
      expect(
        radius,
        closeTo(FaceDetectionService.maxCenterOffsetFraction * 500, 1e-9),
      );
    });

    test('empty screen size yields zero, not a crash or NaN', () {
      final radius = FaceDetectionService.centerToleranceRadiusPx(
        screenSize: Size.zero,
        cameraAspectRatio: 4 / 3,
      );
      expect(radius, 0);
    });
  });
}
