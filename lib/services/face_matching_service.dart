import 'dart:math';

import 'package:rev_crane_control_ops/models/face_match_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';

/// Compares a live embedding against every enrolled operator's template
/// (spec section 14). Pure math, no ML dependency of its own — fully
/// unit-testable. Never picks "the closest face": a match requires
/// clearing both an absolute [threshold] and a margin
/// ([ambiguityMargin]) over the runner-up, or it's rejected rather than
/// guessed.
class FaceMatchingService {
  FaceMatchingService._();

  static const double defaultThreshold = 0.87;
  static const double defaultAmbiguityMargin = 0.03;

  /// [currentModelVersion] is passed in (rather than this service
  /// importing FaceEmbeddingService) so matching stays a pure function
  /// over models only — templates whose modelVersion doesn't match are
  /// excluded rather than compared across incompatible embedding spaces
  /// (spec section 25).
  static FaceMatchResult match({
    required List<double> liveEmbedding,
    required List<FaceTemplate> candidates,
    required String currentModelVersion,
    double threshold = defaultThreshold,
    double ambiguityMargin = defaultAmbiguityMargin,
  }) {
    final compatible = candidates
        .where((t) => t.modelVersion == currentModelVersion)
        .toList();

    if (compatible.isEmpty) return const FaceMatchResult.noCandidates();

    String? bestOperatorId;
    var bestScore = -1.0;
    double? secondBestScore;

    for (final candidate in compatible) {
      final score = cosineSimilarity(liveEmbedding, candidate.embedding);
      if (score > bestScore) {
        secondBestScore = bestScore == -1.0 ? null : bestScore;
        bestScore = score;
        bestOperatorId = candidate.operatorId;
      } else if (secondBestScore == null || score > secondBestScore) {
        secondBestScore = score;
      }
    }

    final belowThreshold = bestScore < threshold;
    final tooAmbiguous =
        secondBestScore != null &&
        (bestScore - secondBestScore) < ambiguityMargin;

    if (belowThreshold || tooAmbiguous) {
      return FaceMatchResult(
        matchedOperatorId: null,
        bestScore: bestScore,
        secondBestScore: secondBestScore,
        ambiguous: tooAmbiguous && !belowThreshold,
      );
    }

    return FaceMatchResult(
      matchedOperatorId: bestOperatorId,
      bestScore: bestScore,
      secondBestScore: secondBestScore,
      ambiguous: false,
    );
  }

  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Embedding length mismatch: ${a.length} vs ${b.length}',
      );
    }
    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }
}
