import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';

img.Image _solidImage(int size, int value) {
  final image = img.Image(width: size, height: size);
  for (final pixel in image) {
    pixel..r = value..g = value..b = value;
  }
  return image;
}

img.Image _checkerboard(int size, {int block = 4}) {
  final image = img.Image(width: size, height: size);
  for (final pixel in image) {
    final on = ((pixel.x ~/ block) + (pixel.y ~/ block)) % 2 == 0;
    final value = on ? 220 : 40;
    pixel..r = value..g = value..b = value;
  }
  return image;
}

void main() {
  group('estimateBrightness', () {
    test('a black image has brightness 0', () {
      expect(FrameQualityAnalyzer.estimateBrightness(_solidImage(20, 0)), 0);
    });

    test('a white image has brightness 255', () {
      expect(
        FrameQualityAnalyzer.estimateBrightness(_solidImage(20, 255)),
        255,
      );
    });

    test('a mid-gray image has brightness around 128', () {
      expect(
        FrameQualityAnalyzer.estimateBrightness(_solidImage(20, 128)),
        closeTo(128, 0.5),
      );
    });
  });

  group('estimateSharpness', () {
    test('a perfectly flat image has zero sharpness', () {
      expect(FrameQualityAnalyzer.estimateSharpness(_solidImage(80, 150)), 0);
    });

    test('a high-contrast checkerboard has high sharpness', () {
      final sharpness = FrameQualityAnalyzer.estimateSharpness(
        _checkerboard(80),
      );
      expect(sharpness, greaterThan(FrameQualityAnalyzer.minSharpness));
    });
  });

  group('evaluate', () {
    test('a dark region is flagged as poor lighting', () {
      final frame = _solidImage(100, 10);
      final issue = FrameQualityAnalyzer.evaluate(
        frame,
        const Rect.fromLTWH(10, 10, 40, 40),
      );
      expect(issue, FaceQualityIssue.poorLighting);
    });

    test('an overexposed region is flagged as poor lighting', () {
      final frame = _solidImage(100, 250);
      final issue = FrameQualityAnalyzer.evaluate(
        frame,
        const Rect.fromLTWH(10, 10, 40, 40),
      );
      expect(issue, FaceQualityIssue.poorLighting);
    });

    test('a well-lit but flat (blurred) region is flagged as too blurry', () {
      final frame = _solidImage(100, 150);
      final issue = FrameQualityAnalyzer.evaluate(
        frame,
        const Rect.fromLTWH(10, 10, 40, 40),
      );
      expect(issue, FaceQualityIssue.tooBlurry);
    });

    test('a well-lit, sharp region passes with no issue', () {
      final frame = _checkerboard(100);
      final issue = FrameQualityAnalyzer.evaluate(
        frame,
        const Rect.fromLTWH(10, 10, 60, 60),
      );
      expect(issue, isNull);
    });

    test('a face region outside the frame bounds does not throw', () {
      final frame = _checkerboard(50);
      expect(
        () => FrameQualityAnalyzer.evaluate(
          frame,
          const Rect.fromLTWH(-20, -20, 200, 200),
        ),
        returnsNormally,
      );
    });
  });
}
