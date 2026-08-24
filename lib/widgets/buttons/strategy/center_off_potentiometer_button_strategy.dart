import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/center_off_potentiometer_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

/// Mirrors PotentiometerButtonStrategy exactly (same PotentiometerConfig
/// source, same onAnalogCommand wiring) — only the rendered widget differs.
class CenterOffPotentiometerButtonStrategy extends ButtonTypeStrategy {
  const CenterOffPotentiometerButtonStrategy();

  @override
  ButtonType get type => ButtonType.potentiometerCenterOff;

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
        : (AppColors.darkInfo, AppColors.accent);
    final primaryColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon = config.icon ?? Icons.center_focus_strong_rounded;
    final potentiometer = PotentiometerConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();

    return IndustrialCenterOffPotentiometerControl(
      config: potentiometer,
      label: config.label,
      icon: icon,
      activeColor: primaryColor,
      activeColorLight: activeColorLight,
      enabled: !isDisabled,
      onChanged: (value) => onAnalogCommand?.call(config, value),
    );
  }
}
