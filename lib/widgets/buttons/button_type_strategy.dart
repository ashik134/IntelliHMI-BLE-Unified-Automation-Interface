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
typedef AnalogButtonCommandCallback =
    void Function(ButtonConfig config, double value);

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
    AnalogButtonCommandCallback? onAnalogCommand,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Gesture-state -> logical-state-id relabeling
//
// Every gesture-handling widget (push button, ToggleSwitchButton,
// CraneSliderButton, CrossTravelSlider, joystick control) only ever reports
// a plain ControlState (idle/slow/fast) — none of them are rewritten by this
// refactor. These functions translate that physical gesture signal into the
// LOGICAL state id used to key ButtonConfig.stateMappings (see
// ButtonTypeLogicalStates.logicalStates). This is a PURE RELABELING: it never
// inspects PlcMapping, never adds a second variant, never consults
// ControlRole/AxisKind. The actual set of PLC output variants a state
// activates is looked up separately, directly from
// ButtonConfig.stateMappings[stateId] — never derived here.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the logical state id for push/toggle/slider/joystick — the
/// button types where a single ButtonConfig's own id already carries all the
/// context needed (no side/zone ambiguity). Cross-travel types use
/// [crossTravelZoneId] instead (see cross_travel_strategy.dart) since they
/// need an explicit side.
String logicalStateIdFor({
  required ButtonType type,
  required ControlState physicalState,
}) {
  switch (type) {
    case ButtonType.pushButton:
      return switch (physicalState) {
        ControlState.idle => 'idle',
        ControlState.slow || ControlState.fast => 'active',
      };
    case ButtonType.toggle:
      // ToggleSwitchButton._commandFor already reports a genuine 3-way
      // signal (left position -> slow, center -> idle, right position ->
      // fast) as an artifact of its internal 3-position model — this is a
      // pure id rename, not a claim that 'right' means anything related to
      // what 'fast' used to mean elsewhere in the app.
      return switch (physicalState) {
        ControlState.idle => 'center',
        ControlState.slow => 'left',
        ControlState.fast => 'right',
      };
    case ButtonType.sliderButton:
    case ButtonType.joystick:
      return switch (physicalState) {
        ControlState.idle => 'idle',
        ControlState.slow => 'step1',
        ControlState.fast => 'step2',
      };
    case ButtonType.potentiometer:
      throw UnsupportedError(
        'logicalStateIdFor does not handle analog potentiometer values.',
      );
    case ButtonType.horn:
    case ButtonType.alarmIndicator:
      // Both are PLC STATUS-DRIVEN FEEDBACK widgets with no gesture-driven
      // physical state at all — their on/off or severity is computed
      // directly from live PlcOutputCommand fields (see
      // HornButtonStrategy/AlarmIndicatorStrategy), never from a
      // ControlState. Reaching here is a programming error.
      throw UnsupportedError(
        'logicalStateIdFor does not handle $type; it is a PLC status-driven '
        'feedback widget, not gesture-derived.',
      );
    case ButtonType.crossTravel:
    case ButtonType.crossTravelSlowOnly:
      // Cross-travel needs an explicit side — callers must use
      // crossTravelZoneId instead. Reaching here is a programming error.
      throw UnsupportedError(
        'logicalStateIdFor does not handle cross-travel types; use '
        'crossTravelZoneId instead.',
      );
  }
}
