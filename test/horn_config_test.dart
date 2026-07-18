import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  test('horn config round-trips through JSON with defaults', () {
    const config = HornConfig(
      trigger: PlcConditionConfig(
        watchedFields: {PlcMapping.left, PlcMapping.right},
        combinator: PlcConditionCombinator.all,
      ),
      soundPattern: HornSoundPattern.pulsing,
      soundEnabled: false,
      hapticFeedback: false,
      visualPulseEnabled: false,
      priority: AlarmPriority.high,
    );

    final restored = HornConfig.fromJson(config.toJson());

    expect(restored, config);
    expect(HornConfig.fromJson(const {}).soundPattern, HornSoundPattern.steady);
    expect(HornConfig.fromJson(const {}).hapticFeedback, true);
    expect(HornConfig.fromJson(const {}).trigger.hasCondition, false);
  });

  test('ButtonConfig persists horn custom properties', () {
    const horn = HornConfig(
      trigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
      soundPattern: HornSoundPattern.doubleBeep,
    );
    final config = ButtonConfig(
      id: 'custom_horn',
      type: ButtonType.horn,
      plcMapping: PlcMapping.up,
      label: 'Horn',
      customProperties: horn.applyToCustomProperties(const {}),
    );

    final restored = ButtonConfig.fromJson(config.toJson());
    final restoredHorn = HornConfig.fromCustomProperties(
      restored.customProperties,
    );

    expect(restored.type, ButtonType.horn);
    expect(restoredHorn.soundPattern, HornSoundPattern.doubleBeep);
    expect(restoredHorn.trigger.watchedFields, {PlcMapping.up});
  });

  test('horn never composes a stateMappings-backed output command', () {
    const layout = ControlLayoutConfig(
      buttons: {
        'custom_horn': ButtonConfig(
          id: 'custom_horn',
          type: ButtonType.horn,
          plcMapping: PlcMapping.up,
          label: 'Horn',
        ),
      },
    );

    final resolved = resolveButtonCommand(
      buttonId: 'custom_horn',
      state: ControlState.fast,
      layoutCfg: layout,
    );

    expect(resolved.stateId, 'idle');
    expect(resolved.activeVariants, isEmpty);
  });

  group('PlcConditionConfig.isActive', () {
    bool onlyUpIsOn(PlcMapping m) => m == PlcMapping.up;

    test('empty watchedFields is never active', () {
      const condition = PlcConditionConfig();
      expect(condition.isActive(onlyUpIsOn), false);
    });

    test('"any" combinator matches if at least one watched field is on', () {
      const condition = PlcConditionConfig(
        watchedFields: {PlcMapping.up, PlcMapping.down},
        combinator: PlcConditionCombinator.any,
      );
      expect(condition.isActive(onlyUpIsOn), true);
    });

    test('"all" combinator requires every watched field to be on', () {
      const condition = PlcConditionConfig(
        watchedFields: {PlcMapping.up, PlcMapping.down},
        combinator: PlcConditionCombinator.all,
      );
      expect(condition.isActive(onlyUpIsOn), false);
    });

    test('"all" combinator matches when every watched field is on', () {
      bool upAndDown(PlcMapping m) =>
          m == PlcMapping.up || m == PlcMapping.down;
      const condition = PlcConditionConfig(
        watchedFields: {PlcMapping.up, PlcMapping.down},
        combinator: PlcConditionCombinator.all,
      );
      expect(condition.isActive(upAndDown), true);
    });

    test('estop is stripped out by normalized()/copyWith()', () {
      final condition = const PlcConditionConfig().copyWith(
        watchedFields: {PlcMapping.estop, PlcMapping.up},
      );
      expect(condition.watchedFields, {PlcMapping.up});
    });
  });
}
