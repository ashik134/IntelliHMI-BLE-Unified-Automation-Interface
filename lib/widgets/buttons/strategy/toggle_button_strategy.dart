import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_icon_registry.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart'
    show PushButtonWiringConfig;
import 'package:rev_crane_control_ops/models/toggle_button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/toggle_switch_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleButtonStrategy
// ─────────────────────────────────────────────────────────────────────────────

class ToggleButtonStrategy extends ButtonTypeStrategy {
  const ToggleButtonStrategy();

  @override
  ButtonType get type => ButtonType.toggle;

  /// Maps the stored [PushButtonWiringConfig] to the visual [ToggleSwitchMode]
  /// understood by [ToggleSwitchButton].
  static ToggleSwitchMode _modeFor(
    PushButtonWiringConfig wiring,
  ) => switch (wiring) {
    PushButtonWiringConfig.offMomentary => ToggleSwitchMode.springReturnOneSide,
    PushButtonWiringConfig.offLatched => ToggleSwitchMode.latchingOneSide,
    PushButtonWiringConfig.springReturnBoth =>
      ToggleSwitchMode.springReturnBoth,
    PushButtonWiringConfig.latchingBoth => ToggleSwitchMode.latchingBoth,
    PushButtonWiringConfig.mixedLeftLatchRightSpring => ToggleSwitchMode.mixed,
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
        : (Colors.blueGrey, Colors.blueGrey.shade200);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);
    final mode = _modeFor(config.behavior.wiring);
    final toggleConfig = ToggleButtonConfig.fromCustomProperties(
      config.customProperties,
    );

    return ToggleSwitchButton(
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      isActive: activeState != ControlState.idle,
      isDisabled: isDisabled,
      isSpringReturn: config.behavior.isSpringReturn,
      mode: mode,
      // T-O-R: top (left) latches, bottom (right) spring-returns.
      leftIsSpringReturn: mode == ToggleSwitchMode.mixed ? false : null,
      rightIsSpringReturn: mode == ToggleSwitchMode.mixed ? true : null,
      topLabel: toggleConfig.leftLabel,
      bottomLabel: toggleConfig.rightLabel,
      topIcon: iconForKey(toggleConfig.leftIconKey),
      bottomIcon: iconForKey(toggleConfig.rightIconKey),
      topDisabled: toggleConfig.disableLeft,
      bottomDisabled: toggleConfig.disableRight,
      style: config.style,
      rotation: config.rotation,
      onCommandChanged: (state) => onCommand(config.id, state),
    );
  }
}
