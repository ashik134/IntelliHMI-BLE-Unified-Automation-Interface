import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/widgets/gauges/radial_gauge_indicator.dart';

void main() {
  testWidgets('industrial radial gauge renders with configured ranges', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox.square(
              dimension: 260,
              child: IndustrialRadialGaugeIndicator(
                label: 'Load Weight',
                minValue: 0,
                maxValue: 100,
                value: 62,
                unit: 'kg',
                majorTickInterval: 20,
                minorTicksPerMajor: 4,
                ranges: [
                  RadialGaugeRange.normal(startValue: 0, endValue: 70),
                  RadialGaugeRange.warning(startValue: 70, endValue: 85),
                  RadialGaugeRange.danger(startValue: 85, endValue: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(IndustrialRadialGaugeIndicator), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(IndustrialRadialGaugeIndicator),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('industrial radial gauge animates value updates cleanly', (
    WidgetTester tester,
  ) async {
    Widget buildGauge(double value) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox.square(
            dimension: 220,
            child: IndustrialRadialGaugeIndicator(
              label: 'Pressure',
              minValue: 0,
              maxValue: 10,
              value: value,
              unit: 'bar',
              majorTickInterval: 2,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildGauge(2));
    await tester.pump();
    await tester.pumpWidget(buildGauge(8));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(IndustrialRadialGaugeIndicator), findsOneWidget);
  });
}
