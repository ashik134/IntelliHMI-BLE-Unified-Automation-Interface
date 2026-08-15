import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/joystick_control.dart';

void main() {
  testWidgets(
    '1D digital joystick emits only when its logical detent changes',
    (tester) async {
      final outputs = <JoystickOutput>[];
      await _pumpJoystick(
        tester,
        config: const JoystickConfig(
          mode: JoystickMode.singleAxisDigital5,
          axis: JoystickAxis.vertical,
        ),
        onChanged: outputs.add,
      );

      final joystick = find.byType(IndustrialJoystickControl);
      final gesture = await tester.startGesture(tester.getCenter(joystick));

      await gesture.moveBy(const Offset(0, -45));
      await tester.pump();
      expect(outputs.map((output) => output.yStep), [1]);

      // These movements change raw y but remain inside the same slow detent.
      await gesture.moveBy(const Offset(0, -5));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump();
      expect(outputs.map((output) => output.yStep), [1]);

      // Crossing into the fast detent is a real logical change.
      await gesture.moveBy(const Offset(0, -35));
      await tester.pump();
      expect(outputs.map((output) => output.yStep), [1, 2]);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(outputs.map((output) => output.yStep), [1, 2, 0]);
    },
  );

  testWidgets(
    '2D digital joystick emits only when its logical direction changes',
    (tester) async {
      final outputs = <JoystickOutput>[];
      await _pumpJoystick(
        tester,
        config: const JoystickConfig(mode: JoystickMode.dualAxisDigital4),
        onChanged: outputs.add,
      );

      final joystick = find.byType(IndustrialJoystickControl);
      final topLeft = tester.getTopLeft(joystick);
      // The cross gate reserves a label band below the gate, so its neutral
      // knob is slightly above the center of the complete widget.
      final gesture = await tester.startGesture(topLeft + const Offset(120, 102));

      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(outputs.map((output) => (output.xStep, output.yStep)), [(1, 0)]);

      // Raw x changes, but the knob remains in the same right-hand cell.
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-4, 0));
      await tester.pump();
      expect(outputs.map((output) => (output.xStep, output.yStep)), [(1, 0)]);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(outputs.map((output) => (output.xStep, output.yStep)), [
        (1, 0),
        (0, 0),
      ]);
    },
  );
}

Future<void> _pumpJoystick(
  WidgetTester tester, {
  required JoystickConfig config,
  required ValueChanged<JoystickOutput> onChanged,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.square(
            dimension: 240,
            child: IndustrialJoystickControl(
              config: config,
              label: 'Joystick',
              activeColor: Colors.orange,
              activeColorLight: Colors.orangeAccent,
              enabled: true,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}
