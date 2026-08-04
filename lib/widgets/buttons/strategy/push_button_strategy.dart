import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/push_control_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonStrategy
//
// Adapts PushControlButton's generic state-id contract (idle/pressed for
// spring-return, off/on for latching) to the ControlState contract shared by
// the other button strategies. PLC output resolution remains outside both
// layers in ButtonConfig.stateMappings.
// ─────────────────────────────────────────────────────────────────────────────

class PushButtonStrategy extends ButtonTypeStrategy {
  const PushButtonStrategy();

  @override
  ButtonType get type => ButtonType.pushButton;

  String _stateIdFor(ControlState state, bool isSpringReturn) {
    final isActive = state != ControlState.idle;
    if (isSpringReturn) {
      return isActive ? PushControlStateId.pressed : PushControlStateId.idle;
    }
    return isActive ? PushControlStateId.on : PushControlStateId.off;
  }

  ControlState _controlStateFor(String stateId) => switch (stateId) {
    PushControlStateId.pressed || PushControlStateId.on => ControlState.level1,
    _ => ControlState.idle,
  };

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
        : (AppColors.upColor, AppColors.upColorLight);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);
    final isSpringReturn = config.behavior.isSpringReturn;

    return SizedBox.expand(
      child: PushControlButton(
        label: config.label,
        icon: icon,
        isDisabled: isDisabled,
        isSpringReturn: isSpringReturn,
        externalStateId: _stateIdFor(activeState, isSpringReturn),
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        rotation: config.rotation,
        pressScale: config.behavior.pressScale,
        debounceMs: config.behavior.debounceMs,
        longPressRequiredMs: config.behavior.longPressRequiredMs,
        onStateChanged: (stateId) =>
            onCommand(config.id, _controlStateFor(stateId)),
      ),
    );
  }
}
