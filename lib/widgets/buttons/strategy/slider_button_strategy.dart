import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_step_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SliderButtonStrategy
//
// Renders MultiStepSliderButton through its generic state-id contract. PLC
// output resolution remains outside both layers in ButtonConfig.stateMappings.
// ─────────────────────────────────────────────────────────────────────────────

class SliderButtonStrategy extends ButtonTypeStrategy {
  const SliderButtonStrategy();

  @override
  ButtonType get type => ButtonType.sliderButton;

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
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);
    final activeColor = config.style.resolvePrimary(AppColors.accent);

    void dispatchStateId(String stateId) {
      final dispatch = onStateIdCommand;
      if (dispatch == null) {
        assert(() {
          debugPrint(
            'SliderButtonStrategy missing onStateIdCommand for ${config.id}; '
            'ignored $stateId.',
          );
          return true;
        }());
        return;
      }
      dispatch(config.id, stateId);
    }

    return MultiStepSliderButton(
      label: config.label,
      icon: icon,
      isDisabled: isDisabled,
      externalStateId: logicalStateIdFor(
        type: type,
        physicalState: activeState,
      ),
      activeColor: activeColor,
      step2Color: config.style.activeColor,
      style: config.style,
      rotation: config.effectiveRotation,
      onStateChanged: dispatchStateId,
    );
  }
}
