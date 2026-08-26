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
  });

  const FaceMatchResult.noCandidates()
    : matchedOperatorId = null,
      bestScore = 0,
      secondBestScore = null,
      ambiguous = false;

  final String? matchedOperatorId;
  final double bestScore;
  final double? secondBestScore;
  final bool ambiguous;

  bool get isMatch => matchedOperatorId != null;
}
