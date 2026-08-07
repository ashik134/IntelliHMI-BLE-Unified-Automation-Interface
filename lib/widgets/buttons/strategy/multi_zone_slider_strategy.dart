import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/multi_zone_slider_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MultiZoneSliderStrategy (Bidirectional5StepStrategy / Bidirectional3StepStrategy)
//
// Every multi-zone slider is a single, free-standing ButtonConfig that owns
// every zone directly through its own stateMappings — dispatched via
// [onStateIdCommand] with the widget's raw zone id, no side/pairing
// translation of any kind. This is what makes the control genuinely usable
// as any button on the grid, not tied to any fixed pair of controls.
// ─────────────────────────────────────────────────────────────────────────────

/// Exhaustive truth table (5-zone):
///   isLeftButton=true,  idle   -> center
///   isLeftButton=true,  level1 -> zone2
///   isLeftButton=true,  level2 -> zone1
///   isLeftButton=false, idle   -> center
///   isLeftButton=false, level1 -> zone4
///   isLeftButton=false, level2 -> zone5
///
/// Exhaustive truth table (3-zone, [fiveZone]=false — MultiZoneSliderButton
/// never emits ControlState.level2 in this variant, but the arm is still
/// written out explicitly rather than defaulted, so a future widget change
/// can't silently misroute a level2 zone through an untested path):
///   isLeftButton=true,  idle   -> center
///   isLeftButton=true,  level1 -> zone1
///   isLeftButton=false, idle   -> center
///   isLeftButton=false, level1 -> zone3
String multiZoneId({
  required bool isLeftButton,
  required ControlState state,
  required bool fiveZone,
}) {
  if (!fiveZone) {
    return switch (state) {
      ControlState.idle => 'center',
      ControlState.level1 => isLeftButton ? 'zone1' : 'zone3',
      ControlState.level2 => isLeftButton ? 'zone1' : 'zone3',
    };
  }
  return switch (state) {
    ControlState.idle => 'center',
    ControlState.level1 => isLeftButton ? 'zone2' : 'zone4',
    ControlState.level2 => isLeftButton ? 'zone1' : 'zone5',
  };
}

class Bidirectional5StepStrategy extends ButtonTypeStrategy {
  const Bidirectional5StepStrategy();

  @override
  ButtonType get type => ButtonType.bidirectionalSlider5Step;

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
    return buildGenericMultiZoneSlider(
      context: context,
      config: config,
      isDisabled: isDisabled,
      onStateIdCommand: onStateIdCommand,
      fiveZone: true,
    );
  }
}

class Bidirectional3StepStrategy extends ButtonTypeStrategy {
  const Bidirectional3StepStrategy();

  @override
  ButtonType get type => ButtonType.bidirectionalSlider3Step;

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
    return buildGenericMultiZoneSlider(
      context: context,
      config: config,
      isDisabled: isDisabled,
      onStateIdCommand: onStateIdCommand,
      fiveZone: false,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared build path
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a free-standing MultiZoneSliderButton for [config]: a single
/// ButtonConfig owns every zone directly through its own stateMappings,
/// dispatched via [onStateIdCommand] with the widget's raw zone id.
Widget buildGenericMultiZoneSlider({
  required BuildContext context,
  required ButtonConfig config,
  required bool isDisabled,
  required ButtonStateIdCommandCallback? onStateIdCommand,
  required bool fiveZone,
}) {
  final startZoneId = fiveZone
      ? MultiZoneSliderStateId.zone2
      : MultiZoneSliderStateId.zone1;
  final endZoneId = fiveZone
      ? MultiZoneSliderStateId.zone4
      : MultiZoneSliderStateId.zone3;

  bool isStartZoneBlocked = false;
  bool isEndZoneBlocked = false;
  if (!isDisabled) {
    final ctrl = tryReadCraneController(context);
    if (ctrl != null) {
      isStartZoneBlocked = ctrl.isFieldBlockedForButton(
        config.id,
        config.stateMappings[startZoneId]?.activeVariants ?? const {},
      );
      isEndZoneBlocked = ctrl.isFieldBlockedForButton(
        config.id,
        config.stateMappings[endZoneId]?.activeVariants ?? const {},
      );
    }
  }

  final zoneConfig = MultiZoneSliderConfig.fromCustomProperties(
    config.customProperties,
  );

  return MultiZoneSliderButton(
    startLabel: zoneConfig.startLabel ?? config.label,
    endLabel: zoneConfig.endLabel ?? config.label,
    startIcon: config.icon ?? Icons.arrow_back_rounded,
    endIcon: config.icon ?? Icons.arrow_forward_rounded,
    isDisabled: isDisabled,
    variant: fiveZone
        ? MultiZoneSliderVariant.fiveZone
        : MultiZoneSliderVariant.threeZone,
    // Reuses the same primary/active style fields every other strategy
    // colors from — see ButtonStyleConfig doc comment on why there's no
    // separate nearColor/farColor model field.
    nearColor: config.style.primaryColor ?? AppColors.accent,
    farColor: config.style.activeColor ?? AppColors.fastColor,
    style: config.style,
    rotation: config.effectiveRotation,
    orientation: zoneConfig.orientation,
    deadZone: zoneConfig.deadZoneFraction,
    farZone: zoneConfig.farZoneFraction,
    isStartZoneBlocked: isStartZoneBlocked,
    isEndZoneBlocked: isEndZoneBlocked,
    onStateChanged: (zoneId) {
      final dispatch = onStateIdCommand;
      if (dispatch == null) {
        assert(() {
          debugPrint(
            'MultiZoneSliderStrategy missing onStateIdCommand for '
            '${config.id}; ignored $zoneId.',
          );
          return true;
        }());
        return;
      }
      dispatch(config.id, zoneId);
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared utility
// ─────────────────────────────────────────────────────────────────────────────

/// Tries to read [CraneController] from [context] without throwing.
/// Returns null when the provider is absent (editing mode, tests, canvas).
CraneController? tryReadCraneController(BuildContext context) {
  try {
    return context.read<CraneController>();
  } catch (_) {
    return null;
  }
}
