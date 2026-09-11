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

  /// Deliberately lower than an untuned guess would suggest, and grounded
  /// in evidence already established elsewhere in this codebase rather
  /// than a fresh guess: `FaceEnrollmentService.outlierSimilarityFloor`
  /// (0.75) is the bar *same-session, same-person* frames — the easiest
  /// case, same lighting/pose/camera warm-up, seconds apart — must clear
  /// to even be considered consistent with each other. A live verification
  /// attempt is strictly harder than that (different day, different
  /// lighting, different pose), so holding it to a *higher* bar than
  /// same-session consistency was the root cause of frequent false
  /// rejections for a genuinely enrolled operator. This value keeps a
  /// meaningful safety margin above that same-session floor rather than
  /// matching it exactly, since `FaceVerificationScreen` now matches on an
  /// average of several verification-phase embeddings (see
  /// `FaceEmbeddingService.averageEmbeddings`) rather than a single noisy
  /// frame, which pulls genuine scores up without needing the threshold
  /// itself to absorb single-frame noise. Still a starting point, not a
  /// final calibration — the debug `FaceVerifyScreen` prints the raw
  /// cosine score on every attempt specifically so this can be validated
  /// (and retuned, in one place) against real on-device genuine/impostor
  /// scores.
  static const double defaultThreshold = 0.80;
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
    String? secondBestOperatorId;
    double? secondBestScore;

    for (final candidate in compatible) {
      final score = cosineSimilarity(liveEmbedding, candidate.embedding);
      if (score > bestScore) {
        secondBestScore = bestScore == -1.0 ? null : bestScore;
        secondBestOperatorId = bestScore == -1.0 ? null : bestOperatorId;
        bestScore = score;
        bestOperatorId = candidate.operatorId;
      } else if (secondBestScore == null || score > secondBestScore) {
        secondBestScore = score;
        secondBestOperatorId = candidate.operatorId;
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
        bestCandidateOperatorId: bestOperatorId,
        secondBestCandidateOperatorId: secondBestOperatorId,
      );
    }

    return FaceMatchResult(
      matchedOperatorId: bestOperatorId,
      bestScore: bestScore,
      secondBestScore: secondBestScore,
      ambiguous: false,
      bestCandidateOperatorId: bestOperatorId,
      secondBestCandidateOperatorId: secondBestOperatorId,
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
