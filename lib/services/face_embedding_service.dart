import 'dart:math';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceEmbeddingService {
  FaceEmbeddingService._(this._interpreter, this._isolateInterpreter);

  static const String modelVersion = 'mobilefacenet_v1';
  static const int inputSize = 112;
  static const int embeddingLength = 192;

  final Interpreter? _interpreter;
  final IsolateInterpreter? _isolateInterpreter;

  static Future<FaceEmbeddingService> load() async {
    final interpreter = await Interpreter.fromAsset(
      'assets/models/mobilefacenet.tflite',
    );
    return FaceEmbeddingService._(interpreter, null);
  }

  factory FaceEmbeddingService.fromIsolateInterpreter(
    IsolateInterpreter isolateInterpreter,
  ) => FaceEmbeddingService._(null, isolateInterpreter);

  int get address => _interpreter!.address;

  void close() => _interpreter?.close();

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
    final isolateInterpreter = _isolateInterpreter;
    if (isolateInterpreter != null) {
      await isolateInterpreter.run(input, output);
    } else {
      _interpreter!.run(input, output);
    }

    return l2Normalize(output[0]);
  }

  /// Crops [source] to the detected face's bounding box with a fixed
  /// padding (matching the reference implementation this model was
  /// sourced alongside), then to a centered square so the later resize to
  /// [inputSize]x[inputSize] doesn't distort the face. Pure image math —
  /// unit-testable without the interpreter.
  static img.Image cropToFace(img.Image source, Rect boundingBox) {
    const padding = 10;
    final left = (boundingBox.left - padding)
        .clamp(0, source.width - 1)
        .round();
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

  /// Averages several embeddings of (nominally) the same face into one
  /// representative, L2-normalized embedding — the same pooling technique
  /// `FaceEnrollmentService` already uses to build a template from several
  /// enrollment samples (see its own `_mean`/outlier-trim step). Per-frame
  /// pose/expression/lighting noise is roughly independent across frames,
  /// so averaging several live frames before matching pulls the aggregate
  /// closer to the subject's true identity direction than any single noisy
  /// frame would be — this is what makes multi-frame verification
  /// meaningfully more reliable than asking each frame to independently
  /// clear the match threshold (see `FaceVerificationScreen`, which uses
  /// this instead of a per-frame majority vote).
  static List<double> averageEmbeddings(List<List<double>> embeddings) {
    final length = embeddings.first.length;
    final sums = List<double>.filled(length, 0);
    for (final embedding in embeddings) {
      for (var i = 0; i < length; i++) {
        sums[i] += embedding[i];
      }
    }
    return l2Normalize([for (final s in sums) s / embeddings.length]);
  }
}
