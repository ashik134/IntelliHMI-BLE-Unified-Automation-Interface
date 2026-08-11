import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/horn_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HornButtonStrategy
//
// PLC STATUS-DRIVEN FEEDBACK strategy — the horn/buzzer is never an output
// control. It reads CONFIRMED PLC readback via
// CraneController.isReportedFieldActive (see crane_controllers.dart) and
// evaluates HornConfig.trigger (a PlcConditionConfig over one or more
// PlcOutputVariant variants, e.g. "A2 ON" or "A5 AND A6 ON") to decide whether
// to sound. [onCommand]/[activeState] are UNUSED here — this strategy never
// calls onCommand, matching "Buzzer must not send PLC output commands."
//
// Readback, NOT isFieldActive: the latter also carries the optimistic echo of
// an outgoing command, which would let merely sending a command sound the
// buzzer. Same rule the output LEDs' inner core follows, and the same source
// CompactPlcStatusBuzzer already uses for the AppBar buzzer, so the in-canvas
// and AppBar buzzers can no longer disagree.
// ─────────────────────────────────────────────────────────────────────────────

class HornButtonStrategy extends ButtonTypeStrategy {
  const HornButtonStrategy();

  @override
  ButtonType get type => ButtonType.horn;

  @override
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
    ButtonStateIdCommandCallback? onStateIdCommand,
    AnalogButtonCommandCallback? onAnalogCommand,
  }) {
    final role = config.role;
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.fastColor, AppColors.fastColorLight);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon = config.icon ?? Icons.campaign_rounded;
    final hornConfig = HornConfig.fromCustomProperties(config.customProperties);

    final craneController = context.watch<CraneController>();

    final conditionTrue = hornConfig.trigger.isActive(
      craneController.isReportedFieldActive,
    );
    final isActive = conditionTrue && !isDisabled;

    return IndustrialHornControl(
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      isActive: isActive,
      enabled: !isDisabled,
      config: hornConfig,
      rotation: config.effectiveRotation,
    );
  }
}
