import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/potentiometer_control.dart';

void main() {
  testWidgets('touching the track does not jump the value', (tester) async {
    final values = <double>[];

    await _pumpPotentiometer(
      tester,
      config: const PotentiometerConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
        defaultValue: 25,
      ),
      onChanged: values.add,
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(62, 62));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isEmpty);
  });

  testWidgets('dragging applies angle delta from the starting value', (
    tester,
  ) async {
    final values = <double>[];

    await _pumpPotentiometer(
      tester,
      config: const PotentiometerConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
        defaultValue: 25,
      ),
      onChanged: values.add,
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(0, -70));
    await gesture.moveTo(center + const Offset(50, -50));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isNotEmpty);
    expect(values.last, greaterThan(25));
    expect(values.last, lessThan(60));
  });

  testWidgets('dragging below minimum clamps instead of wrapping', (
    tester,
  ) async {
    final values = <double>[];

    await _pumpPotentiometer(
      tester,
      config: const PotentiometerConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
        defaultValue: 0,
      ),
      onChanged: values.add,
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(50, -50));
    await gesture.moveTo(center + const Offset(0, -70));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isEmpty);
  });

  testWidgets('dragging above maximum clamps instead of wrapping', (
    tester,
  ) async {
    final values = <double>[];

    await _pumpPotentiometer(
      tester,
      config: const PotentiometerConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
        defaultValue: 100,
      ),
      onChanged: values.add,
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(0, -70));
    await gesture.moveTo(center + const Offset(50, -50));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isEmpty);
  });

  testWidgets('dragging outside the knob grip does not emit values', (
    tester,
  ) async {
    final values = <double>[];

    await _pumpPotentiometer(
      tester,
      config: const PotentiometerConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
        defaultValue: 100,
      ),
      onChanged: values.add,
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(95, 0));
    await gesture.moveTo(center + const Offset(70, -60));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(values, isEmpty);
  });

  testWidgets('disabled potentiometer does not emit values', (tester) async {
    final values = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              height: 200,
              child: IndustrialPotentiometerControl(
                config: const PotentiometerConfig(),
                label: 'Speed',
                activeColor: Colors.blue,
                activeColorLight: Colors.lightBlueAccent,
                enabled: false,
                onChanged: values.add,
              ),
            ),
          ),
        ),
      ),
    );

    final finder = find.byType(IndustrialPotentiometerControl);
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center + const Offset(-62, 62));
    await gesture.moveTo(center + const Offset(62, 62));
    await tester.pump();
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));

    expect(values, isEmpty);
  });
}

Future<void> _pumpPotentiometer(
  WidgetTester tester, {
  required PotentiometerConfig config,
  required ValueChanged<double> onChanged,
  bool enabled = true,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: IndustrialPotentiometerControl(
              config: config,
              label: 'Speed',
              activeColor: Colors.blue,
              activeColorLight: Colors.lightBlueAccent,
              enabled: enabled,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    ),
  );
}
