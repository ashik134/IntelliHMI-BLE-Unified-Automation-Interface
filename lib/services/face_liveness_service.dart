import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/liveness_challenge.dart';

/// Tracks progress of one active liveness challenge across successive
/// detection frames (spec section 9). Pure state machine — consumes only
/// [DetectedFace], no ML Kit/camera dependency of its own, so it's fully
/// unit-testable with hand-built frame sequences.
///
/// The caller calls [processFrame] once per detection result, including
/// when zero or multiple faces were found — treated as an anti-spoof
/// signal (a second photo held up, or the subject stepping out of frame)
/// rather than silently ignored. This is deliberately strict; if
/// on-device testing shows normal head turns transiently drop detection
/// for a single frame, tolerating one bad frame before failing is the
/// first knob to turn.
///
/// `headEulerAngleY` sign convention: [_isTurnedLeft]/[_isTurnedRight] now
/// follow [DetectedFace.headEulerAngleY]'s own documented convention
/// (positive = turned toward the subject's left) via [config] — this file
/// previously used the opposite sign, contradicting that doc comment,
/// which is why turn challenges were disabled elsewhere in this codebase.
/// [config]`.yawLeftIsPositive` is a one-flag override if on-device
/// testing shows the real ML Kit build disagrees.
class LivenessSession {
  LivenessSession(
    this.challenge, {
    DateTime? startedAt,
    this.timeout = const Duration(seconds: 8),
    this.config = FaceEnrollmentConfig.defaults,
  }) : _startedAt = startedAt ?? DateTime.now();

  final LivenessChallengeType challenge;
  final Duration timeout;
  final FaceEnrollmentConfig config;
  final DateTime _startedAt;

  static const double _eyeClosedThreshold = 0.35;
  static const double _eyeOpenThreshold = 0.6;
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
    if (angle == null) return false;
    final threshold = config.leftTurnYawThreshold;
    return config.yawLeftIsPositive ? angle > threshold : angle < threshold;
  }

  bool _isTurnedRight(DetectedFace face) {
    final angle = face.headEulerAngleY;
    if (angle == null) return false;
    final threshold = config.rightTurnYawThreshold;
    return config.yawLeftIsPositive ? angle < threshold : angle > threshold;
  }

  bool _isLookingStraight(DetectedFace face) {
    final yaw = face.headEulerAngleY;
    final pitch = face.headEulerAngleX;
    if (yaw == null || pitch == null) return false;
    return yaw.abs() < _straightAngleTolerance &&
        pitch.abs() < _straightAngleTolerance;
  }
}
