import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/cross_travel_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/push_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/slider_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/toggle_button_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Strategy registry
//
// Plain const map — no factory/service-locator machinery needed, the type
// set is closed and small. Adding a 5th button type later (joystick, rotary,
// ...) is a pure addition: implement ButtonTypeStrategy, add one map entry —
// zero edits to existing call sites. That is the duplication this refactor
// removes (today's 4 near-duplicate switch(axisCfg.widgetType) methods).
// ─────────────────────────────────────────────────────────────────────────────

const Map<ButtonType, ButtonTypeStrategy> kButtonTypeStrategies = {
  ButtonType.pushButton: PushButtonStrategy(),
  ButtonType.toggle: ToggleButtonStrategy(),
  ButtonType.sliderButton: SliderButtonStrategy(),
  ButtonType.crossTravel: CrossTravelStrategy(),
  ButtonType.crossTravelSlowOnly: CrossTravelSlowOnlyStrategy(),
};

// ─────────────────────────────────────────────────────────────────────────────
// ConfigurableButton
//
// Single generic entry point both control screens use for every button.
// Reads a ButtonConfig, resolves the right ButtonTypeStrategy, and renders:
// sizing shell -> rotation shell -> strategy's interactive widget. Direct
// generalization of the existing IndustrialSpringButton (generic primitive)
// + DirectionalPushControlButton (thin per-role wrapper) split, just
// parameterized by strategy instead of hardcoded to push-button behavior.
//
// Does NOT wrap EditableControlTile itself — that stays a call-site concern
// (see plc14_control_screen.dart / plc38_control_screen.dart), keeping this
// widget reusable in contexts that don't need editing chrome (e.g.
// CustomizationCanvas's disabled preview tiles).
// ─────────────────────────────────────────────────────────────────────────────

class ConfigurableButton extends StatelessWidget {
  const ConfigurableButton({
    super.key,
    required this.config,
    required this.activeState,
    required this.isDisabled,
    required this.onCommand,
    this.height,
  });

  final ButtonConfig config;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandCallback onCommand;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final strategy = kButtonTypeStrategies[config.type]!;
    final child = SizedBox(
      height: height ?? config.resolvedHeight,
      child: strategy.build(
        context: context,
        config: config,
        activeState: activeState,
        isDisabled: isDisabled,
        onCommand: onCommand,
      ),
    );

    if (config.rotation.quarterTurns == 0) return child;
    return RotatedBox(quarterTurns: config.rotation.quarterTurns, child: child);
  }
}
