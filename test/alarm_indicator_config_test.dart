import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  test('alarm indicator config round-trips through JSON with defaults', () {
    const config = AlarmIndicatorConfig(
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
  });

  test('ButtonConfig persists alarm indicator custom properties', () {
    const alarm = AlarmIndicatorConfig(
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
  });

  test('alarm indicator resolves acknowledge output regardless of physical state', () {
    const layout = ControlLayoutConfig(
      buttons: {
        'custom_alarm': ButtonConfig(
          id: 'custom_alarm',
          type: ButtonType.alarmIndicator,
          plcMapping: PlcMapping.up,
          label: 'Hoist Alarm',
          stateMappings: {
            'acknowledge': ButtonStateOutputMapping(
              stateId: 'acknowledge',
              activeVariants: {PlcMapping.up},
            ),
          },
        ),
      },
    );

    final resolved = resolveButtonCommand(
      buttonId: 'custom_alarm',
      state: ControlState.slow,
      layoutCfg: layout,
    );

    expect(resolved.stateId, 'acknowledge');
    expect(resolved.activeVariants, {PlcMapping.up});
  });

  test('alarm indicator with no acknowledge mapping resolves to empty variants', () {
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

    expect(resolved.stateId, 'acknowledge');
    expect(resolved.activeVariants, isEmpty);
  });
}
