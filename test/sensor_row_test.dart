import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/gauges/radial_gauge_indicator.dart';

void main() {
  testWidgets('sensor row shows radial gauge and sensor values', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 360, child: SensorRow(a1: 62, a2: 48)),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(IndustrialRadialGaugeIndicator), findsOneWidget);
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('A2'), findsOneWidget);
    expect(find.text('62'), findsOneWidget);
    expect(find.text('48'), findsOneWidget);
  });
}
