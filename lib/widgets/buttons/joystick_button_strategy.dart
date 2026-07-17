import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/joystick_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

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
    AnalogButtonCommandCallback? onAnalogCommand,
  }) {
    final role = config.role;
    final joystickConfig = JoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalizedForMode();
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.traverseColor, AppColors.traverseColorLight);
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
      required ControlRole positive,
      required ControlRole negative,
      required int step,
    }) {
      final positiveId = _virtualIdFor(config, positive.plcMapping);
      final negativeId = _virtualIdFor(config, negative.plcMapping);
      final positiveState = step > 0 ? _stateForStep(step) : ControlState.idle;
      final negativeState = step < 0 ? _stateForStep(step) : ControlState.idle;
      commands
        ..add(_JoystickCommand(positiveId, positiveState))
        ..add(_JoystickCommand(negativeId, negativeState));
    }

    final role = config.role;
    if (joystickConfig.isDualAxis) {
      axisCommands(
        positive: ControlRole.traverseRight,
        negative: ControlRole.traverseLeft,
        step: value.xStep,
      );
      axisCommands(
        positive: ControlRole.travelForward,
        negative: ControlRole.travelReverse,
        step: value.yStep,
      );
      return commands;
    }

    final axis = role?.axis ?? AxisKind.hoist;
    final step = joystickConfig.axis == JoystickAxis.horizontal
        ? value.xStep
        : value.yStep;
    final (positive, negative) = _rolePairForAxis(axis);
    axisCommands(positive: positive, negative: negative, step: step);
    return commands;
  }

  ControlState _stateForStep(int step) {
    final magnitude = step.abs();
    if (magnitude >= 2) return ControlState.fast;
    if (magnitude == 1) return ControlState.slow;
    return ControlState.idle;
  }

  (ControlRole positive, ControlRole negative) _rolePairForAxis(AxisKind axis) {
    return switch (axis) {
      AxisKind.hoist => (ControlRole.hoistUp, ControlRole.hoistDown),
      AxisKind.traverse => (
        ControlRole.traverseRight,
        ControlRole.traverseLeft,
      ),
      AxisKind.travel => (ControlRole.travelForward, ControlRole.travelReverse),
    };
  }

  String _virtualIdFor(ButtonConfig config, PlcMapping? mapping) {
    if (mapping == null) return config.id;
    return joystickVirtualButtonId(config.id, mapping);
  }
}

class _JoystickCommand {
  const _JoystickCommand(this.buttonId, this.state);

  final String buttonId;
  final ControlState state;
}
