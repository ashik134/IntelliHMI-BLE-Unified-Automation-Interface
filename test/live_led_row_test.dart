import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';

void main() {
  testWidgets('E-STOP LED is solid red when active', (tester) async {
    await _pumpEstopLed(tester, active: true);
    await tester.pump(const Duration(milliseconds: 300));

    final initial = _ledDecoration(tester);
    expect(initial.color, AppColors.eStopColor);
    expect(initial.boxShadow, hasLength(1));

    await tester.pump(const Duration(seconds: 1));

    final later = _ledDecoration(tester);
    expect(later.color, AppColors.eStopColor);
    expect(later.boxShadow, hasLength(1));
    expect(
      later.boxShadow!.single.blurRadius,
      initial.boxShadow!.single.blurRadius,
    );

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('E-STOP LED pulses green when inactive', (tester) async {
    await _pumpEstopLed(tester, active: false);

    final initial = _ledDecoration(tester);
    expect(initial.color, AppColors.darkSuccess.withAlpha(185));
    expect(initial.color, isNot(AppColors.eStopColor));
    expect(initial.boxShadow, hasLength(2));

    await tester.pump(const Duration(milliseconds: 500));

    final later = _ledDecoration(tester);
    expect(later.color, isNot(initial.color));
    expect(later.color, isNot(AppColors.eStopColor));
    expect(later.boxShadow, hasLength(2));
    expect(later.boxShadow!.first.color, isNot(initial.boxShadow!.first.color));

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _pumpEstopLed(WidgetTester tester, {required bool active}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: LiveLedRow(
            leds: [
              LedSpec(
                label: 'ESTOP',
                active: active,
                color: AppColors.eStopColor,
                inactiveColor: AppColors.darkSuccess,
                pulseWhenInactive: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

BoxDecoration _ledDecoration(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .singleWhere((decoration) => decoration.shape == BoxShape.circle);
}
