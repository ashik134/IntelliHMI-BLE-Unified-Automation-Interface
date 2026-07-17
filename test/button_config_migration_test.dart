// Regression guard for the migration step: proves that
// ButtonConfig.migratedStateMappingsFor / .migratedJoystickSubButtonMappingsFor
// / .fromLegacyAxis reproduce, as static baked data, EXACTLY what the OLD
// ControlRole/AxisKind-derived composition would have produced for every
// reachable state — own field for the slow-equivalent state, own field +
// axis fast field for the fast-equivalent state, {} for idle — so that after
// migration the composer needs zero live derivation to behave identically to
// before.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';

/// Mirrors the OLD (pre-refactor) _fieldsFor derivation exactly, for a real
/// ControlRole button: own field for slow, own field + axis fast field for
/// fast, {} for idle. This is the ground truth migration must reproduce.
Set<PlcMapping> oldFieldsFor(ControlRole role, {required bool isFast}) {
  final own = role.plcMapping!;
  if (!isFast) return {own};
  final fast = role.axis?.fastMapping;
  return {own, ?fast};
}

void main() {
  group('migratedStateMappingsFor — pushButton', () {
    for (final role in [
      ControlRole.hoistUp,
      ControlRole.hoistDown,
      ControlRole.traverseLeft,
      ControlRole.traverseRight,
      ControlRole.travelForward,
      ControlRole.travelReverse,
    ]) {
      test('${role.name}: idle -> {}, active -> old slow-equivalent set', () {
        final mappings = ButtonConfig.migratedStateMappingsFor(
          role: role,
          type: ButtonType.pushButton,
        );
        expect(mappings['idle']!.activeVariants, isEmpty);
        expect(
          mappings['active']!.activeVariants,
          oldFieldsFor(role, isFast: false),
        );
      });
    }
  });

  group('migratedStateMappingsFor — sliderButton', () {
    for (final role in [
      ControlRole.hoistUp,
      ControlRole.hoistDown,
      ControlRole.traverseLeft,
      ControlRole.traverseRight,
      ControlRole.travelForward,
      ControlRole.travelReverse,
    ]) {
      test(
        '${role.name}: idle -> {}, step1 -> old slow set, '
        'step2 -> old fast set (own field + axis fast field)',
        () {
          final mappings = ButtonConfig.migratedStateMappingsFor(
            role: role,
            type: ButtonType.sliderButton,
          );
          expect(mappings['idle']!.activeVariants, isEmpty);
          expect(
            mappings['step1']!.activeVariants,
            oldFieldsFor(role, isFast: false),
          );
          expect(
            mappings['step2']!.activeVariants,
            oldFieldsFor(role, isFast: true),
          );
        },
      );
    }
  });

  group('migratedStateMappingsFor — toggle', () {
    for (final role in [
      ControlRole.hoistUp,
      ControlRole.traverseLeft,
      ControlRole.travelForward,
    ]) {
      test('${role.name}: center -> {}, left -> old slow set, '
          'right -> old fast set', () {
        final mappings = ButtonConfig.migratedStateMappingsFor(
          role: role,
          type: ButtonType.toggle,
        );
        expect(mappings['center']!.activeVariants, isEmpty);
        expect(
          mappings['left']!.activeVariants,
          oldFieldsFor(role, isFast: false),
        );
        expect(
          mappings['right']!.activeVariants,
          oldFieldsFor(role, isFast: true),
        );
      });
    }
  });

  group('migratedStateMappingsFor — crossTravel (5-zone)', () {
    test(
      'traverseLeft: zone1 -> old fast set, zone2 -> old slow set, '
      'center -> {}, zone4/zone5 -> {} (belong to sibling config)',
      () {
        final mappings = ButtonConfig.migratedStateMappingsFor(
          role: ControlRole.traverseLeft,
          type: ButtonType.crossTravel,
        );
        expect(
          mappings['zone1']!.activeVariants,
          oldFieldsFor(ControlRole.traverseLeft, isFast: true),
        );
        expect(
          mappings['zone2']!.activeVariants,
          oldFieldsFor(ControlRole.traverseLeft, isFast: false),
        );
        expect(mappings['center']!.activeVariants, isEmpty);
        expect(mappings['zone4']!.activeVariants, isEmpty);
        expect(mappings['zone5']!.activeVariants, isEmpty);
      },
    );

    test(
      'traverseRight: zone4 -> old slow set, zone5 -> old fast set, '
      'center -> {}, zone1/zone2 -> {} (belong to sibling config)',
      () {
        final mappings = ButtonConfig.migratedStateMappingsFor(
          role: ControlRole.traverseRight,
          type: ButtonType.crossTravel,
        );
        expect(mappings['zone1']!.activeVariants, isEmpty);
        expect(mappings['zone2']!.activeVariants, isEmpty);
        expect(mappings['center']!.activeVariants, isEmpty);
        expect(
          mappings['zone4']!.activeVariants,
          oldFieldsFor(ControlRole.traverseRight, isFast: false),
        );
        expect(
          mappings['zone5']!.activeVariants,
          oldFieldsFor(ControlRole.traverseRight, isFast: true),
        );
      },
    );

    test(
      'the union of traverseLeft + traverseRight zone1/zone2/zone4/zone5 '
      'exactly reproduces the old field-sets, and the two buttons\' fields '
      'never overlap with each other (left-side fields vs right-side fields)',
      () {
        final left = ButtonConfig.migratedStateMappingsFor(
          role: ControlRole.traverseLeft,
          type: ButtonType.crossTravel,
        );
        final right = ButtonConfig.migratedStateMappingsFor(
          role: ControlRole.traverseRight,
          type: ButtonType.crossTravel,
        );
        final zone1 = left['zone1']!.activeVariants;
        final zone2 = left['zone2']!.activeVariants;
        final zone4 = right['zone4']!.activeVariants;
        final zone5 = right['zone5']!.activeVariants;

        expect(zone1, {PlcMapping.left, PlcMapping.fastLr});
        expect(zone2, {PlcMapping.left});
        expect(zone4, {PlcMapping.right});
        expect(zone5, {PlcMapping.right, PlcMapping.fastLr});

        // Cross-button isolation: no left-side zone ever contains `right`,
        // and no right-side zone ever contains `left` — the two buttons'
        // direction bits never leak into each other, even though each
        // button's OWN fast/slow zones legitimately share their own field.
        for (final leftZone in [zone1, zone2]) {
          expect(leftZone.contains(PlcMapping.right), isFalse);
        }
        for (final rightZone in [zone4, zone5]) {
          expect(rightZone.contains(PlcMapping.left), isFalse);
        }
      },
    );
  });

  group('estop / resetEstop — never state-mapped', () {
    test('ButtonConfig.estopDefault() has empty stateMappings', () {
      expect(ButtonConfig.estopDefault().stateMappings, isEmpty);
    });

    test('ButtonConfig.resetEstopDefault(label) has empty stateMappings', () {
      expect(
        ButtonConfig.resetEstopDefault('RESET').stateMappings,
        isEmpty,
      );
    });
  });

  group('ButtonConfig.fromLegacyAxis wires migratedStateMappingsFor in', () {
    test('a pushButton-widgetType hoistUp axis migrates correctly', () {
      final config = ButtonConfig.fromLegacyAxis(
        role: ControlRole.hoistUp,
        axisConfig: const AxisControlConfig(
          widgetType: ControlWidgetType.pushButton,
        ),
        style: const ButtonStyleConfig(),
        label: 'UP',
      );
      expect(config.stateMappings['idle']!.activeVariants, isEmpty);
      expect(
        config.stateMappings['active']!.activeVariants,
        oldFieldsFor(ControlRole.hoistUp, isFast: false),
      );
    });

    test(
      'a sliderButton-widgetType traverse axis migrates to crossTravel '
      'type with correctly-populated zone states',
      () {
        final config = ButtonConfig.fromLegacyAxis(
          role: ControlRole.traverseLeft,
          axisConfig: const AxisControlConfig(
            widgetType: ControlWidgetType.sliderButton,
          ),
          style: const ButtonStyleConfig(),
          label: 'LEFT',
        );
        expect(config.type, ButtonType.crossTravel);
        expect(
          config.stateMappings['zone1']!.activeVariants,
          oldFieldsFor(ControlRole.traverseLeft, isFast: true),
        );
      },
    );

    test('a joystick-widgetType hoist axis migrates joystickSubButtonMappings '
        'with the old own-field/own-field+fast-field derivation', () {
      final config = ButtonConfig.fromLegacyAxis(
        role: ControlRole.hoistUp,
        axisConfig: const AxisControlConfig(
          widgetType: ControlWidgetType.joystick,
        ),
        style: const ButtonStyleConfig(),
        label: 'HOIST',
      );
      expect(config.type, ButtonType.joystick);
      expect(config.joystickSubButtonMappings, isNotEmpty);
      final upSubId = joystickVirtualButtonId(
        ControlRole.hoistUp.name,
        PlcMapping.up,
      );
      final downSubId = joystickVirtualButtonId(
        ControlRole.hoistUp.name,
        PlcMapping.down,
      );
      final upSub = config.joystickSubButtonMappings[upSubId];
      final downSub = config.joystickSubButtonMappings[downSubId];
      expect(upSub, isNotNull);
      expect(downSub, isNotNull);
      expect(upSub!['idle']!.activeVariants, isEmpty);
      expect(upSub['step1']!.activeVariants, {PlcMapping.up});
      expect(upSub['step2']!.activeVariants, {PlcMapping.up, PlcMapping.fastUd});
      expect(downSub!['step1']!.activeVariants, {PlcMapping.down});
      expect(
        downSub['step2']!.activeVariants,
        {PlcMapping.down, PlcMapping.fastUd},
      );
    });
  });

  group('migratedJoystickSubButtonMappingsFor — dual-axis', () {
    test('dual-axis always drives traverse (x) + travel (y), matching '
        'JoystickButtonStrategy\'s hardcoded role pairing', () {
      final mappings = ButtonConfig.migratedJoystickSubButtonMappingsFor(
        sourceButtonId: 'my_joystick',
        role: null,
        joystickConfig: const JoystickConfig(mode: JoystickMode.dualAxisAnalog),
      );
      for (final role in [
        ControlRole.traverseRight,
        ControlRole.traverseLeft,
        ControlRole.travelForward,
        ControlRole.travelReverse,
      ]) {
        final subId = joystickVirtualButtonId(
          'my_joystick',
          role.plcMapping!,
        );
        expect(mappings[subId], isNotNull);
        expect(
          mappings[subId]!['step2']!.activeVariants,
          oldFieldsFor(role, isFast: true),
        );
      }
    });
  });

  group('fromJson migration fallback (old JSON, no stateMappings key)', () {
    test(
      'a legacy hoistUp JSON blob without stateMappings migrates on load',
      () {
        final legacyJson = ButtonConfig.fromLegacyAxis(
          role: ControlRole.hoistUp,
          axisConfig: const AxisControlConfig(
            widgetType: ControlWidgetType.sliderButton,
          ),
          style: const ButtonStyleConfig(),
          label: 'UP',
        ).toJson();
        legacyJson.remove('stateMappings');

        final restored = ButtonConfig.fromJson(legacyJson);
        expect(restored.stateMappings['idle']!.activeVariants, isEmpty);
        expect(
          restored.stateMappings['step1']!.activeVariants,
          oldFieldsFor(ControlRole.hoistUp, isFast: false),
        );
        expect(
          restored.stateMappings['step2']!.activeVariants,
          oldFieldsFor(ControlRole.hoistUp, isFast: true),
        );
      },
    );

    test(
      'a role-less (custom) button JSON without stateMappings loads with '
      'empty stateMappings — never migrated, never auto-populated',
      () {
        const custom = ButtonConfig(
          id: 'custom_1',
          type: ButtonType.pushButton,
          plcMapping: PlcMapping.up,
          label: 'Custom',
        );
        final json = custom.toJson();
        json.remove('stateMappings');
        final restored = ButtonConfig.fromJson(json);
        expect(restored.stateMappings, isEmpty);
      },
    );
  });
}
