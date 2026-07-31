import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/joystick_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// JoystickButtonStrategy
//
// A joystick decomposes into up to 4 independent virtual sub-buttons — one
// per direction (posX/negX for single-axis, plus posY/negY for dual-axis) —
// each dispatched as its own onCommand(virtualId, state). The direction
// identity itself carries no PLC meaning: which field(s) each direction
// asserts comes entirely from config.joystickSubButtonMappings, resolved by
// the caller exactly like any other button's stateMappings.
// ─────────────────────────────────────────────────────────────────────────────

class JoystickButtonStrategy extends ButtonTypeStrategy {
  const JoystickButtonStrategy();

  @override
  ButtonType get type => ButtonType.joystick;

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
    final joystickConfig = JoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalizedForMode();
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.accent, AppColors.accent);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon =
        config.icon ?? (role != null ? iconForRole(role) : Icons.gamepad);

    return IndustrialJoystickControl(
      config: joystickConfig,
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      enabled: !isDisabled,
      onChanged: (value) {
        for (final command in _commandsFor(config, joystickConfig, value)) {
          onCommand(command.buttonId, command.state);
        }
      },
    );
  }

  List<_JoystickCommand> _commandsFor(
    ButtonConfig config,
    JoystickConfig joystickConfig,
    JoystickOutput value,
  ) {
    final commands = <_JoystickCommand>[];

    void axisCommands({
      required JoystickDirection positive,
      required JoystickDirection negative,
      required int step,
    }) {
      final positiveId = joystickVirtualButtonId(config.id, positive);
      final negativeId = joystickVirtualButtonId(config.id, negative);
      final positiveState = step > 0 ? _stateForStep(step) : ControlState.idle;
      final negativeState = step < 0 ? _stateForStep(step) : ControlState.idle;
      commands
        ..add(_JoystickCommand(positiveId, positiveState))
        ..add(_JoystickCommand(negativeId, negativeState));
    }

    if (joystickConfig.isDualAxis) {
      axisCommands(
        positive: JoystickDirection.posX,
        negative: JoystickDirection.negX,
        step: value.xStep,
      );
      axisCommands(
        positive: JoystickDirection.posY,
        negative: JoystickDirection.negY,
        step: value.yStep,
      );
      return commands;
    }

    final step = joystickConfig.axis == JoystickAxis.horizontal
        ? value.xStep
        : value.yStep;
    axisCommands(
      positive: JoystickDirection.posX,
      negative: JoystickDirection.negX,
      step: step,
    );
    return commands;
  }

  ControlState _stateForStep(int step) {
    final magnitude = step.abs();
    if (magnitude >= 2) return ControlState.level2;
    if (magnitude == 1) return ControlState.level1;
    return ControlState.idle;
  }
}

class _JoystickCommand {
  const _JoystickCommand(this.buttonId, this.state);

  final String buttonId;
  final ControlState state;
}
