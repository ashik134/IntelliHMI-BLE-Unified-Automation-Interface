/// An active liveness challenge (spec section 9) — the operator must
/// perform a specific action in front of the camera; a static photo or
/// screen replay can't produce the required motion on cue.
enum LivenessChallengeType {
  blink('Blink'),
  turnLeft('Turn your head left'),
  turnRight('Turn your head right'),
  lookStraight('Look straight at the camera');

  const LivenessChallengeType(this.instruction);

  final String instruction;
}

/// Progress of one in-flight liveness challenge, reported once per
/// processed frame by [FaceLivenessService].
class LivenessChallengeState {
  const LivenessChallengeState({
    required this.challenge,
    required this.progress,
    this.completed = false,
    this.failed = false,
    this.timedOut = false,
    this.failureReason,
  });

  final LivenessChallengeType challenge;

  /// 0.0 (just started) to 1.0 (challenge satisfied).
  final double progress;

  final bool completed;
  final bool failed;
  final bool timedOut;
  final String? failureReason;

  bool get isDone => completed || failed || timedOut;
}
