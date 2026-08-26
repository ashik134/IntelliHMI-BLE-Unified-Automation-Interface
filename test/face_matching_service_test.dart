import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/face_match_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';

const _currentVersion = 'mobilefacenet_v1';

FaceTemplate _template(String operatorId, List<double> embedding, {String? version}) {
  return FaceTemplate(
    templateId: 'T-$operatorId',
    operatorId: operatorId,
    embedding: embedding,
    modelVersion: version ?? _currentVersion,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('cosineSimilarity', () {
    test('identical vectors score 1.0', () {
      final v = [1.0, 0.0, 0.0];
      expect(FaceMatchingService.cosineSimilarity(v, v), closeTo(1.0, 1e-9));
    });

    test('orthogonal vectors score 0.0', () {
      expect(
        FaceMatchingService.cosineSimilarity([1.0, 0.0], [0.0, 1.0]),
        closeTo(0.0, 1e-9),
      );
    });

    test('opposite vectors score -1.0', () {
      expect(
        FaceMatchingService.cosineSimilarity([1.0, 0.0], [-1.0, 0.0]),
        closeTo(-1.0, 1e-9),
      );
    });

    test('throws on length mismatch', () {
      expect(
        () => FaceMatchingService.cosineSimilarity([1.0], [1.0, 0.0]),
        throwsArgumentError,
      );
    });
  });

  group('match', () {
    test('matches the clear best candidate above threshold', () {
      final live = [1.0, 0.0, 0.0];
      final result = FaceMatchingService.match(
        liveEmbedding: live,
        candidates: [
          _template('OP-1', [0.999, 0.001, 0.0]),
          _template('OP-2', [0.0, 1.0, 0.0]),
        ],
        currentModelVersion: _currentVersion,
      );
      expect(result.isMatch, isTrue);
      expect(result.matchedOperatorId, 'OP-1');
      expect(result.ambiguous, isFalse);
    });

    test('rejects when the best score is below threshold', () {
      final result = FaceMatchingService.match(
        liveEmbedding: [1.0, 0.0],
        candidates: [_template('OP-1', [0.0, 1.0])],
        currentModelVersion: _currentVersion,
        threshold: 0.9,
      );
      expect(result.isMatch, isFalse);
      expect(result.matchedOperatorId, isNull);
    });

    test('rejects an ambiguous result even above threshold', () {
      // Two candidates score almost identically — must not guess.
      final result = FaceMatchingService.match(
        liveEmbedding: [1.0, 0.0, 0.0],
        candidates: [
          _template('OP-1', [0.99, 0.01, 0.0]),
          _template('OP-2', [0.985, 0.015, 0.0]),
        ],
        currentModelVersion: _currentVersion,
        threshold: 0.8,
        ambiguityMargin: 0.05,
      );
      expect(result.isMatch, isFalse);
      expect(result.ambiguous, isTrue);
    });

    test('excludes templates with a mismatched model version', () {
      final result = FaceMatchingService.match(
        liveEmbedding: [1.0, 0.0],
        candidates: [
          _template('OP-1', [1.0, 0.0], version: 'mobilefacenet_v0_old'),
        ],
        currentModelVersion: _currentVersion,
      );
      expect(result.isMatch, isFalse);
      expect(result, isA<FaceMatchResult>());
    });

    test('returns noCandidates-equivalent when nothing is enrolled', () {
      final result = FaceMatchingService.match(
        liveEmbedding: [1.0, 0.0],
        candidates: const [],
        currentModelVersion: _currentVersion,
      );
      expect(result.isMatch, isFalse);
      expect(result.secondBestScore, isNull);
    });
  });
}
