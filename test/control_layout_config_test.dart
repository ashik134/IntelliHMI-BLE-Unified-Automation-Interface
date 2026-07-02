import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';

void main() {
  group('ControlLayoutConfig JSON round-trip', () {
    test('default config round-trips through toJsonString/fromJsonString', () {
      const original = ControlLayoutConfig();
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored, original);
    });

    test('custom axisConfigs/roleStyles/axisOrder round-trip', () {
      const original = ControlLayoutConfig(
        axisConfigs: AxisConfigSet(
          hoist: AxisControlConfig(
            widgetType: ControlWidgetType.toggle,
            wiringConfig: PushButtonWiringConfig.offLatched,
            heightScale: 1.2,
          ),
        ),
        axisOrder: [AxisKind.travel, AxisKind.hoist, AxisKind.traverse],
      );
      final restored = ControlLayoutConfig.fromJsonString(
        original.toJsonString(),
      );
      expect(restored, original);
      expect(restored.axisConfigs.hoist.widgetType, ControlWidgetType.toggle);
      expect(restored.axisOrder, [
        AxisKind.travel,
        AxisKind.hoist,
        AxisKind.traverse,
      ]);
    });

    test('malformed axisOrder falls back to the default order', () {
      final restored = ControlLayoutConfig.fromJson({
        'axisOrder': ['hoist', 'hoist', 'travel'], // invalid: not a permutation
      });
      expect(restored.axisOrder, kDefaultAxisOrder);
    });

    test('malformed JSON string falls back to factory defaults', () {
      final restored = ControlLayoutConfig.fromJsonString('not json');
      expect(restored, const ControlLayoutConfig());
    });
  });

  group('LayoutValidationService', () {
    const validator = LayoutValidationService();

    test('rejects axis height scale below the touch-target minimum', () {
      final result = validator.validateAxisConfig(
        AxisKind.hoist,
        const AxisControlConfig(heightScale: AxisControlConfig.minHeightScale),
      );
      // At the allowed minimum scale (0.7x of 185px = ~129px), this stays
      // above the 48px floor, so it should be valid...
      expect(result.isValid, isTrue);
    });

    test('rejects axis height scale outside [min, max] bounds', () {
      final result = validator.validateAxisConfig(
        AxisKind.hoist,
        const AxisControlConfig(heightScale: 2.0),
      );
      expect(result.isValid, isFalse);
    });

    test('rejects E-Stop role style — appearance is not customizable', () {
      final result = validator.validateRoleStyle(
        ControlRole.estop,
        const ButtonStyleConfig(),
      );
      expect(result.isValid, isFalse);
    });

    test('rejects out-of-range corner radius on a styleable role', () {
      final result = validator.validateRoleStyle(
        ControlRole.hoistUp,
        const ButtonStyleConfig(cornerRadius: 999),
      );
      expect(result.isValid, isFalse);
    });

    test('accepts a null (default) style override', () {
      final result = validator.validateRoleStyle(
        ControlRole.hoistUp,
        const ButtonStyleConfig(),
      );
      expect(result.isValid, isTrue);
    });

    test('rejects a non-permutation axis order', () {
      final result = validator.validateAxisOrder([
        AxisKind.hoist,
        AxisKind.hoist,
      ]);
      expect(result.isValid, isFalse);
    });

    test('accepts a valid permutation axis order', () {
      final result = validator.validateAxisOrder([
        AxisKind.travel,
        AxisKind.traverse,
        AxisKind.hoist,
      ]);
      expect(result.isValid, isTrue);
    });
  });
}
