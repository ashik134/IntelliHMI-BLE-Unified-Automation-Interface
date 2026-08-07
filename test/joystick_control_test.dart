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

  testWidgets('digital cross gate expands with its widget', (tester) async {
    Future<Size> pumpCrossGate(double extent) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox.square(
                dimension: extent,
                child: IndustrialJoystickControl(
                  config: const JoystickConfig(
                    mode: JoystickMode.dualAxisDigital4,
                  ),
                  label: 'Joystick',
                  activeColor: Colors.orange,
                  activeColorLight: Colors.orangeAccent,
                  enabled: true,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      final crossGate = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_CrossGatePainter',
      );
      expect(crossGate, findsOneWidget);
      return tester.getSize(crossGate);
    }

    final compactSize = await pumpCrossGate(220);
    final expandedSize = await pumpCrossGate(420);

    expect(compactSize, const Size.square(200));
    expect(expandedSize, const Size.square(400));
    expect(expandedSize.width, greaterThan(compactSize.width));
  });

  testWidgets('dual-axis analog joystick shows live X and Y values', (
    tester,
  ) async {
    final outputs = <JoystickOutput>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 220,
              child: IndustrialJoystickControl(
                config: const JoystickConfig(mode: JoystickMode.dualAxisAnalog),
                label: 'Joystick',
                activeColor: Colors.orange,
                activeColorLight: Colors.orangeAccent,
                enabled: true,
                onChanged: outputs.add,
              ),
            ),
          ),
        ),
      ),
    );

    expect(_axisValue(tester, 'x'), '0.00');
    expect(_axisValue(tester, 'y'), '0.00');

    final joystick = find.byType(IndustrialJoystickControl);
    final gesture = await tester.startGesture(tester.getCenter(joystick));
    await gesture.moveBy(const Offset(36, -36));
    await tester.pump();

    expect(outputs, isNotEmpty);
    expect(outputs.last.x, greaterThan(0));
    expect(outputs.last.y, greaterThan(0));
    expect(_axisValue(tester, 'x'), startsWith('+'));
    expect(_axisValue(tester, 'y'), startsWith('+'));
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('analog-joystick-x-direction')),
          )
          .icon,
      Icons.arrow_forward_rounded,
    );
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('analog-joystick-y-direction')),
          )
          .icon,
      Icons.arrow_upward_rounded,
    );

    await gesture.cancel();
  });

  testWidgets('single-axis analog joystick shows its live axis value', (
    tester,
  ) async {
    Future<List<JoystickOutput>> pumpAxis(JoystickAxis axis) async {
      final outputs = <JoystickOutput>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: axis == JoystickAxis.horizontal ? 240 : 120,
                height: axis == JoystickAxis.horizontal ? 120 : 240,
                child: IndustrialJoystickControl(
                  key: ValueKey(axis),
                  config: JoystickConfig(
                    mode: JoystickMode.singleAxisAnalog,
                    axis: axis,
                  ),
                  label: 'Joystick',
                  activeColor: Colors.orange,
                  activeColorLight: Colors.orangeAccent,
                  enabled: true,
                  onChanged: outputs.add,
                ),
              ),
            ),
          ),
        ),
      );
      return outputs;
    }

    var outputs = await pumpAxis(JoystickAxis.vertical);
    expect(_axisValue(tester, 'y'), '0.00');
    var joystick = find.byType(IndustrialJoystickControl);
    var gesture = await tester.startGesture(tester.getCenter(joystick));
    await gesture.moveBy(const Offset(0, -48));
    await tester.pump();

    expect(outputs.last.x, 0);
    expect(outputs.last.y, greaterThan(0));
    expect(_axisValue(tester, 'y'), startsWith('+'));
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('analog-joystick-y-direction')),
          )
          .icon,
      Icons.arrow_upward_rounded,
    );
    await gesture.cancel();
    await tester.pump();

    outputs = await pumpAxis(JoystickAxis.horizontal);
    expect(_axisValue(tester, 'x'), '0.00');
    joystick = find.byType(IndustrialJoystickControl);
    gesture = await tester.startGesture(tester.getCenter(joystick));
    await gesture.moveBy(const Offset(48, 0));
    await tester.pump();

    expect(outputs.last.x, greaterThan(0));
    expect(outputs.last.y, 0);
    expect(_axisValue(tester, 'x'), startsWith('+'));
    expect(
      tester
          .widget<Icon>(
            find.byKey(const ValueKey('analog-joystick-x-direction')),
          )
          .icon,
      Icons.arrow_forward_rounded,
    );
    await gesture.cancel();
  });
}

String _axisValue(WidgetTester tester, String axis) {
  return tester
      .widget<Text>(find.byKey(ValueKey('analog-joystick-$axis-value')))
      .data!;
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
