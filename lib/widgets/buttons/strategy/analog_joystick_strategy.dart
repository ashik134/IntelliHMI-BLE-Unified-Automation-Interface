import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/joystick_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

/// Backs both ButtonType.analogJoystick1D (dualAxis: false) and
/// .analogJoystick2D (dualAxis: true). Reuses IndustrialJoystickControl
/// as-is — the same widget the DIGITAL joystick uses — but reads its
/// continuous JoystickOutput.x/.y (already dead-zone-applied, see
/// _outputFor in joystick_control.dart) instead of the stepped
/// .xStep/.yStep, and calls onAnalogCommand instead of onCommand. Zero
/// edits to joystick_control.dart/joystick_config.dart/
/// JoystickButtonStrategy — the digital joystick is untouched.
class AnalogJoystickStrategy extends ButtonTypeStrategy {
  const AnalogJoystickStrategy({required this.type, required this.dualAxis});

  @override
  final ButtonType type;

  /// true for analogJoystick2D (gimbal, both axes computed — only the
  /// configured [AnalogJoystickConfig.outputAxis] is transmitted), false
  /// for analogJoystick1D (rail, single configured
  /// [AnalogJoystickConfig.orientation]).
  final bool dualAxis;

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
    final analogConfig = AnalogJoystickConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.darkInfo, AppColors.accent);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon = config.icon ?? Icons.control_camera_rounded;

    final joystickAxis =
        analogConfig.orientation == AnalogJoystickOrientation.horizontal
        ? JoystickAxis.horizontal
        : JoystickAxis.vertical;
    final joystickConfig = JoystickConfig(
      mode: dualAxis
          ? JoystickMode.dualAxisAnalog
          : JoystickMode.singleAxisAnalog,
      axis: joystickAxis,
      boundary: JoystickBoundary.circular,
      springReturn: analogConfig.springReturnEnabled,
      deadZone: analogConfig.deadZone,
    );

    return IndustrialJoystickControl(
      config: joystickConfig,
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      enabled: !isDisabled,
      onChanged: (output) {
        final raw = dualAxis
            ? (analogConfig.outputAxis == AnalogJoystickOutputAxis.x
                  ? output.x
                  : output.y)
            : (joystickAxis == JoystickAxis.horizontal ? output.x : output.y);
        final signed = analogConfig.invert ? -raw : raw;
        onAnalogCommand?.call(config, analogConfig.signedToValue(signed));
      },
    );
  }
}
