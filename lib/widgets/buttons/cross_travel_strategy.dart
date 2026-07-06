import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/cross_travel_slider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CrossTravelStrategy
//
// Wraps CrossTravelSlider (reused verbatim, zero changes) — the combined-
// slider "type" kept as an optional selectable button type. CrossTravelSlider
// intrinsically needs both LEFT and RIGHT ButtonConfig (two labels), which a
// single ButtonTypeStrategy.build() call can't express without leaking this
// one type's oddity into the shared interface every other strategy would
// have to ignore. So build() (below) supports only the "single side" case
// with a same-value fallback label, and [buildPaired] — an escape hatch
// OUTSIDE the ButtonTypeStrategy interface, directly analogous to how
// ButtonEditSheet.forAxis already special-cases this one axis today — is the
// real entry point screens should use for cross-travel.
//
// Whichever entry point is used, the invariant is preserved: exactly two
// onCommand(buttonId, state) calls happen over a drag's lifetime (one per
// logical direction, or an idle call on release) — never a combined
// callback. Downstream code only ever sees the uniform per-button signature.
// ─────────────────────────────────────────────────────────────────────────────

class CrossTravelStrategy extends ButtonTypeStrategy {
  const CrossTravelStrategy();

  @override
  ButtonType get type => ButtonType.crossTravel;

  @override
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
  }) {
    // No sibling config available through the uniform interface — renders
    // using config's own label for both sides as a reasonable single-config
    // fallback. Screens with both LEFT/RIGHT configs available should call
    // buildPaired instead (see plc38_control_screen.dart's traverse axis).
    final endpoints = _traverseEndpointsFor(config);
    return buildPaired(
      leftId: endpoints.leftId,
      rightId: endpoints.rightId,
      leftLabel: endpoints.leftLabel,
      rightLabel: endpoints.rightLabel,
      isDisabled: isDisabled,
      onCommand: onCommand,
    );
  }

  /// The real entry point for cross-travel: takes both LEFT and RIGHT
  /// button ids/labels explicitly and adapts CrossTravelSlider's combined
  /// `{isLeft, state}` callback into two independent
  /// `onCommand(buttonId, state)` calls.
  Widget buildPaired({
    required String leftId,
    required String rightId,
    required String leftLabel,
    required String rightLabel,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
  }) {
    return CrossTravelSlider(
      leftLabel: leftLabel,
      rightLabel: rightLabel,
      isDisabled: isDisabled,
      onCommandChanged: ({required bool isLeft, required ControlState state}) {
        if (state == ControlState.idle) {
          onCommand(leftId, ControlState.idle);
          if (rightId != leftId) onCommand(rightId, ControlState.idle);
          return;
        }
        onCommand(isLeft ? leftId : rightId, state);
      },
    );
  }

  ({String leftId, String rightId, String leftLabel, String rightLabel})
  _traverseEndpointsFor(ButtonConfig config) {
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

class CrossTravelSlowOnlyStrategy extends ButtonTypeStrategy {
  const CrossTravelSlowOnlyStrategy();

  @override
  ButtonType get type => ButtonType.crossTravelSlowOnly;

  @override
  Widget build({
    required BuildContext context,
    required ButtonConfig config,
    required ControlState activeState,
    required bool isDisabled,
    required ButtonCommandCallback onCommand,
  }) {
    final endpoints = _traverseEndpointsFor(config);
    return CrossTravelSlider(
      leftLabel: endpoints.leftLabel,
      rightLabel: endpoints.rightLabel,
      isDisabled: isDisabled,
      variant: CrossTravelSliderVariant.threeZoneSlowOnly,
      onCommandChanged: ({required bool isLeft, required ControlState state}) {
        if (state == ControlState.idle) {
          onCommand(endpoints.leftId, ControlState.idle);
          if (endpoints.rightId != endpoints.leftId) {
            onCommand(endpoints.rightId, ControlState.idle);
          }
          return;
        }
        onCommand(isLeft ? endpoints.leftId : endpoints.rightId, state);
      },
    );
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
  _traverseEndpointsFor(ButtonConfig config) {
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
