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

    test(
      'a face near the image edge produces the same crop — position-'
      'independence regression test',
      () {
        // The same face (same box size, same eye geometry, just
        // translated) should land at the *same* relative position within
        // the aligned output regardless of where it sat in the source
        // frame. Before the padding fix, `align()` clamped the crop
        // window's edges independently instead of padding the source —
        // for a face this close to an edge that silently shifted the
        // window off the face's true center, so the *same* person's face
        // produced a differently-cropped (and therefore differently-
        // embedded) input purely because of on-screen position. That's
        // the exact defect behind "verification only recognizes the same
        // position used during enrollment".
        img.Image sourceWith({
          required double centerX,
          required int leftEyeX,
          required int rightEyeX,
        }) {
          final source = img.Image(width: 500, height: 500);
          _markSquare(source, leftEyeX, 200, r: 255, g: 0, b: 0);
          _markSquare(source, rightEyeX, 200, r: 0, g: 0, b: 255);
          return source;
        }

        // Baseline: box comfortably inside the frame — the padded
        // window (paddedSide 200, i.e. ±100 from center) never reaches
        // an edge, so this is unaffected by the bug either way.
        final centered = sourceWith(
          centerX: 200,
          leftEyeX: 240,
          rightEyeX: 160,
        );
        final centeredFace = _face(
          boundingBox: const Rect.fromLTWH(150, 150, 100, 100),
          leftEyePosition: const math.Point(240, 200),
          rightEyePosition: const math.Point(160, 200),
        );
        final centeredResult = FaceAlignmentService.align(
          sourceImage: centered,
          face: centeredFace,
        );

        // Same face, shifted 130px toward x=0 — the padded window's
        // desired left edge (70 - 100 = -30) falls outside the source,
        // exactly the case the old clamp-based crop mishandled.
        final edge = sourceWith(centerX: 70, leftEyeX: 110, rightEyeX: 30);
        final edgeFace = _face(
          boundingBox: const Rect.fromLTWH(20, 150, 100, 100),
          leftEyePosition: const math.Point(110, 200),
          rightEyePosition: const math.Point(30, 200),
        );
        final edgeResult = FaceAlignmentService.align(
          sourceImage: edge,
          face: edgeFace,
        );

        // Same face size everywhere -> the output crop size itself
        // should already be identical.
        expect(edgeResult.width, centeredResult.width);
        expect(edgeResult.height, centeredResult.height);

        final centeredRed = _findMarker(centeredResult, red: true);
        final centeredBlue = _findMarker(centeredResult, red: false);
        final edgeRed = _findMarker(edgeResult, red: true);
        final edgeBlue = _findMarker(edgeResult, red: false);

        expect(edgeRed.x, closeTo(centeredRed.x, 1));
        expect(edgeRed.y, closeTo(centeredRed.y, 1));
        expect(edgeBlue.x, closeTo(centeredBlue.x, 1));
        expect(edgeBlue.y, closeTo(centeredBlue.y, 1));
      },
    );
  });
}
