import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/joystick_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

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

  group('digital cross gate responsive sizing', () {
    test('the gate fills its box instead of floating inside it', () {
      // Regression: the 3x3 cell arrangement used to be derived from the
      // plate (cell = plateR * 0.46, plateR = side * 0.48), so it occupied
      // only ~70% of the box and read as a small control adrift in a large
      // grid cell. It must now consume the full extent bar the label band.
      const box = Size(300, 300);
      final extent = digitalCrossGateExtentFor(box);

      expect(extent, greaterThan(box.height * 0.9));
      expect(extent, lessThanOrEqualTo(box.height));
      // Comfortably beyond the old 0.702 * min(w, h) geometry.
      expect(extent, greaterThan(box.height * 0.702 * 1.25));
    });

    test('the gate scales up with the assigned grid span', () {
      // 2x2 -> 3x3 -> 4x4 at a constant cell size: strictly proportional
      // growth, never clamped at some fixed visual size.
      final twoByTwo = digitalCrossGateExtentFor(const Size(300, 300));
      final threeByThree = digitalCrossGateExtentFor(const Size(450, 450));
      final fourByFour = digitalCrossGateExtentFor(const Size(600, 600));

      expect(threeByThree, greaterThan(twoByTwo * 1.4));
      expect(fourByFour, greaterThan(threeByThree * 1.3));
    });

    test('the gate stays square, bound by the shorter dimension', () {
      // A non-square footprint must never stretch the control: the gate is
      // capped by the binding dimension and simply centres on the other.
      final wide = digitalCrossGateExtentFor(const Size(640, 300));
      final tall = digitalCrossGateExtentFor(const Size(300, 640));
      final square = digitalCrossGateExtentFor(const Size(300, 300));

      expect(wide, lessThanOrEqualTo(300));
      expect(tall, lessThanOrEqualTo(300));
      // A wide box is height-bound, so it matches the square case exactly;
      // a tall box has spare height for the label band and so reaches the
      // full 300 width.
      expect(wide, square);
      expect(tall, greaterThanOrEqualTo(square));
    });

    test('the gate never exceeds the box it is given', () {
      for (final box in const [
        Size(80, 80),
        Size(120, 300),
        Size(300, 120),
        Size(1000, 1000),
      ]) {
        final extent = digitalCrossGateExtentFor(box);
        expect(extent, lessThanOrEqualTo(box.width));
        expect(extent, lessThanOrEqualTo(box.height));
        expect(extent, greaterThanOrEqualTo(0));
      }
    });
  });

  testWidgets(
    'digital cross gate paints across its whole footprint and stays '
    'centered on a non-square grid span',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 300,
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
      // The paint box spans the full footprint (less only the small slot
      // padding) rather than being pre-squared, so no height is wasted on a
      // tall span; the gate squares itself inside it.
      expect(tester.getSize(crossGate), const Size(620, 280));
      expect(
        tester.getCenter(crossGate),
        tester.getCenter(find.byType(IndustrialJoystickControl)),
      );
    },
  );

  testWidgets(
    'digital cross gate renders identically in Edit Mode chrome and Normal '
    'Mode for the same grid span',
    (tester) async {
      Widget joystick() => IndustrialJoystickControl(
        config: const JoystickConfig(mode: JoystickMode.dualAxisDigital4),
        label: 'Joystick',
        activeColor: Colors.orange,
        activeColorLight: Colors.orangeAccent,
        enabled: true,
        onChanged: (_) {},
      );
      final crossGate = find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_CrossGatePainter',
      );

      // Normal Mode: sole occupant of a tight grid cell.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 300,
                  height: 300,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: joystick(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final normalMode = tester.getSize(crossGate);

      // Edit Mode: same cell, plus StackFit.expand and the selection-frame
      // chrome ControlCanvas._OccupiedCell layers on while editing.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 300,
                  height: 300,
                  child: Stack(
                    fit: StackFit.expand,
                    clipBehavior: Clip.none,
                    children: [
                      AbsorbPointer(
                        absorbing: true,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: joystick(),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.purple),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.getSize(crossGate), normalMode);
    },
  );

  testWidgets('digital cross gate still resolves directions after resizing', (
    tester,
  ) async {
    // The knob hit target and travel radius are derived from the same
    // metrics as the painting, including the label band's upward shift of
    // the gate centre — so a drag must still engage a direction at a
    // footprint well away from the default.
    final outputs = <JoystickOutput>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 460,
              height: 380,
              child: IndustrialJoystickControl(
                config: const JoystickConfig(
                  mode: JoystickMode.dualAxisDigital4,
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

    final gate = find.byType(IndustrialJoystickControl);
    // Grab the knob at the gate's own centre, which sits above the box
    // centre by half the reserved label band.
    final gateCenter =
        tester.getCenter(gate) -
        const Offset(0, ControlButtonVisualMetrics.rowHeight / 2);
    final gesture = await tester.startGesture(gateCenter);
    await gesture.moveBy(const Offset(0, -120));
    await tester.pump();

    expect(outputs, isNotEmpty);
    expect(outputs.last.yStep, greaterThan(0));

    await gesture.cancel();
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
