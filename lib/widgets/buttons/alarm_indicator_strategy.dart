import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/widgets/buttons/alarm_indicator_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlarmIndicatorStrategy
//
// PLC STATUS-DRIVEN FEEDBACK strategy — never sends a PLC output ([onCommand]
// is unused here). Reads the live composed PlcOutputCommand via
// CraneController.isFieldActive and evaluates AlarmIndicatorConfig's three
// PlcConditionConfigs (critical/alarm/warning, each an "any of" or "all of"
// selected PlcMapping variants) most-severe first, exactly mirroring how
// live_led_row.dart's control screens already read PLC status for LEDs.
//
// Acknowledge is handled entirely inside AlarmIndicatorControl as LOCAL,
// UI-only state — it never reaches onCommand, so this widget can never send
// a PLC output "unless explicitly designed later," per the safety
// requirement.
// ─────────────────────────────────────────────────────────────────────────────

class AlarmIndicatorStrategy extends ButtonTypeStrategy {
  const AlarmIndicatorStrategy();

  @override
  ButtonType get type => ButtonType.alarmIndicator;

  static AlarmSeverity severityFor(
    AlarmIndicatorConfig config,
    bool Function(PlcMapping) isFieldActive,
  ) {
    if (config.criticalTrigger.isActive(isFieldActive)) {
      return AlarmSeverity.critical;
    }
    if (config.alarmTrigger.isActive(isFieldActive)) {
      return AlarmSeverity.alarm;
    }
    if (config.warningTrigger.isActive(isFieldActive)) {
      return AlarmSeverity.warning;
    }
    return AlarmSeverity.normal;
  }

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
    final craneController = context.watch<CraneController>();
    final isCustomizing = context
        .watch<CustomizationModeController>()
        .isActive;
    // Customization Mode never escalates/animates, even if the underlying
    // live PLC condition happens to be true — editing a layout must not
    // visually alarm the operator over a preview tile.
    final severity = isCustomizing
        ? AlarmSeverity.normal
        : severityFor(alarmConfig, craneController.isFieldActive);

    return AlarmIndicatorControl(
      label: config.label,
      rawSeverity: severity,
      enabled: !isDisabled,
      config: alarmConfig,
    );
  }
}
