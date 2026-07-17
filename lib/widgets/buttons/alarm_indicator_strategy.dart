import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/alarm_indicator_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlarmIndicatorStrategy
//
// Monitor-only strategy: AlarmIndicatorControl never asserts a PLC output by
// itself. [activeState] stands in for real PLC status feedback until that
// transport exists — idle -> normal, slow -> warning, fast -> critical. Once
// a real status-feedback field is wired (mirroring how live_led_row.dart
// reads PLC status today), only this mapping needs to change; the widget and
// config are already future-ready for that swap.
//
// 'acknowledge' is the ONE state this button type can ever compose into
// stateMappings (see ButtonTypeLogicalStates), and it is only ever sent when
// AlarmIndicatorConfig.acknowledgeEnabled is explicitly turned on — the
// widget's own default keeps it view-only, matching "Do not send PLC output
// unless explicitly configured later."
// ─────────────────────────────────────────────────────────────────────────────

class AlarmIndicatorStrategy extends ButtonTypeStrategy {
  const AlarmIndicatorStrategy();

  @override
  ButtonType get type => ButtonType.alarmIndicator;

  static AlarmSeverity _severityFor(ControlState state) => switch (state) {
    ControlState.idle => AlarmSeverity.normal,
    ControlState.slow => AlarmSeverity.warning,
    ControlState.fast => AlarmSeverity.critical,
  };

  @override
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
    AnalogButtonCommandCallback? onAnalogCommand,
  }) {
    final alarmConfig = AlarmIndicatorConfig.fromCustomProperties(
      config.customProperties,
    );
    final severity = _severityFor(activeState);

    return AlarmIndicatorControl(
      label: config.label,
      severity: severity,
      enabled: !isDisabled,
      config: alarmConfig,
      onAcknowledge: alarmConfig.acknowledgeEnabled
          ? () => onCommand(config.id, ControlState.slow)
          : null,
    );
  }
}
