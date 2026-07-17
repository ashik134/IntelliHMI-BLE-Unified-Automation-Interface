import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/horn_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HornButtonStrategy
//
// Digital horn/buzzer output. Reuses ButtonType.pushButton's exact
// idle/active logicalStates shape and ControlState plumbing (see
// logicalStateIdFor) — a real ButtonConfig.stateMappings entry drives real
// PLC output the same way a push button does. HornConfig only carries the
// cosmetic extras (sound pattern, haptic/beep toggles) IndustrialHornControl
// needs, mirroring how PotentiometerButtonStrategy layers PotentiometerConfig
// on top of the generic strategy contract.
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

    final enabled = !isDisabled;
    final isActive = activeState != ControlState.idle;
    final isSpringReturn = config.behavior.isSpringReturn;
    final latched = !isSpringReturn && isActive;

    return IndustrialHornControl(
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      isActive: (isSpringReturn ? isActive : latched) && enabled,
      enabled: enabled,
      config: hornConfig,
      isSpringReturn: isSpringReturn,
      onPressed: isSpringReturn
          ? () => onCommand(config.id, ControlState.slow)
          : () {},
      onReleased: isSpringReturn
          ? () => onCommand(config.id, ControlState.idle)
          : null,
      onChanged: isSpringReturn
          ? null
          : (value) => onCommand(
              config.id,
              value ? ControlState.slow : ControlState.idle,
            ),
    );
  }
}
