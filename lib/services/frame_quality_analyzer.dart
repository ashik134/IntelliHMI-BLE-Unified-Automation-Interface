import 'dart:ui';

import 'package:image/image.dart' as img;

import 'package:rev_crane_control_ops/models/face_quality_result.dart';

/// Raw-pixel-buffer quality checks that `FaceDetectionService.evaluateQuality`
/// deliberately doesn't do — see its class doc comment: ML Kit's `Face`
/// result doesn't expose brightness or sharpness, and only the capture
/// screen (which owns the decoded frame) has the buffer needed to check
/// them. Pure image math, no ML Kit/camera dependency — unit-testable with
/// synthetic `img.Image`s.
class FrameQualityAnalyzer {
  FrameQualityAnalyzer._();

  static const double minBrightness = 60;
  static const double maxBrightness = 235;
  static const double minSharpness = 30;

  /// Returns the first issue found (lighting checked before sharpness), or
  /// null if the region inside [faceRegion] (in [frame]'s own pixel
  /// coordinates) passes both checks.
  static FaceQualityIssue? evaluate(img.Image frame, Rect faceRegion) {
    final region = _cropRegion(frame, faceRegion);

    final brightness = estimateBrightness(region);
    if (brightness < minBrightness || brightness > maxBrightness) {
      return FaceQualityIssue.poorLighting;
    }

    final sharpness = estimateSharpness(region);
    if (sharpness < minSharpness) {
      return FaceQualityIssue.tooBlurry;
    }

    return null;
  }

  /// Mean luma (ITU-R BT.601 weights) over [region], 0..255.
  static double estimateBrightness(img.Image region) {
    var sum = 0.0;
    var count = 0;
    for (final pixel in region) {
      sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }

  /// A cheap sharpness estimate: variance of a 3x3 Laplacian edge response
  /// over a small grayscale downsample of [region]. Higher = sharper; a
  /// heavily blurred/out-of-focus face produces a low-variance, mostly-flat
  /// edge response. Downsampling first keeps the per-sample cost small and
  /// roughly constant regardless of the camera's native resolution — this
  /// only needs to detect meaningful blur, not fine detail.
  static double estimateSharpness(img.Image region) {
    const targetSize = 64;
    final small = img.copyResize(
      region,
      width: targetSize,
      height: targetSize,
      interpolation: img.Interpolation.average,
    );

    final gray = List.generate(
      targetSize,
      (y) => List.generate(targetSize, (x) {
        final p = small.getPixel(x, y);
        return 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      }),
    );

    final responses = <double>[];
    for (var y = 1; y < targetSize - 1; y++) {
      for (var x = 1; x < targetSize - 1; x++) {
        final laplacian =
            4 * gray[y][x] -
            gray[y - 1][x] -
            gray[y + 1][x] -
            gray[y][x - 1] -
            gray[y][x + 1];
        responses.add(laplacian);
      }
    }
    if (responses.isEmpty) return 0;

    final mean = responses.reduce((a, b) => a + b) / responses.length;
    final variance =
        responses
            .map((v) => (v - mean) * (v - mean))
            .reduce((a, b) => a + b) /
        responses.length;
    return variance;
  }

  static img.Image _cropRegion(img.Image frame, Rect region) {
    final left = region.left.clamp(0, frame.width - 1).round();
    final top = region.top.clamp(0, frame.height - 1).round();
    final right = region.right.clamp(left + 1, frame.width).round();
    final bottom = region.bottom.clamp(top + 1, frame.height).round();
    return img.copyCrop(
      frame,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
  }
}
