import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/liveness_challenge.dart';

/// Tracks progress of one active liveness challenge across successive
/// detection frames (spec section 9). Pure state machine — consumes only
/// [DetectedFace], no ML Kit/camera dependency of its own, so it's fully
/// unit-testable with hand-built frame sequences.
///
/// The caller (Stage 4) calls [processFrame] once per detection result,
/// including when zero or multiple faces were found — treated as an
/// anti-spoof signal (a second photo held up, or the subject stepping out
/// of frame) rather than silently ignored. This is deliberately strict;
/// if on-device testing shows normal head turns transiently drop
/// detection for a single frame, tolerating one bad frame before failing
/// is the first knob to turn — noted here rather than guessed at now,
/// since it needs real usage to tune.
///
/// NOTE on `headEulerAngleY` sign convention: ML Kit's exact left/right
/// sign has not been verified against a real device in this environment.
/// [_isTurnedLeft]/[_isTurnedRight] use a consistent, symmetric
/// convention that may need flipping once verified on-device — see
/// Stage 3's plan "what can and can't be verified here" section.
class LivenessSession {
  LivenessSession(
    this.challenge, {
    DateTime? startedAt,
    this.timeout = const Duration(seconds: 8),
  }) : _startedAt = startedAt ?? DateTime.now();

  final LivenessChallengeType challenge;
  final Duration timeout;
  final DateTime _startedAt;

  static const double _eyeClosedThreshold = 0.35;
  static const double _eyeOpenThreshold = 0.6;
  static const double _turnAngleThreshold = 15.0; // degrees
  static const double _straightAngleTolerance = 10.0; // degrees
  static const Duration _requiredHoldDuration = Duration(milliseconds: 600);

  bool _sawEyesClosed = false;
  DateTime? _poseHoldStartedAt;

  /// Set once [processFrame] reaches a terminal outcome (completed,
  /// failed, or timed out) and returned verbatim on every call after —
  /// deliberately not re-derived, so a session that already failed can
  /// never later report itself as completed just because `_done` is true.
  LivenessChallengeState? _terminalState;

  /// [faceCount] lets the caller report "zero" or "more than one" without
  /// constructing a placeholder [DetectedFace] for those cases.
  LivenessChallengeState processFrame({
    required int faceCount,
    DetectedFace? face,
    DateTime? now,
  }) {
    final existingTerminal = _terminalState;
    if (existingTerminal != null) return existingTerminal;

    final currentTime = now ?? DateTime.now();

    if (currentTime.difference(_startedAt) > timeout) {
      return _terminalState = LivenessChallengeState(
        challenge: challenge,
        progress: 0,
        timedOut: true,
        failureReason: 'Challenge timed out.',
      );
    }

    if (faceCount != 1 || face == null) {
      return _terminalState = LivenessChallengeState(
        challenge: challenge,
        progress: 0,
        failed: true,
        failureReason: faceCount == 0
            ? 'Face lost during challenge.'
            : 'More than one face detected during challenge.',
      );
    }

    final progress = switch (challenge) {
      LivenessChallengeType.blink => _updateBlink(face),
      LivenessChallengeType.turnLeft => _updatePoseHold(
        currentTime,
        _isTurnedLeft(face),
      ),
      LivenessChallengeType.turnRight => _updatePoseHold(
        currentTime,
        _isTurnedRight(face),
      ),
      LivenessChallengeType.lookStraight => _updatePoseHold(
        currentTime,
        _isLookingStraight(face),
      ),
    };

    final state = LivenessChallengeState(
      challenge: challenge,
      progress: progress.clamp(0.0, 1.0),
      completed: progress >= 1.0,
    );
    if (state.completed) _terminalState = state;
    return state;
  }

  double _updateBlink(DetectedFace face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left == null || right == null) return _sawEyesClosed ? 0.5 : 0.0;

    if (!_sawEyesClosed) {
      if (left < _eyeClosedThreshold && right < _eyeClosedThreshold) {
        _sawEyesClosed = true;
        return 0.5;
      }
      return 0.0;
    }

    if (left > _eyeOpenThreshold && right > _eyeOpenThreshold) {
      return 1.0;
    }
    return 0.5;
  }

  double _updatePoseHold(DateTime now, bool poseSatisfied) {
    if (!poseSatisfied) {
      _poseHoldStartedAt = null;
      return 0.0;
    }
    _poseHoldStartedAt ??= now;
    final held = now.difference(_poseHoldStartedAt!);
    return held.inMilliseconds / _requiredHoldDuration.inMilliseconds;
  }

  bool _isTurnedLeft(DetectedFace face) {
    final angle = face.headEulerAngleY;
    return angle != null && angle < -_turnAngleThreshold;
  }

  bool _isTurnedRight(DetectedFace face) {
    final angle = face.headEulerAngleY;
    return angle != null && angle > _turnAngleThreshold;
  }

  bool _isLookingStraight(DetectedFace face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    if (yaw == null || pitch == null) return false;
    return yaw.abs() < _straightAngleTolerance &&
        pitch.abs() < _straightAngleTolerance;
  }
}
