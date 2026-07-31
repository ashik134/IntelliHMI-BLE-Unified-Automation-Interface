import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/analog_slider_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

/// Backs both ButtonType.analogSliderOT and .analogSliderTOT. Both share one
/// AnalogSliderConfig shape and one AnalogSliderControl widget — the
/// one-side/two-side behavior is entirely a property of the stored config's
/// neutralValue (see AnalogSliderConfig doc comment). A sensible default
/// neutralValue per type is seeded once, the first time a button switches to
/// one of these types (see _CustomTypePicker._selectType in
/// button_edit_sheet.dart) — this strategy itself is pure rendering and
/// never guesses at defaults.
class AnalogSliderStrategy extends ButtonTypeStrategy {
  const AnalogSliderStrategy({required this.type});

  @override
  final ButtonType type;

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
    final analogConfig = AnalogSliderConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();
    final (defaultColor, defaultColorLight) = role != null
        ? colorsForRole(role)
        : (AppColors.darkInfo, AppColors.accent);
    final activeColor = config.style.resolvePrimary(defaultColor);
    final activeColorLight = config.style.resolveActive(defaultColorLight);
    final icon = config.icon ?? Icons.swap_vert_rounded;

    return AnalogSliderControl(
      config: analogConfig,
      label: config.label,
      icon: icon,
      activeColor: activeColor,
      activeColorLight: activeColorLight,
      enabled: !isDisabled,
      rotation: config.rotation,
      onChanged: (value) => onAnalogCommand?.call(config, value),
    );
  }
}
