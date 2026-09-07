import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/controllers/inactivity_controller.dart';

/// Drives [InactivityController] under a fake clock so the real 3-minute
/// deadline can be exercised in milliseconds. The controller's injected
/// clock is tied to the same fake timeline its Timers run on, so wall-clock
/// reconciliation and Timer firing can never disagree by accident.
void _withController(
  void Function(FakeAsync async, InactivityController c, List<InactivityPhase> seen)
  body, {
  Duration sleepAfter = const Duration(minutes: 3),
  Duration disconnectAfterSleep = const Duration(minutes: 2),
}) {
  fakeAsync((async) {
    final start = DateTime(2026, 1, 1);
    final controller = InactivityController(
      sleepAfter: sleepAfter,
      disconnectAfterSleep: disconnectAfterSleep,
      clock: () => start.add(async.elapsed),
    );
    final seen = <InactivityPhase>[];
    controller.addListener(() => seen.add(controller.phase));
    addTearDown(controller.dispose);
    body(async, controller, seen);
  });
}

void main() {
  group('inactivity deadline', () {
    test('stays active for the first three minutes', () {
      _withController((async, c, seen) {
        c.start();
        async.elapse(const Duration(minutes: 2, seconds: 59));
        expect(c.phase, InactivityPhase.active);
        expect(c.isSleeping, isFalse);
        expect(seen, isEmpty);
      });
    });

    test('sleeps at exactly three minutes of no interaction', () {
      _withController((async, c, seen) {
        c.start();
        async.elapse(const Duration(minutes: 3));
        expect(c.phase, InactivityPhase.sleeping);
        expect(seen, [InactivityPhase.sleeping]);
      });
    });

    test('expires two minutes after sleeping, and only once', () {
      _withController((async, c, seen) {
        c.start();
        async.elapse(const Duration(minutes: 5));
        expect(c.phase, InactivityPhase.expired);
        expect(seen, [InactivityPhase.sleeping, InactivityPhase.expired]);

        // Terminal: no further transitions once expired.
        async.elapse(const Duration(minutes: 30));
        expect(seen, [InactivityPhase.sleeping, InactivityPhase.expired]);
      });
    });

    test('activity before the deadline restarts the full three minutes', () {
      _withController((async, c, seen) {
        c.start();
        async.elapse(const Duration(minutes: 2, seconds: 50));
        c.registerActivity();

        // The original deadline passes without firing...
        async.elapse(const Duration(seconds: 20));
        expect(c.phase, InactivityPhase.active);
        expect(seen, isEmpty);

        // ...and the clock runs from the interaction instead.
        async.elapse(const Duration(minutes: 2, seconds: 40));
        expect(c.phase, InactivityPhase.sleeping);
      });
    });

    test('waking from sleep cancels the pending expiry', () {
      _withController((async, c, seen) {
        c.start();
        async.elapse(const Duration(minutes: 3));
        expect(c.phase, InactivityPhase.sleeping);

        c.registerActivity();
        expect(c.phase, InactivityPhase.active);

        // Would have expired here had the wake not reset the machine.
        async.elapse(const Duration(minutes: 2, seconds: 30));
        expect(c.phase, InactivityPhase.active);
        expect(seen, [InactivityPhase.sleeping, InactivityPhase.active]);
      });
    });

    test('stop() halts the machine before the deadline', () {
      _withController((async, c, seen) {
        c.start();
        c.stop();
        async.elapse(const Duration(minutes: 30));
        expect(c.phase, InactivityPhase.active);
        expect(seen, isEmpty);
      });
    });
  });

  group('backgrounded app reconciliation', () {
    test('a suspended timer still sleeps once elapsed time is reconciled', () {
      _withController((async, c, seen) {
        c.start();
        // Stand in for the OS suspending Dart Timers while backgrounded:
        // real time passes but no Timer fires.
        c.pauseTimerForBackground();
        async.elapse(const Duration(minutes: 4));
        expect(c.phase, InactivityPhase.active, reason: 'timer was suspended');

        c.reconcileAfterResume();
        expect(c.phase, InactivityPhase.sleeping);
        expect(seen, [InactivityPhase.sleeping]);
      });
    });

    test('resuming past the whole window goes straight to expired', () {
      _withController((async, c, seen) {
        c.start();
        c.pauseTimerForBackground();
        async.elapse(const Duration(minutes: 20));

        c.reconcileAfterResume();
        expect(c.phase, InactivityPhase.expired);
        expect(seen, [InactivityPhase.expired]);
      });
    });

    test('resuming before the deadline leaves the machine active', () {
      _withController((async, c, seen) {
        c.start();
        c.pauseTimerForBackground();
        async.elapse(const Duration(minutes: 1));

        c.reconcileAfterResume();
        expect(c.phase, InactivityPhase.active);
        expect(seen, isEmpty);

        // The rescheduled timer still fires at the original deadline.
        async.elapse(const Duration(minutes: 2));
        expect(c.phase, InactivityPhase.sleeping);
      });
    });
  });
}
