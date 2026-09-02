/// Result of comparing one live embedding against every enrolled
/// candidate (spec section 14). [matchedOperatorId] is only non-null when
/// the best score clears the threshold **and** is clearly ahead of the
/// second-best — an ambiguous result is a rejection, never a guess.
class FaceMatchResult {
  const FaceMatchResult({
    required this.matchedOperatorId,
    required this.bestScore,
    required this.secondBestScore,
    required this.ambiguous,
    this.bestCandidateOperatorId,
    this.secondBestCandidateOperatorId,
  });

  const FaceMatchResult.noCandidates()
    : matchedOperatorId = null,
      bestScore = 0,
      secondBestScore = null,
      ambiguous = false,
      bestCandidateOperatorId = null,
      secondBestCandidateOperatorId = null;

  final String? matchedOperatorId;
  final double bestScore;
  final double? secondBestScore;
  final bool ambiguous;

  /// The highest-scoring candidate's operator ID, populated whenever there
  /// was at least one candidate to compare against — regardless of whether
  /// it actually cleared the match threshold. Unlike [matchedOperatorId]
  /// (the safe, confidence-gated decision this class exists to make),
  /// this exists purely so debug/verification tooling can show "closest
  /// candidate" for a rejected/ambiguous result without ever treating it
  /// as an actual match. Never use this in place of [matchedOperatorId]
  /// for an authentication or duplicate-detection decision.
  final String? bestCandidateOperatorId;

  /// Same idea as [bestCandidateOperatorId], for the runner-up.
  final String? secondBestCandidateOperatorId;

  bool get isMatch => matchedOperatorId != null;
}
