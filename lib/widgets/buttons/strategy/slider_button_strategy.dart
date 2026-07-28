import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/3-step_slider.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SliderButtonStrategy
//
// Wraps CraneSliderButton (reused verbatim, zero changes). One ButtonConfig
// = one direction, matching today's per-direction instantiation.
// ─────────────────────────────────────────────────────────────────────────────

class SliderButtonStrategy extends ButtonTypeStrategy {
  const SliderButtonStrategy();

  @override
  ButtonType get type => ButtonType.sliderButton;

  /// CraneSliderButton's `isUp` is purely cosmetic (drag-gesture orientation
  /// default) — derived here from PlcOutputVariant's "primary" vs "secondary"
  /// direction (up/left/forward vs down/right/reverse), mirroring how each
  /// axis is oriented on the control screens today.
  bool _isUp(PlcOutputVariant mapping) => switch (mapping) {
    PlcOutputVariant.df2 ||
    PlcOutputVariant.df5 ||
    PlcOutputVariant.df8 => true,
    _ => false,
  };

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
    final icon =
        config.icon ??
        (role != null ? iconForRole(role) : Icons.radio_button_checked);

    return CraneSliderButton(
      label: config.label,
      icon: icon,
      isUp: _isUp(config.plcMapping),
      isDisabled: isDisabled,
      externalState: activeState,
      axisColor: config.style.primaryColor,
      style: config.style,
      onCommandChanged: (state) => onCommand(config.id, state),
    );
  }
}
