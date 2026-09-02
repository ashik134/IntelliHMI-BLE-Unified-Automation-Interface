import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/services/face_alignment_service.dart';

DetectedFace _face({
  required Rect boundingBox,
  math.Point<int>? leftEyePosition,
  math.Point<int>? rightEyePosition,
}) {
  return DetectedFace(
    boundingBox: boundingBox,
    imageSize: const Size(500, 500),
    leftEyePosition: leftEyePosition,
    rightEyePosition: rightEyePosition,
  );
}

void _markSquare(img.Image image, int cx, int cy, {required int r, required int g, required int b}) {
  for (var dy = -2; dy <= 2; dy++) {
    for (var dx = -2; dx <= 2; dx++) {
      image.setPixelRgb(cx + dx, cy + dy, r, g, b);
    }
  }
}

/// Finds the pixel with the strongest red (or blue) tint — an
/// interpolation-tolerant stand-in for "where the marker ended up".
({int x, int y}) _findMarker(img.Image image, {required bool red}) {
  var bestScore = -1;
  var bestX = 0;
  var bestY = 0;
  for (final pixel in image) {
    final score = red
        ? pixel.r.toInt() - pixel.b.toInt()
        : pixel.b.toInt() - pixel.r.toInt();
    if (score > bestScore) {
      bestScore = score;
      bestX = pixel.x;
      bestY = pixel.y;
    }
  }
  return (x: bestX, y: bestY);
}

void main() {
  group('align', () {
    test('output is always square', () {
      final source = img.Image(width: 500, height: 500);
      final face = _face(boundingBox: const Rect.fromLTWH(150, 150, 100, 100));
      final result = FaceAlignmentService.align(sourceImage: source, face: face);
      expect(result.width, result.height);
    });

    test('falls back to a center crop when landmarks are missing', () {
      final source = img.Image(width: 500, height: 500);
      final face = _face(boundingBox: const Rect.fromLTWH(150, 150, 100, 100));
      final result = FaceAlignmentService.align(sourceImage: source, face: face);
      expect(result.width, result.height);
      expect(result.width, greaterThan(0));
    });

    test(
      'an already-level eye pair produces the same output as no landmarks '
      'at all (zero-degree rotation is a no-op)',
      () {
        const boundingBox = Rect.fromLTWH(150, 150, 100, 100);

        final sourceA = img.Image(width: 500, height: 500);
        _markSquare(sourceA, 240, 200, r: 255, g: 0, b: 0);
        _markSquare(sourceA, 160, 200, r: 0, g: 0, b: 255);
        final level = _face(
          boundingBox: boundingBox,
          // Same y for both eyes — already level.
          leftEyePosition: const math.Point(240, 200),
          rightEyePosition: const math.Point(160, 200),
        );
        final resultLevel = FaceAlignmentService.align(
          sourceImage: sourceA,
          face: level,
        );

        final sourceB = img.Image(width: 500, height: 500);
        _markSquare(sourceB, 240, 200, r: 255, g: 0, b: 0);
        _markSquare(sourceB, 160, 200, r: 0, g: 0, b: 255);
        final noLandmarks = _face(boundingBox: boundingBox);
        final resultNoLandmarks = FaceAlignmentService.align(
          sourceImage: sourceB,
          face: noLandmarks,
        );

        expect(resultLevel.width, resultNoLandmarks.width);
        expect(resultLevel.height, resultNoLandmarks.height);
        final redLevel = _findMarker(resultLevel, red: true);
        final redFallback = _findMarker(resultNoLandmarks, red: true);
        expect(redLevel.x, redFallback.x);
        expect(redLevel.y, redFallback.y);
      },
    );

    test('a tilted eye pair ends up level after alignment', () {
      final source = img.Image(width: 500, height: 500);
      // Subject's left eye (larger x) higher up than their right eye
      // (smaller x) — a real, moderate head-roll tilt.
      const leftEye = math.Point(240, 180);
      const rightEye = math.Point(160, 200);
      _markSquare(source, leftEye.x, leftEye.y, r: 255, g: 0, b: 0);
      _markSquare(source, rightEye.x, rightEye.y, r: 0, g: 0, b: 255);

      final face = _face(
        boundingBox: const Rect.fromLTWH(150, 150, 100, 100),
        leftEyePosition: leftEye,
        rightEyePosition: rightEye,
      );

      // Sanity check: the markers really are tilted before alignment.
      expect(leftEye.y, isNot(rightEye.y));

      final result = FaceAlignmentService.align(sourceImage: source, face: face);

      final red = _findMarker(result, red: true);
      final blue = _findMarker(result, red: false);

      // The two eye markers should now be level (allowing a couple of
      // pixels of slack for rotation interpolation/rounding).
      expect((red.y - blue.y).abs(), lessThanOrEqualTo(3));
      // A ~14° roll shouldn't reverse left/right ordering.
      expect(red.x, greaterThan(blue.x));
    });

    test('a small face near the image edge does not throw', () {
      final source = img.Image(width: 100, height: 100);
      final face = _face(
        boundingBox: const Rect.fromLTWH(0, 0, 30, 30),
        leftEyePosition: const math.Point(20, 8),
        rightEyePosition: const math.Point(8, 10),
      );
      expect(
        () => FaceAlignmentService.align(sourceImage: source, face: face),
        returnsNormally,
      );
    });
  });
}
