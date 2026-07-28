import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/joystick_control.dart';

void main() {
  testWidgets(
    'disabling an active joystick defers neutral command until after build',
    (tester) async {
      await tester.pumpWidget(const _JoystickHarness(enabled: true));

      final joystick = find.byType(IndustrialJoystickControl);
      final center = tester.getCenter(joystick);
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, -72));
      await tester.pump();

      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const _JoystickHarness(enabled: false));
      expect(
        tester.takeException(),
        isNull,
        reason:
            'didUpdateWidget must not call parent onChanged synchronously '
            'because the parent may setState while Flutter is still building.',
      );

      await tester.pump();
      expect(tester.takeException(), isNull);

      await gesture.cancel();
    },
  );
}

class _JoystickHarness extends StatefulWidget {
  const _JoystickHarness({required this.enabled});

  final bool enabled;

  @override
  State<_JoystickHarness> createState() => _JoystickHarnessState();
}

class _JoystickHarnessState extends State<_JoystickHarness> {
  JoystickOutput _lastOutput = const JoystickOutput(
    x: 0,
    y: 0,
    xStep: 0,
    yStep: 0,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 180,
                height: 180,
                child: IndustrialJoystickControl(
                  config: const JoystickConfig(),
                  label: 'Joystick',
                  activeColor: Colors.orange,
                  activeColorLight: Colors.orangeAccent,
                  enabled: widget.enabled,
                  onChanged: (output) => setState(() => _lastOutput = output),
                ),
              ),
              Text('${_lastOutput.xStep}:${_lastOutput.yStep}'),
            ],
          ),
        ),
      ),
    );
  }
}
