import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/toggle_switch_button.dart';

void main() {
  group('ToggleSwitchButton position indicators', () {
    testWidgets('shows O and T for O-T spring-return mode', (tester) async {
      await _pumpToggle(tester, ToggleSwitchMode.springReturnOneSide);

      expect(find.text('O'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
      expect(find.text('R'), findsNothing);
    });

    testWidgets('shows O and R for O-R latching mode', (tester) async {
      await _pumpToggle(
        tester,
        ToggleSwitchMode.latchingOneSide,
        isSpringReturn: false,
      );

      expect(find.text('O'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
      expect(find.text('T'), findsNothing);
    });

    testWidgets('shows R, O, and R for R-O-R mode', (tester) async {
      await _pumpToggle(tester, ToggleSwitchMode.springReturnBoth);

      expect(find.text('R'), findsNWidgets(2));
      expect(find.text('O'), findsOneWidget);
      expect(find.text('T'), findsNothing);
    });

    testWidgets('shows T, O, and T for T-O-T mode', (tester) async {
      await _pumpToggle(
        tester,
        ToggleSwitchMode.latchingBoth,
        isSpringReturn: false,
      );

      expect(find.text('T'), findsNWidgets(2));
      expect(find.text('O'), findsOneWidget);
      expect(find.text('R'), findsNothing);
    });

    testWidgets('shows T, O, and R for T-O-R mode', (tester) async {
      await _pumpToggle(tester, ToggleSwitchMode.mixed);

      expect(find.text('T'), findsOneWidget);
      expect(find.text('O'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);
    });

    testWidgets('indicator overlay does not intercept spring-return gestures', (
      tester,
    ) async {
      final commands = await _pumpToggle(
        tester,
        ToggleSwitchMode.springReturnOneSide,
      );
      final rect = tester.getRect(find.byType(ToggleSwitchButton));
      final bottomIndicatorPoint = Offset(
        rect.center.dx + rect.width * 0.27,
        rect.top + rect.height * 0.70,
      );

      final gesture = await tester.startGesture(bottomIndicatorPoint);
      await tester.pump();
      expect(commands.last, ControlState.slow);

      await gesture.up();
      await tester.pump();
      expect(commands.last, ControlState.idle);
    });
  });
}

Future<List<ControlState>> _pumpToggle(
  WidgetTester tester,
  ToggleSwitchMode mode, {
  bool isSpringReturn = true,
}) async {
  final commands = <ControlState>[];

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            height: 240,
            child: ToggleSwitchButton(
              label: 'SWITCH',
              icon: Icons.toggle_on_rounded,
              activeColor: AppColors.accent,
              activeColorLight: AppColors.upColorLight,
              isActive: false,
              isDisabled: false,
              isSpringReturn: isSpringReturn,
              mode: mode,
              onCommandChanged: commands.add,
            ),
          ),
        ),
      ),
    ),
  );

  expect(commands, isEmpty);
  return commands;
}
