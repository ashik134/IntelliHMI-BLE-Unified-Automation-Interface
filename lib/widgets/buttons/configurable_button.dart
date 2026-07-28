import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/alarm_indicator_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/cross_travel_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/horn_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/joystick_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/potentiometer_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/push_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/slider_button_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/toggle_button_strategy.dart';

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
  ButtonType.bidirectionalSlider5Step: Bidirectional5StepStrategy(),
  ButtonType.bidirectionalSlider3Step: Bidirectional3StepStrategy(),
  ButtonType.joystick: JoystickButtonStrategy(),
  ButtonType.potentiometer: PotentiometerButtonStrategy(),
  ButtonType.horn: HornButtonStrategy(),
  ButtonType.alarmIndicator: AlarmIndicatorStrategy(),
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
    this.onAnalogCommand,
    this.height,
  });

  final ButtonConfig config;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandCallback onCommand;
  final AnalogButtonCommandCallback? onAnalogCommand;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final strategy = kButtonTypeStrategies[config.type]!;

    Widget button({double? width, double? childHeight}) {
      return SizedBox(
        width: width,
        height: childHeight ?? height ?? config.resolvedHeight,
        child: strategy.build(
          context: context,
          config: config,
          activeState: activeState,
          isDisabled: isDisabled,
          onCommand: onCommand,
          onAnalogCommand: onAnalogCommand,
        ),
      );
    }

    final outerHeight = height ?? config.resolvedHeight;
    if (config.rotation.quarterTurns == 0) {
      return SizedBox(
        height: outerHeight,
        child: button(childHeight: outerHeight),
      );
    }

    return SizedBox(
      height: outerHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          final availableHeight = constraints.maxHeight;
          if (!availableWidth.isFinite || !availableHeight.isFinite) {
            return Center(
              child: Transform.rotate(
                angle: config.rotation.turns * 2 * math.pi,
                child: button(childHeight: outerHeight),
              ),
            );
          }

          final isSideways = config.rotation.quarterTurns.isOdd;
          final childWidth = isSideways ? availableHeight : availableWidth;
          final childHeight = isSideways ? availableWidth : availableHeight;

          return ClipRect(
            child: Center(
              child: Transform.rotate(
                angle: config.rotation.turns * 2 * math.pi,
                child: button(width: childWidth, childHeight: childHeight),
              ),
            ),
          );
        },
      ),
    );
  }
}
