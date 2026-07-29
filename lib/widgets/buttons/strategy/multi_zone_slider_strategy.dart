import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrossTravelStrategy
//
// Wraps the generic MultiZoneSliderButton — the combined-slider "type" kept
// as an optional selectable button type. MultiZoneSliderButton only ever
// reports a generic zone id (zone1/zone2/center/zone4/zone5, or zone1/
// center/zone3) — it has no notion of "left"/"right" ButtonConfig or two
// PLC-mapped halves. This combined traverse type intrinsically needs both
// LEFT and RIGHT ButtonConfig (two labels), which a single
// ButtonTypeStrategy.build() call can't express without leaking this one
// type's oddity into the shared interface every other strategy would have
// to ignore. So build() (below) supports only the "single side" case with a
// same-value fallback label, and [buildPaired] — an escape hatch OUTSIDE the
// ButtonTypeStrategy interface, directly analogous to how
// ButtonEditSheet.forAxis already special-cases this one axis today — is the
// real entry point screens should use for cross-travel. Translating the
// widget's generic zone id into which side's ButtonConfig it belongs to (and
// the legacy ControlState the rest of the pipeline still expects) happens
// entirely HERE, in the strategy — never inside the widget.
//
// Whichever entry point is used, the invariant is preserved: exactly two
// onCommand(buttonId, state) calls happen over a drag's lifetime (one per
// logical direction, or an idle call on release) — never a combined
// callback. Downstream code only ever sees the uniform per-button signature.
//
// ── Zone-id resolution (crossTravelZoneId) ─────────────────────────────────
//
// crossTravelZoneId below is the pure, exhaustive relabeling used by
// resolveButtonCommand (see control_grid_utils.dart) to recover a button's
// logical state id from its (side, ControlState) pair with no default/
// fallback case, so a future ControlState value would be a compile error
// here rather than silently misrouting a drag into the wrong zone's
// configured output variants. [_zoneIdToSideAndState] below is its exact
// inverse, used to translate MultiZoneSliderButton's own zone id back into
// the (side, ControlState) pair this file's onCommand callers still expect.
// This is the highest-risk part of the whole generic-output-variant
// refactor: a bug here wouldn't look like auto-derivation (adding an
// unconfigured variant) — it would look like one zone silently reading a
// DIFFERENT zone's user-configured variants, which is why every arm is
// written out explicitly instead of collapsed via `_`.
// ─────────────────────────────────────────────────────────────────────────────

/// Exhaustive truth table (5-zone):
///   isLeftButton=true,  idle -> center
///   isLeftButton=true,  slow -> zone2
///   isLeftButton=true,  fast -> zone1
///   isLeftButton=false, idle -> center
///   isLeftButton=false, slow -> zone4
///   isLeftButton=false, fast -> zone5
///
/// Exhaustive truth table (3-zone, [fiveZone]=false — MultiZoneSliderButton
/// never emits ControlState.fast in this variant, but the arm is still written out
/// explicitly rather than defaulted, so a future widget change can't silently
/// misroute a fast zone through an untested path):
///   isLeftButton=true,  idle -> center
///   isLeftButton=true,  slow -> zone1
///   isLeftButton=false, idle -> center
///   isLeftButton=false, slow -> zone3
String crossTravelZoneId({
  required bool isLeftButton,
  required ControlState state,
  required bool fiveZone,
}) {
  if (!fiveZone) {
    return switch (state) {
      ControlState.idle => 'center',
      ControlState.slow => isLeftButton ? 'zone1' : 'zone3',
      ControlState.fast => isLeftButton ? 'zone1' : 'zone3',
    };
  }
  return switch (state) {
    ControlState.idle => 'center',
    ControlState.slow => isLeftButton ? 'zone2' : 'zone4',
    ControlState.fast => isLeftButton ? 'zone1' : 'zone5',
  };
}

/// Exact inverse of [crossTravelZoneId]: translates a zone id reported by
/// [MultiZoneSliderButton.onZoneChanged] into which side it belongs to and
/// the legacy [ControlState] the rest of the pipeline (onCommand ->
/// resolveButtonCommand -> crossTravelZoneId) still expects to see. Written
/// out exhaustively for the same reason as crossTravelZoneId itself: a zone
/// id this table doesn't recognize is a programming error, never silently
/// coerced to centre/idle.
({bool isLeftButton, ControlState state}) zoneIdToSideAndState({
  required String zoneId,
  required bool fiveZone,
}) {
  if (!fiveZone) {
    return switch (zoneId) {
      kZoneCenter => (isLeftButton: true, state: ControlState.idle),
      kZone1 => (isLeftButton: true, state: ControlState.slow),
      kZone3 => (isLeftButton: false, state: ControlState.slow),
      _ => throw ArgumentError.value(zoneId, 'zoneId', 'Unknown 3-zone id'),
    };
  }
  return switch (zoneId) {
    kZoneCenter => (isLeftButton: true, state: ControlState.idle),
    kZone1 => (isLeftButton: true, state: ControlState.fast),
    kZone2 => (isLeftButton: true, state: ControlState.slow),
    kZone4 => (isLeftButton: false, state: ControlState.slow),
    kZone5 => (isLeftButton: false, state: ControlState.fast),
    _ => throw ArgumentError.value(zoneId, 'zoneId', 'Unknown 5-zone id'),
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
    // No sibling config available through the uniform interface — renders
    // using config's own label for both sides as a reasonable single-config
    // fallback. Screens with both LEFT/RIGHT configs available should call
    // buildPaired instead (see plc38_control_screen.dart's traverse axis).
    final endpoints = traverseEndpointsFor(config);

    bool isLeftZoneBlocked = false;
    bool isRightZoneBlocked = false;
    if (!isDisabled) {
      final ctrl = tryReadCraneController(context);
      if (ctrl != null) {
        isLeftZoneBlocked = ctrl.isFieldBlockedForButton(
          endpoints.leftId,
          _nearZoneFieldsFor(config, isLeft: true),
        );
        isRightZoneBlocked = ctrl.isFieldBlockedForButton(
          endpoints.rightId,
          _nearZoneFieldsFor(config, isLeft: false),
        );
      }
    }

    return buildPaired(
      leftId: endpoints.leftId,
      rightId: endpoints.rightId,
      leftLabel: endpoints.leftLabel,
      rightLabel: endpoints.rightLabel,
      isDisabled: isDisabled,
      isLeftZoneBlocked: isLeftZoneBlocked,
      isRightZoneBlocked: isRightZoneBlocked,
      onCommand: onCommand,
    );
  }

  /// Fields the near (slow) zone on this side would claim — used only as the
  /// representative non-idle state for the drag-clamp preview. The actual
  /// composition, when the gesture fires for real, always re-resolves the
  /// exact zone via crossTravelZoneId + config.stateMappings (see the
  /// control screens' onCommand handlers).
  Set<PlcOutputVariant> _nearZoneFieldsFor(
    ButtonConfig config, {
    required bool isLeft,
  }) {
    final zoneId = crossTravelZoneId(
      isLeftButton: isLeft,
      state: ControlState.slow,
      fiveZone: true,
    );
    return config.stateMappings[zoneId]?.activeVariants ?? const {};
  }

  /// The real entry point for cross-travel: takes both LEFT and RIGHT
  /// button ids/labels explicitly and adapts MultiZoneSliderButton's generic
  /// `onZoneChanged(zoneId)` callback into two independent
  /// `onCommand(buttonId, state)` calls via [zoneIdToSideAndState].
  Widget buildPaired({
    required String leftId,
    required String rightId,
    required String leftLabel,
    required String rightLabel,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
    bool isLeftZoneBlocked = false,
    bool isRightZoneBlocked = false,
  }) {
    return MultiZoneSliderButton(
      startLabel: leftLabel,
      endLabel: rightLabel,
      isDisabled: isDisabled,
      isStartZoneBlocked: isLeftZoneBlocked,
      isEndZoneBlocked: isRightZoneBlocked,
      onZoneChanged: (zoneId) {
        final resolved = zoneIdToSideAndState(zoneId: zoneId, fiveZone: true);
        if (resolved.state == ControlState.idle) {
          onCommand(leftId, ControlState.idle);
          if (rightId != leftId) onCommand(rightId, ControlState.idle);
          return;
        }
        onCommand(resolved.isLeftButton ? leftId : rightId, resolved.state);
      },
    );
  }

  ({String leftId, String rightId, String leftLabel, String rightLabel})
  traverseEndpointsFor(ButtonConfig config) {
    if (config.role?.axis == AxisKind.traverse) {
      final isLeftConfig = config.role == ControlRole.traverseLeft;
      return (
        leftId: ControlRole.traverseLeft.name,
        rightId: ControlRole.traverseRight.name,
        leftLabel: isLeftConfig
            ? config.label
            : ControlRole.traverseLeft.defaultLabel,
        rightLabel: isLeftConfig
            ? ControlRole.traverseRight.defaultLabel
            : config.label,
      );
    }

    return (
      leftId: config.id,
      rightId: config.id,
      leftLabel: config.label,
      rightLabel: config.label,
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
    final endpoints = traverseEndpointsFor(config);

    // Per-zone blocking: prevents this slider from entering the zone that
    // would claim a PLC field already owned by another button.
    bool isLeftZoneBlocked = false;
    bool isRightZoneBlocked = false;
    if (!isDisabled) {
      final ctrl = tryReadCraneController(context);
      if (ctrl != null) {
        isLeftZoneBlocked = ctrl.isFieldBlockedForButton(
          endpoints.leftId,
          _fieldsForEndpoint(config, endpoints.leftId, isLeft: true),
        );
        isRightZoneBlocked = ctrl.isFieldBlockedForButton(
          endpoints.rightId,
          _fieldsForEndpoint(config, endpoints.rightId, isLeft: false),
        );
      }
    }

    return MultiZoneSliderButton(
      startLabel: endpoints.leftLabel,
      endLabel: endpoints.rightLabel,
      isDisabled: isDisabled,
      isStartZoneBlocked: isLeftZoneBlocked,
      isEndZoneBlocked: isRightZoneBlocked,
      variant: MultiZoneSliderVariant.threeZone,
      onZoneChanged: (zoneId) {
        final resolved = zoneIdToSideAndState(zoneId: zoneId, fiveZone: false);
        if (resolved.state == ControlState.idle) {
          onCommand(endpoints.leftId, ControlState.idle);
          if (endpoints.rightId != endpoints.leftId) {
            onCommand(endpoints.rightId, ControlState.idle);
          }
          return;
        }
        onCommand(
          resolved.isLeftButton ? endpoints.leftId : endpoints.rightId,
          resolved.state,
        );
      },
    );
  }

  /// Representative non-idle-state fields for one endpoint of the paired
  /// slider. [sideId] may be [config]'s own id (real button — resolved via
  /// crossTravelZoneId + config.stateMappings) or a virtual fast-key id
  /// (kTraverseLeftFastKey/kTraverseRightFastKey — resolved via the fixed,
  /// migrated kVirtualFastKeyStateMappings table, never re-derived).
  Set<PlcOutputVariant> _fieldsForEndpoint(
    ButtonConfig config,
    String sideId, {
    required bool isLeft,
  }) {
    final virtualStates = kVirtualFastKeyStateMappings[sideId];
    if (virtualStates != null) {
      return virtualStates[kVirtualFastKeyActiveState]?.activeVariants ??
          const {};
    }
    final zoneId = crossTravelZoneId(
      isLeftButton: isLeft,
      state: ControlState.slow,
      fiveZone: false,
    );
    return config.stateMappings[zoneId]?.activeVariants ?? const {};
  }

  // Independent 3-zone mode: each traverse button controls its own
  // direction on the natural side and the shared fast_lr modifier on the
  // inward side (toward the adjacent slider).
  //
  //   traverseLeft  → drag left  = left    (leftId = traverseLeft)
  //                   drag right = fast_lr  (rightId = kTraverseLeftFastKey)
  //   traverseRight → drag right = right   (rightId = traverseRight)
  //                   drag left  = fast_lr  (leftId = kTraverseRightFastKey)
  //
  // Combined fast traversal requires both sliders together:
  //   left  fast = left slider dragged left  + right slider dragged left
  //   right fast = right slider dragged right + left slider dragged right
  ({String leftId, String rightId, String leftLabel, String rightLabel})
  traverseEndpointsFor(ButtonConfig config) {
    if (config.role == ControlRole.traverseLeft) {
      return (
        leftId: ControlRole.traverseLeft.name,
        rightId: kTraverseLeftFastKey,
        leftLabel: config.label,
        rightLabel: 'FAST',
      );
    }
    if (config.role == ControlRole.traverseRight) {
      return (
        leftId: kTraverseRightFastKey,
        rightId: ControlRole.traverseRight.name,
        leftLabel: 'FAST',
        rightLabel: config.label,
      );
    }

    return (
      leftId: config.id,
      rightId: config.id,
      leftLabel: config.label,
      rightLabel: config.label,
    );
  }
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
