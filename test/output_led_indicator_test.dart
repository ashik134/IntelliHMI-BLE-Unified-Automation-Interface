// Behavior guard for the PLC output LED indicators, which draw commanded
// state and confirmed PLC readback as two independent things:
//   - the inner core shows a settled state only; it stays dark while command
//     and PLC echo disagree
//   - the outer ring moves on the command, and blinks amber while the two
//     disagree
//   - a channel no control in the layout maps draws a dashed grey ring
//   - CraneController keeps the two sources genuinely separate, in both
//     directions (a command never writes readback, readback never writes the
//     commanded state)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';

LedSpec _spec({
  String label = 'DF2',
  required bool commanded,
  required bool confirmed,
  bool mapped = true,
  Color color = AppColors.accent,
  Color? inactiveColor,
  bool pulseWhenInactive = false,
}) => LedSpec(
  label: label,
  commanded: commanded,
  confirmed: confirmed,
  mapped: mapped,
  color: color,
  inactiveColor: inactiveColor,
  pulseWhenInactive: pulseWhenInactive,
);

Future<void> _pumpRow(WidgetTester tester, List<LedSpec> leds) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: LiveLedRow(leds: leds)),
      ),
    ),
  );
  // Never pumpAndSettle: the pending ring blinks forever by design.
  await tester.pump(const Duration(milliseconds: 350));
}

LedRingPainter _ring(WidgetTester tester, String label) =>
    tester.widget<CustomPaint>(find.byKey(ValueKey('led-ring-$label'))).painter
        as LedRingPainter;

Color? _coreColor(WidgetTester tester, String label) {
  final core = tester.widget<Container>(
    find.byKey(ValueKey('led-core-$label')),
  );
  return (core.decoration as BoxDecoration).color;
}

ButtonConfig _buttonWithMappings(
  String id,
  Map<String, Set<PlcOutputVariant>> states, {
  Map<String, Map<String, Set<PlcOutputVariant>>> joystickSubButtons = const {},
}) => ButtonConfig(
  id: id,
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  stateMappings: {
    for (final entry in states.entries)
      entry.key: ButtonStateOutputMapping(
        stateId: entry.key,
        activeVariants: entry.value,
      ),
  },
  joystickSubButtonMappings: {
    for (final sub in joystickSubButtons.entries)
      sub.key: {
        for (final entry in sub.value.entries)
          entry.key: ButtonStateOutputMapping(
            stateId: entry.key,
            activeVariants: entry.value,
          ),
      },
  },
);

void main() {
  group('LedSpec.indicatorState', () {
    test('agreement between commanded and confirmed is a settled state', () {
      expect(
        _spec(commanded: true, confirmed: true).indicatorState,
        LedIndicatorState.confirmedOn,
      );
      expect(
        _spec(commanded: false, confirmed: false).indicatorState,
        LedIndicatorState.confirmedOff,
      );
    });

    test('any disagreement is pending, in both directions', () {
      // Commanded on, PLC has not confirmed it yet.
      expect(
        _spec(commanded: true, confirmed: false).indicatorState,
        LedIndicatorState.pending,
      );
      // Commanded off, PLC still reports the field energised.
      expect(
        _spec(commanded: false, confirmed: true).indicatorState,
        LedIndicatorState.pending,
      );
    });

    test('unmapped outranks pending — there is nothing to command', () {
      expect(
        _spec(commanded: true, confirmed: false, mapped: false).indicatorState,
        LedIndicatorState.unmapped,
      );
      expect(
        _spec(commanded: false, confirmed: false, mapped: false).isPending,
        isFalse,
      );
    });

    test('ready pulse shows only while confirmed off', () {
      const ready = AppColors.darkSuccess;
      expect(
        _spec(
          commanded: false,
          confirmed: false,
          inactiveColor: ready,
          pulseWhenInactive: true,
        ).showsReadyPulse,
        isTrue,
      );
      expect(
        _spec(
          commanded: true,
          confirmed: false,
          inactiveColor: ready,
          pulseWhenInactive: true,
        ).showsReadyPulse,
        isFalse,
      );
      expect(
        _spec(
          commanded: false,
          confirmed: true,
          inactiveColor: ready,
          pulseWhenInactive: true,
        ).showsReadyPulse,
        isFalse,
      );
    });
  });

  group('LiveLedRow rendering', () {
    testWidgets('a commanded-but-unconfirmed channel leaves the core dark', (
      tester,
    ) async {
      await _pumpRow(tester, [_spec(commanded: true, confirmed: false)]);

      // The whole point: the app asked for DF2, so the core must NOT light.
      expect(_coreColor(tester, 'DF2'), AppColors.idleColor);
      expect(_ring(tester, 'DF2').color, isNot(AppColors.accent));
    });

    testWidgets('the pending ring blinks amber', (tester) async {
      await _pumpRow(tester, [_spec(commanded: true, confirmed: false)]);

      final first = _ring(tester, 'DF2').color;
      await tester.pump(const Duration(milliseconds: 230));
      final second = _ring(tester, 'DF2').color;

      expect(
        first,
        isNot(second),
        reason: 'the pending ring must animate, not sit on one colour',
      );
      for (final color in [first, second]) {
        expect(color.r, greaterThan(color.b), reason: 'amber, not grey/blue');
      }
      expect(_ring(tester, 'DF2').dashed, isFalse);
    });

    testWidgets('readback alone lights the core, with a matching ring', (
      tester,
    ) async {
      await _pumpRow(tester, [_spec(commanded: true, confirmed: true)]);

      expect(_coreColor(tester, 'DF2'), AppColors.accent);
      expect(_ring(tester, 'DF2').color, AppColors.accent);
      expect(_ring(tester, 'DF2').dashed, isFalse);
    });

    testWidgets('a PLC-only mismatch leaves the core dark', (tester) async {
      await _pumpRow(tester, [_spec(commanded: false, confirmed: true)]);

      expect(_coreColor(tester, 'DF2'), AppColors.idleColor);
      expect(_ring(tester, 'DF2').color, isNot(AppColors.accent));
    });

    testWidgets('E-STOP pending uses only its blinking amber ring', (
      tester,
    ) async {
      for (final state in [
        (commanded: true, confirmed: false),
        (commanded: false, confirmed: true),
      ]) {
        await _pumpRow(tester, [
          _spec(
            label: 'ESTOP',
            commanded: state.commanded,
            confirmed: state.confirmed,
            color: AppColors.eStopColor,
            inactiveColor: AppColors.darkSuccess,
            pulseWhenInactive: true,
          ),
        ]);

        expect(_coreColor(tester, 'ESTOP'), AppColors.idleColor);
        expect(_ring(tester, 'ESTOP').color, isNot(AppColors.eStopColor));
      }
    });

    testWidgets('an unmapped channel draws a dashed grey ring', (tester) async {
      await _pumpRow(tester, [
        _spec(commanded: false, confirmed: false, mapped: false),
      ]);

      final ring = _ring(tester, 'DF2');
      expect(ring.dashed, isTrue);
      expect(ring.color, AppColors.ledUnmappedGrey);
      expect(_coreColor(tester, 'DF2'), AppColors.idleColor);
    });

    testWidgets('an unmapped channel still reports PLC readback on its core', (
      tester,
    ) async {
      await _pumpRow(tester, [
        _spec(commanded: false, confirmed: true, mapped: false),
      ]);

      expect(_ring(tester, 'DF2').dashed, isTrue);
      expect(
        _coreColor(tester, 'DF2'),
        AppColors.accent,
        reason: 'the PLC can drive a field no layout control maps',
      );
    });

    testWidgets('E-STOP keeps its confirmed-clear ready glow on the core', (
      tester,
    ) async {
      await _pumpRow(tester, [
        _spec(
          label: 'ESTOP',
          commanded: false,
          confirmed: false,
          color: AppColors.eStopColor,
          inactiveColor: AppColors.darkSuccess,
          pulseWhenInactive: true,
        ),
      ]);

      final core = _coreColor(tester, 'ESTOP')!;
      expect(core, isNot(AppColors.idleColor));
      expect(core.g, greaterThan(core.r), reason: 'the safe/ready green');
    });

    testWidgets('renders one indicator per channel', (tester) async {
      await _pumpRow(tester, [
        _spec(label: 'ESTOP', commanded: false, confirmed: false),
        _spec(label: 'DF2', commanded: true, confirmed: true),
        _spec(label: 'DF3', commanded: false, confirmed: false, mapped: false),
      ]);

      expect(find.text('ESTOP'), findsOneWidget);
      expect(find.text('DF2'), findsOneWidget);
      expect(find.text('DF3'), findsOneWidget);
      expect(_ring(tester, 'DF3').dashed, isTrue);
      expect(_ring(tester, 'DF2').dashed, isFalse);
    });
  });

  group('ControlLayoutConfig.mappedOutputVariants', () {
    test('collects every variant any button state can drive', () {
      final layout = ControlLayoutConfig(
        buttons: {
          'a': _buttonWithMappings('a', {
            'idle': const <PlcOutputVariant>{},
            'active': {PlcOutputVariant.df2},
          }),
          'b': _buttonWithMappings('b', {
            'step1': {PlcOutputVariant.df3},
            'step2': {PlcOutputVariant.df3, PlcOutputVariant.df4},
          }),
        },
      );

      expect(layout.mappedOutputVariants, {
        PlcOutputVariant.df1,
        PlcOutputVariant.df2,
        PlcOutputVariant.df3,
        PlcOutputVariant.df4,
      });
    });

    test('includes joystick virtual sub-button mappings', () {
      final layout = ControlLayoutConfig(
        buttons: {
          'j': _buttonWithMappings(
            'j',
            const {},
            joystickSubButtons: {
              'j::up': {
                'step1': {PlcOutputVariant.df5},
              },
              'j::down': {
                'step1': {PlcOutputVariant.df6},
              },
            },
          ),
        },
      );

      expect(
        layout.mappedOutputVariants,
        containsAll(<PlcOutputVariant>[
          PlcOutputVariant.df5,
          PlcOutputVariant.df6,
        ]),
      );
    });

    test('always reports DF1 mapped — E-STOP is controller-owned', () {
      final layout = ControlLayoutConfig(
        buttons: {'a': _buttonWithMappings('a', const {})},
      );

      expect(layout.mappedOutputVariants, {PlcOutputVariant.df1});
      expect(
        layout.mappedOutputVariants.contains(PlcOutputVariant.df7),
        isFalse,
      );
    });
  });

  group('CraneController commanded vs confirmed', () {
    test('PLC readback never rewrites what the app commanded', () {
      final controller = CraneController();
      addTearDown(controller.dispose);

      controller.handlePlcStatusForTesting(
        PlcOutputCommand.compose({PlcOutputVariant.df2}),
      );

      expect(controller.isConfirmedFieldActive(PlcOutputVariant.df2), isTrue);
      expect(
        controller.isCommandedFieldActive(PlcOutputVariant.df2),
        isFalse,
        reason: 'the app never asked for DF2',
      );
    });

    test('sending a command never moves the confirmed state', () async {
      final controller = CraneController();
      addTearDown(controller.dispose);

      // Readback says everything is clear.
      controller.handlePlcStatusForTesting(PlcOutputCommand.idle());
      await controller.triggerEStop();

      expect(controller.isCommandedFieldActive(PlcOutputVariant.df1), isTrue);
      expect(
        controller.isConfirmedFieldActive(PlcOutputVariant.df1),
        isFalse,
        reason: 'only a readback notification may light the core',
      );

      // ...and once the PLC confirms, the two agree.
      controller.handlePlcStatusForTesting(PlcOutputCommand.emergencyStop());
      expect(controller.isConfirmedFieldActive(PlcOutputVariant.df1), isTrue);
      expect(controller.isCommandedFieldActive(PlcOutputVariant.df1), isTrue);
    });

    test('a latched E-STOP clears every other commanded channel', () async {
      final controller = CraneController();
      addTearDown(controller.dispose);

      await controller.triggerEStop();

      for (final variant in PlcOutputVariant.values.skip(1)) {
        expect(
          controller.isCommandedFieldActive(variant),
          isFalse,
          reason: '${variant.storageKey} must not stay commanded under E-STOP',
        );
      }
    });
  });
}
