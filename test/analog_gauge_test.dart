// Behavior guard for the analog gauge that renders the PLC's analog
// characteristic (A1/A2) on the control screen:
//   - scale mapping clamps out-of-range and degenerate ranges instead of
//     throwing or drawing past the arc
//   - the readout still reports the true reading when it is out of range
//   - zone thresholds resolve to the operating band that drives the colours
//   - the sensor strip stays inside its derived height budget on both a
//     narrow phone and a wide tablet layout

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/control_screen/analog_gauge.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';

void main() {
  group('AnalogGauge.fractionFor', () {
    test('maps a value onto 0..1 of the configured range', () {
      expect(
        AnalogGauge.fractionFor(2048, maxValue: 4096),
        closeTo(0.5, 0.0001),
      );
      expect(
        AnalogGauge.fractionFor(75, minValue: 50, maxValue: 100),
        closeTo(0.5, 0.0001),
      );
    });

    test('clamps readings outside the range', () {
      expect(AnalogGauge.fractionFor(-500), 0.0);
      expect(AnalogGauge.fractionFor(9999), 1.0);
    });

    test('degrades to zero for an empty or non-finite scale', () {
      expect(AnalogGauge.fractionFor(10, minValue: 100, maxValue: 100), 0.0);
      expect(AnalogGauge.fractionFor(10, minValue: 100, maxValue: 0), 0.0);
      expect(AnalogGauge.fractionFor(double.nan), 0.0);
    });
  });

  group('AnalogGauge.formatValue', () {
    test('rounds to whole counts on wide ranges', () {
      expect(AnalogGauge.formatValue(2047.6, span: 4095), '2048');
    });

    test('keeps one decimal on narrow engineering ranges', () {
      expect(AnalogGauge.formatValue(7.25, span: 10), '7.3');
    });
  });

  group('GaugeZone.forFraction', () {
    GaugeZone zoneOf(double fraction) => GaugeZone.forFraction(
      fraction,
      warningFraction: 0.75,
      criticalFraction: 0.9,
    );

    test('resolves each operating band, thresholds inclusive', () {
      expect(zoneOf(0.0), GaugeZone.normal);
      expect(zoneOf(0.74), GaugeZone.normal);
      expect(zoneOf(0.75), GaugeZone.warning);
      expect(zoneOf(0.89), GaugeZone.warning);
      expect(zoneOf(0.9), GaugeZone.critical);
      expect(zoneOf(1.0), GaugeZone.critical);
    });
  });

  testWidgets('gauge card shows the channel tag, label and live reading', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(
        size: Size(180, 120),
        child: AnalogGaugeCard(
          tag: 'A1',
          label: 'Load 1',
          value: 2048,
          color: Colors.green,
          colorLight: Colors.lightGreen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A1'), findsOneWidget);
    expect(find.text('LOAD 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The reading itself is painted, not a Text widget — Semantics is what
    // exposes it, so assert there.
    final semantics = tester.getSemantics(
      find.byType(AnalogGauge).first,
    );
    expect(semantics.value, '2048');
  });

  testWidgets('an over-range reading still reports its true value', (
    tester,
  ) async {
    await tester.pumpWidget(
      const _Harness(
        size: Size(180, 120),
        child: AnalogGaugeCard(
          tag: 'A2',
          label: 'Load 2',
          value: 5000,
          color: Colors.blue,
          colorLight: Colors.lightBlue,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSemantics(find.byType(AnalogGauge).first).value, '5000');
  });

  group('SensorRow.heightFor', () {
    test('shrinks the strip as the screen size class shrinks', () {
      final smallPhone = SensorRow.heightFor(screenWidth: 320, rowWidth: 296);
      final phone = SensorRow.heightFor(screenWidth: 360, rowWidth: 336);
      final largePhone = SensorRow.heightFor(screenWidth: 412, rowWidth: 388);
      final tablet = SensorRow.heightFor(screenWidth: 800, rowWidth: 776);

      expect(smallPhone, lessThan(phone));
      expect(phone, lessThan(largePhone));
      expect(largePhone, lessThan(tablet));
      expect(smallPhone, inInclusiveRange(62, 78));
      expect(tablet, inInclusiveRange(96, 128));
    });

    test('never lets the strip outgrow its band, whatever the row width', () {
      for (final rowWidth in <double>[0, 120, 336, 2000]) {
        expect(
          SensorRow.heightFor(screenWidth: 360, rowWidth: rowWidth),
          inInclusiveRange(62, 128),
        );
      }
    });

    test('a handset in landscape is still sized as a handset', () {
      // Callers pass the shortest side, so a 800x360 phone lands on the same
      // band as the same phone held upright.
      expect(
        SensorRow.heightFor(screenWidth: 360, rowWidth: 776),
        lessThan(SensorRow.heightFor(screenWidth: 800, rowWidth: 776)),
      );
    });
  });

  testWidgets('sensor strip renders both channels within its height budget', (
    tester,
  ) async {
    const cases = <Size>[Size(320, 640), Size(360, 800), Size(800, 1200)];

    for (final screen in cases) {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = screen;
      addTearDown(tester.view.reset);

      final rowWidth = screen.width - 24;
      await tester.pumpWidget(
        _Harness(
          size: Size(rowWidth, screen.height - 40),
          child: const Align(
            alignment: Alignment.topCenter,
            child: SensorRow(a1: 1200, a2: 3900),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final strip = tester.getSize(find.byType(SensorRow));
      expect(
        strip.height,
        SensorRow.heightFor(screenWidth: screen.width, rowWidth: rowWidth),
      );
      expect(strip.height, inInclusiveRange(62, 128));
    }
  });
}

class _Harness extends StatelessWidget {
  const _Harness({required this.size, required this.child});

  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );
  }
}
