import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/detented_selector_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/detented_selector_control.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DetentedSelectorStrategy
//
// A detented selector is a single, free-standing ButtonConfig that owns
// every one of its N positions directly through its own stateMappings —
// dispatched via onStateIdCommand with the widget's raw SelectorPosition.id,
// exactly like the multi-zone slider (see multi_zone_slider_strategy.dart).
// ─────────────────────────────────────────────────────────────────────────────

class DetentedSelectorStrategy extends ButtonTypeStrategy {
  const DetentedSelectorStrategy();

  @override
  ButtonType get type => ButtonType.detentedSelector;

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
    final icon = config.icon ?? Icons.radio_button_checked_rounded;

    final selectorConfig = DetentedSelectorConfig.fromCustomProperties(
      config.customProperties,
    ).normalized();

    return IndustrialDetentedSelectorControl(
      config: selectorConfig,
      label: config.label,
      icon: icon,
      activeColor: primaryColor,
      activeColorLight: activeColorLight,
      enabled: !isDisabled,
      onPositionSelected: (positionId) {
        final dispatch = onStateIdCommand;
        if (dispatch == null) {
          assert(() {
            debugPrint(
              'DetentedSelectorStrategy missing onStateIdCommand for '
              '${config.id}; ignored $positionId.',
            );
            return true;
          }());
          return;
        }
        dispatch(config.id, positionId);
      },
    );
  }
}
