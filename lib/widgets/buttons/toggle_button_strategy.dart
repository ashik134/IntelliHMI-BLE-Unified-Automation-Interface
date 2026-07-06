import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';
import 'package:rev_crane_control_ops/widgets/buttons/toggle_switch_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleButtonStrategy
//
// Wraps ToggleSwitchButton (reused verbatim, zero changes).
// ─────────────────────────────────────────────────────────────────────────────

class ToggleButtonStrategy extends ButtonTypeStrategy {
  const ToggleButtonStrategy();

  @override
  ButtonType get type => ButtonType.toggle;

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
        : (Colors.blueGrey, Colors.blueGrey.shade200);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);

    return ToggleSwitchButton(
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      isActive: activeState != ControlState.idle,
      isDisabled: isDisabled,
      isSpringReturn: config.behavior.isSpringReturn,
      style: config.style,
      onCommandChanged: (state) => onCommand(config.id, state),
    );
  }
}
