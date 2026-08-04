// Widget-level regression guard for IndustrialSpringButton's new
// debounce/long-press-required behavior (see ButtonBehaviorConfig
// .debounceMs/.longPressRequiredMs):
//   - debounceMs=0 / longPressRequiredMs=0 (the defaults) behave exactly
//     like before this feature: activation on pointer-down, no gating.
//   - debounceMs > 0 ignores a new press that starts too soon after the
//     previous release.
//   - longPressRequiredMs > 0 (spring-return only) defers activation until
//     the hold duration elapses, and a release before then never activates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/buttons/button/push_control_button.dart';

Widget _harness({
  required bool isSpringReturn,
  int debounceMs = 0,
  int longPressRequiredMs = 0,
  required ValueChanged<bool> onChanged,
  VoidCallback? onPressed,
  VoidCallback? onReleased,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 200,
          height: 240,
          child: IndustrialSpringButton(
            label: 'Test',
            icon: Icons.circle,
            isSpringReturn: isSpringReturn,
            debounceMs: debounceMs,
            longPressRequiredMs: longPressRequiredMs,
            onChanged: onChanged,
            onPressed: onPressed,
            onReleased: onReleased,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'defaults (debounce/long-press off) activate immediately on pointer-down, '
    'exactly like before this feature existed',
    (tester) async {
      var pressedCount = 0;
      await tester.pumpWidget(
        _harness(
          isSpringReturn: true,
          onChanged: (_) {},
          onPressed: () => pressedCount++,
        ),
      );

      final center = tester.getCenter(find.byType(IndustrialSpringButton));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      expect(pressedCount, 1);
      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'debounceMs ignores a press that starts too soon after the previous release',
    (tester) async {
      var pressedCount = 0;
      await tester.pumpWidget(
        _harness(
          isSpringReturn: true,
          debounceMs: 300,
          onChanged: (_) {},
          onPressed: () => pressedCount++,
        ),
      );

      final center = tester.getCenter(find.byType(IndustrialSpringButton));

      final first = await tester.startGesture(center);
      await tester.pump();
      expect(pressedCount, 1);
      await first.up();
      await tester.pump();

      // Well within the 300ms debounce window — must be ignored entirely.
      await tester.pump(const Duration(milliseconds: 100));
      final second = await tester.startGesture(center);
      await tester.pump();
      expect(pressedCount, 1, reason: 'debounced press must not activate');
      await second.up();
      await tester.pump();

      // Past the debounce window — a fresh press must activate normally.
      await tester.pump(const Duration(milliseconds: 350));
      final third = await tester.startGesture(center);
      await tester.pump();
      expect(pressedCount, 2);
      await third.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'longPressRequiredMs defers activation until the hold duration elapses',
    (tester) async {
      var pressedCount = 0;
      var activeValue = false;
      await tester.pumpWidget(
        _harness(
          isSpringReturn: true,
          longPressRequiredMs: 400,
          onChanged: (v) => activeValue = v,
          onPressed: () => pressedCount++,
        ),
      );

      final center = tester.getCenter(find.byType(IndustrialSpringButton));
      final gesture = await tester.startGesture(center);
      await tester.pump();
      // Pressed animation may start immediately, but activation is deferred.
      expect(pressedCount, 0);
      expect(activeValue, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(pressedCount, 0, reason: 'hold duration has not elapsed yet');

      await tester.pump(const Duration(milliseconds: 250));
      expect(pressedCount, 1, reason: 'hold duration elapsed — now activates');
      expect(activeValue, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'releasing before the long-press hold duration elapses never activates',
    (tester) async {
      var pressedCount = 0;
      await tester.pumpWidget(
        _harness(
          isSpringReturn: true,
          longPressRequiredMs: 400,
          onChanged: (_) {},
          onPressed: () => pressedCount++,
        ),
      );

      final center = tester.getCenter(find.byType(IndustrialSpringButton));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 150));
      await gesture.up();
      await tester.pumpAndSettle();

      // Let the (now-cancelled) timer's original deadline pass — it must
      // never fire after release.
      await tester.pump(const Duration(milliseconds: 400));
      expect(pressedCount, 0);
    },
  );
}
