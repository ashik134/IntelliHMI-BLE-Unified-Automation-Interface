import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/industrial_spring_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonStrategy
//
// Wraps IndustrialSpringButton (reused verbatim, zero changes), the same way
// DirectionalPushControlButton does today — this is that adapter,
// parameterized by ButtonConfig instead of hardcoded per-role wrapper widgets.
// ─────────────────────────────────────────────────────────────────────────────

class PushButtonStrategy extends ButtonTypeStrategy {
  const PushButtonStrategy();

  @override
  ButtonType get type => ButtonType.pushButton;

  @override
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
  }) {
    final role = config.role;
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.upColor, AppColors.upColorLight);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);

    final enabled = !isDisabled;
    final isActive = activeState != ControlState.idle;
    final isSpringReturn = config.behavior.isSpringReturn;
    final latched = !isSpringReturn && isActive;

    return SizedBox.expand(
      child: IndustrialSpringButton(
        label: config.label,
        icon: icon,
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        isActive: isActive && enabled,
        isSpringReturn: isSpringReturn,
        isLatched: latched,
        enabled: enabled,
        onPressed: isSpringReturn
            ? () => onCommand(config.id, ControlState.slow)
            : null,
        onReleased: isSpringReturn
            ? () => onCommand(config.id, ControlState.idle)
            : null,
       
      ),
    );
  }
}
