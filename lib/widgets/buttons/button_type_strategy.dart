import 'package:flutter/widgets.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonTypeStrategy
//
// Shared contract every button TYPE (push/toggle/slider/cross-travel, and
// future joystick/rotary/lever) implements. Rendering shell (ConfigurableButton),
// selection, editing, and persistence are handled ONCE, outside the strategy —
// a strategy only supplies interaction/gesture logic and how to visually
// represent its own state.
// ─────────────────────────────────────────────────────────────────────────────

/// One uniform command signature every strategy emits, resolving
/// CrossTravelSlider's {isLeft, state} inconsistency: every strategy —
/// including cross-travel — reports state per logical button id, never a
/// combined/multi-field callback.
typedef ButtonCommandCallback =
    void Function(String buttonId, ControlState state);

abstract class ButtonTypeStrategy {
  const ButtonTypeStrategy();

  ButtonType get type;

  /// Builds the interactive control surface for [config]. [activeState] is
  /// the authoritative current ControlState (local optimistic state OR'd
  /// with any externally-reported PLC state, resolved by the caller exactly
  /// as today's screens' _externalVertState-style helpers do). [onCommand]
  /// must be invoked with [config.id] whenever this strategy's gesture fires.
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
  });
}
