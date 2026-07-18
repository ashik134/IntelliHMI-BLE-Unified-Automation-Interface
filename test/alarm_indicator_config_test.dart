import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/alarm_indicator_strategy.dart';

void main() {
  test('alarm indicator config round-trips through JSON with defaults', () {
    const config = AlarmIndicatorConfig(
      warningTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
      alarmTrigger: PlcConditionConfig(watchedFields: {PlcMapping.down}),
      criticalTrigger: PlcConditionConfig(
        watchedFields: {PlcMapping.left, PlcMapping.right},
        combinator: PlcConditionCombinator.all,
      ),
      acknowledgeEnabled: true,
      showStatusText: false,
      showTimestamp: true,
    );

    final restored = AlarmIndicatorConfig.fromJson(config.toJson());

    expect(restored, config);
    expect(
      AlarmIndicatorConfig.fromJson(const {}).acknowledgeEnabled,
      false,
    );
    expect(AlarmIndicatorConfig.fromJson(const {}).showStatusText, true);
    expect(
      AlarmIndicatorConfig.fromJson(const {}).warningTrigger.hasCondition,
      false,
    );
  });

  test('ButtonConfig persists alarm indicator custom properties', () {
    const alarm = AlarmIndicatorConfig(
      criticalTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
      acknowledgeEnabled: true,
      showTimestamp: true,
    );
    final config = ButtonConfig(
      id: 'custom_alarm',
      type: ButtonType.alarmIndicator,
      plcMapping: PlcMapping.up,
      label: 'Hoist Alarm',
      customProperties: alarm.applyToCustomProperties(const {}),
    );

    final restored = ButtonConfig.fromJson(config.toJson());
    final restoredAlarm = AlarmIndicatorConfig.fromCustomProperties(
      restored.customProperties,
    );

    expect(restored.type, ButtonType.alarmIndicator);
    expect(restoredAlarm.acknowledgeEnabled, true);
    expect(restoredAlarm.showTimestamp, true);
    expect(restoredAlarm.criticalTrigger.watchedFields, {PlcMapping.up});
  });

  test('alarm indicator never composes a stateMappings-backed output command', () {
    const layout = ControlLayoutConfig(
      buttons: {
        'custom_alarm': ButtonConfig(
          id: 'custom_alarm',
          type: ButtonType.alarmIndicator,
          plcMapping: PlcMapping.up,
          label: 'Hoist Alarm',
        ),
      },
    );

    final resolved = resolveButtonCommand(
      buttonId: 'custom_alarm',
      state: ControlState.fast,
      layoutCfg: layout,
    );

    expect(resolved.stateId, 'idle');
    expect(resolved.activeVariants, isEmpty);
  });

  group('AlarmIndicatorStrategy.severityFor', () {
    test('reads Normal when no field is on', () {
      const config = AlarmIndicatorConfig(
        warningTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
      );
      final severity = AlarmIndicatorStrategy.severityFor(
        config,
        (_) => false,
      );
      expect(severity, AlarmSeverity.normal);
    });

    test('reads Warning when only the warning condition is true', () {
      const config = AlarmIndicatorConfig(
        warningTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
      );
      final severity = AlarmIndicatorStrategy.severityFor(
        config,
        (m) => m == PlcMapping.up,
      );
      expect(severity, AlarmSeverity.warning);
    });

    test('Critical wins over Alarm and Warning when all three are true', () {
      const config = AlarmIndicatorConfig(
        warningTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
        alarmTrigger: PlcConditionConfig(watchedFields: {PlcMapping.down}),
        criticalTrigger: PlcConditionConfig(watchedFields: {PlcMapping.left}),
      );
      final severity = AlarmIndicatorStrategy.severityFor(
        config,
        (_) => true,
      );
      expect(severity, AlarmSeverity.critical);
    });

    test('Alarm wins over Warning when both are true but Critical is not', () {
      const config = AlarmIndicatorConfig(
        warningTrigger: PlcConditionConfig(watchedFields: {PlcMapping.up}),
        alarmTrigger: PlcConditionConfig(watchedFields: {PlcMapping.down}),
        criticalTrigger: PlcConditionConfig(watchedFields: {PlcMapping.left}),
      );
      final severity = AlarmIndicatorStrategy.severityFor(
        config,
        (m) => m == PlcMapping.up || m == PlcMapping.down,
      );
      expect(severity, AlarmSeverity.alarm);
    });
  });
}
