import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';

// `FaceEmbeddingService.embed` needs a real on-device TFLite interpreter
// (see its own doc comment), so only its pure-math static helpers —
// `l2Normalize`/`averageEmbeddings` — are exercised here.

void main() {
  group('l2Normalize', () {
    test('scales a vector to unit length', () {
      final normalized = FaceEmbeddingService.l2Normalize([3.0, 4.0]);
      expect(normalized[0], closeTo(0.6, 1e-9));
      expect(normalized[1], closeTo(0.8, 1e-9));
    });

    test('leaves an all-zero vector unchanged rather than dividing by zero', () {
      expect(FaceEmbeddingService.l2Normalize([0.0, 0.0]), [0.0, 0.0]);
    });
  });

  group('averageEmbeddings', () {
    test('averages identical embeddings back to the same unit vector', () {
      final result = FaceEmbeddingService.averageEmbeddings([
        [1.0, 0.0],
        [1.0, 0.0],
        [1.0, 0.0],
      ]);
      expect(result[0], closeTo(1.0, 1e-9));
      expect(result[1], closeTo(0.0, 1e-9));
    });

    test(
      'pools noisy same-identity embeddings closer to the true direction '
      'than any single noisy sample — the reliability property '
      'FaceVerificationScreen depends on',
      () {
        // Symmetric noise around (1, 0): averaging should cancel the
        // off-axis component out much more than any single sample does.
        final result = FaceEmbeddingService.averageEmbeddings([
          [0.95, 0.31],
          [0.95, -0.31],
          [0.90, 0.20],
          [0.90, -0.20],
        ]);
        expect(result[1].abs(), lessThan(0.05));
      },
    );

    test('returns a unit-length result', () {
      final result = FaceEmbeddingService.averageEmbeddings([
        [0.9, 0.1, 0.0],
        [0.8, 0.2, 0.1],
        [1.0, 0.0, 0.0],
      ]);
      var normSquared = 0.0;
      for (final v in result) {
        normSquared += v * v;
      }
      expect(normSquared, closeTo(1.0, 1e-9));
    });
  });
}
