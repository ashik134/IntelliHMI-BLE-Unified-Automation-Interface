import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/liveness_challenge.dart';
import 'package:rev_crane_control_ops/services/face_liveness_service.dart';

DetectedFace _face({double? leftEye, double? rightEye, double? yaw, double? pitch}) {
  return DetectedFace(
    boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
    imageSize: const Size(400, 400),
    leftEyeOpenProbability: leftEye,
    rightEyeOpenProbability: rightEye,
    headEulerAngleY: yaw,
    headEulerAngleX: pitch,
  );
}

void main() {
  group('blink challenge', () {
    test('completes when eyes close then reopen', () {
      final session = LivenessSession(LivenessChallengeType.blink);
      final now = DateTime.now();

      var state = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.9, rightEye: 0.9),
        now: now,
      );
      expect(state.completed, isFalse);
      expect(state.progress, 0.0);

      state = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.1, rightEye: 0.1),
        now: now.add(const Duration(milliseconds: 100)),
      );
      expect(state.completed, isFalse);
      expect(state.progress, 0.5);

      state = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.9, rightEye: 0.9),
        now: now.add(const Duration(milliseconds: 200)),
      );
      expect(state.completed, isTrue);
      expect(state.progress, 1.0);
    });

    test('does not complete without ever seeing eyes close', () {
      final session = LivenessSession(LivenessChallengeType.blink);
      final state = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.9, rightEye: 0.9),
      );
      expect(state.completed, isFalse);
    });
  });

  group('turn challenges', () {
    test('turnLeft completes after holding the pose long enough', () {
      final session = LivenessSession(LivenessChallengeType.turnLeft);
      final now = DateTime.now();

      final first = session.processFrame(
        faceCount: 1,
        face: _face(yaw: -20),
        now: now,
      );
      expect(first.completed, isFalse);

      final state = session.processFrame(
        faceCount: 1,
        face: _face(yaw: -20),
        now: now.add(const Duration(milliseconds: 700)),
      );
      expect(state.completed, isTrue);
    });

    test('resets hold progress if the pose is lost before completion', () {
      final session = LivenessSession(LivenessChallengeType.turnLeft);
      final now = DateTime.now();

      session.processFrame(faceCount: 1, face: _face(yaw: -20), now: now);
      final lost = session.processFrame(
        faceCount: 1,
        face: _face(yaw: 0),
        now: now.add(const Duration(milliseconds: 300)),
      );
      expect(lost.progress, 0.0);

      // Re-establishing the pose restarts the hold timer rather than
      // resuming from where it left off.
      session.processFrame(
        faceCount: 1,
        face: _face(yaw: -20),
        now: now.add(const Duration(milliseconds: 400)),
      );
      final state = session.processFrame(
        faceCount: 1,
        face: _face(yaw: -20),
        now: now.add(const Duration(milliseconds: 600)),
      );
      expect(state.completed, isFalse);
    });

    test('turnRight pose does not satisfy turnLeft', () {
      final session = LivenessSession(LivenessChallengeType.turnLeft);
      final now = DateTime.now();
      final state = session.processFrame(
        faceCount: 1,
        face: _face(yaw: 20),
        now: now.add(const Duration(milliseconds: 700)),
      );
      expect(state.progress, 0.0);
    });
  });

  group('lookStraight challenge', () {
    test('completes when both angles stay near zero', () {
      final session = LivenessSession(LivenessChallengeType.lookStraight);
      final now = DateTime.now();
      session.processFrame(faceCount: 1, face: _face(yaw: 2, pitch: -3), now: now);
      final state = session.processFrame(
        faceCount: 1,
        face: _face(yaw: 2, pitch: -3),
        now: now.add(const Duration(milliseconds: 700)),
      );
      expect(state.completed, isTrue);
    });
  });

  group('anti-spoof / edge cases', () {
    test('fails immediately when no face is present mid-challenge', () {
      final session = LivenessSession(LivenessChallengeType.blink);
      final state = session.processFrame(faceCount: 0, face: null);
      expect(state.failed, isTrue);
      expect(state.failureReason, contains('lost'));
    });

    test('fails immediately when multiple faces are present', () {
      final session = LivenessSession(LivenessChallengeType.blink);
      final state = session.processFrame(
        faceCount: 2,
        face: _face(leftEye: 0.9, rightEye: 0.9),
      );
      expect(state.failed, isTrue);
    });

    test('times out after the configured duration', () {
      final now = DateTime.now();
      final session = LivenessSession(
        LivenessChallengeType.blink,
        startedAt: now,
        timeout: const Duration(seconds: 2),
      );
      final state = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.9, rightEye: 0.9),
        now: now.add(const Duration(seconds: 3)),
      );
      expect(state.timedOut, isTrue);
    });

    test('a terminal state is returned verbatim on subsequent calls', () {
      final session = LivenessSession(LivenessChallengeType.blink);
      final now = DateTime.now();
      final failed = session.processFrame(faceCount: 0, face: null, now: now);
      expect(failed.failed, isTrue);

      // Must not "recover" into completed just because a face reappears —
      // once terminal, a session stays terminal; the caller starts a new
      // LivenessSession for another attempt.
      final again = session.processFrame(
        faceCount: 1,
        face: _face(leftEye: 0.9, rightEye: 0.9),
        now: now,
      );
      expect(again.failed, isTrue);
      expect(again.completed, isFalse);
    });
  });
}
