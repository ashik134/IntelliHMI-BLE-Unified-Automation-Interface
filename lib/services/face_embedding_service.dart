import 'dart:math';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Wraps the bundled MobileFaceNet TFLite model to turn an aligned face
/// crop into a 192-dimensional, L2-normalized embedding vector.
///
/// **See `assets/models/NOTICE_mobilefacenet.txt` before enabling real
/// operator enrollment.** This model's training-data provenance is not
/// documented upstream and likely traces to datasets (MS-Celeb-1M/CASIA-
/// WebFace lineage) since withdrawn elsewhere over consent concerns. Do
/// not match real people's faces against templates from this service in
/// production until that's cleared your own legal/compliance review —
/// it's bundled now so the pipeline is genuinely testable in development,
/// not because it's cleared for production use on real people.
///
/// [embed]'s actual inference cannot be verified in this dev environment:
/// `tflite_flutter` needs a platform-matching native TensorFlow Lite
/// library resolved via FFI, which a bare `flutter test` on this Windows
/// machine is not expected to resolve outside a full app build (see
/// Stage 3's plan). Only on-device testing confirms this actually runs;
/// this class compiling and its pure helper methods being unit-testable
/// is as far as this environment can verify.
class FaceEmbeddingService {
  FaceEmbeddingService._(this._interpreter);

  static const String modelVersion = 'mobilefacenet_v1';
  static const int inputSize = 112;
  static const int embeddingLength = 192;

  final Interpreter _interpreter;

  static Future<FaceEmbeddingService> load() async {
    final interpreter = await Interpreter.fromAsset(
      'assets/models/mobilefacenet.tflite',
    );
    return FaceEmbeddingService._(interpreter);
  }

  void close() => _interpreter.close();

  /// [alignedFace] must already be a face crop (see [cropToFace]) — this
  /// only resizes to the model's input size, normalizes, and runs
  /// inference.
  Future<List<double>> embed(img.Image alignedFace) async {
    final resized = img.copyResize(
      alignedFace,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = [
      List.generate(
        inputSize,
        (y) => List.generate(inputSize, (x) {
          final pixel = resized.getPixel(x, y);
          return [
            (pixel.r - 128) / 128,
            (pixel.g - 128) / 128,
            (pixel.b - 128) / 128,
          ];
        }),
      ),
    ];

    final output = [List.filled(embeddingLength, 0.0)];
    _interpreter.run(input, output);

    return l2Normalize(output[0]);
  }

  /// Crops [source] to the detected face's bounding box with a fixed
  /// padding (matching the reference implementation this model was
  /// sourced alongside), then to a centered square so the later resize to
  /// [inputSize]x[inputSize] doesn't distort the face. Pure image math —
  /// unit-testable without the interpreter.
  static img.Image cropToFace(img.Image source, Rect boundingBox) {
    const padding = 10;
    final left = (boundingBox.left - padding).clamp(0, source.width - 1).round();
    final top = (boundingBox.top - padding).clamp(0, source.height - 1).round();
    final right = (boundingBox.right + padding)
        .clamp(left + 1, source.width)
        .round();
    final bottom = (boundingBox.bottom + padding)
        .clamp(top + 1, source.height)
        .round();

    final cropped = img.copyCrop(
      source,
      x: left,
      y: top,
      width: right - left,
      height: bottom - top,
    );
    return img.copyResizeCropSquare(
      cropped,
      size: max(cropped.width, cropped.height),
    );
  }

  /// Pure math — unit-testable without the interpreter.
  static List<double> l2Normalize(List<double> vector) {
    var sumSquares = 0.0;
    for (final v in vector) {
      sumSquares += v * v;
    }
    final norm = sqrt(sumSquares);
    if (norm == 0) return vector;
    return vector.map((v) => v / norm).toList();
  }
}
