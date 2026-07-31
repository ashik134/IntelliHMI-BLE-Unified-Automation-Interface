import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/role_appearance.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MultiZoneSliderStrategy (Bidirectional5StepStrategy / Bidirectional3StepStrategy)
//
// Two ways this strategy builds MultiZoneSliderButton, kept deliberately
// isolated from one another:
//

/// Exhaustive truth table (5-zone):
///   isLeftButton=true,  idle -> center
///   isLeftButton=true,  slow -> zone2
///   isLeftButton=true,  fast -> zone1
///   isLeftButton=false, idle -> center
///   isLeftButton=false, slow -> zone4
///   isLeftButton=false, fast -> zone5
///
/// Exhaustive truth table (3-zone, [fiveZone]=false — MultiZoneSliderButton
/// never emits ControlState.fast in this variant, but the arm is still
/// written out explicitly rather than defaulted, so a future widget change
/// can't silently misroute a fast zone through an untested path):
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
/// [MultiZoneSliderButton.onStateChanged] into which side it belongs to and
/// the legacy [ControlState] the paired path's pipeline (onCommand ->
/// resolveButtonCommand -> crossTravelZoneId) still expects to see. Written
/// out exhaustively for the same reason as crossTravelZoneId itself: a zone
/// id this table doesn't recognize is a programming error, never silently
/// coerced to centre/idle. Only used by the LEGACY PAIRED path — the generic
/// path dispatches the zone id straight through, untranslated.
({bool isLeftButton, ControlState state}) zoneIdToSideAndState({
  required String zoneId,
  required bool fiveZone,
}) {
  if (!fiveZone) {
    return switch (zoneId) {
      MultiZoneSliderStateId.center => (
        isLeftButton: true,
        state: ControlState.idle,
      ),
      MultiZoneSliderStateId.zone1 => (
        isLeftButton: true,
        state: ControlState.slow,
      ),
      MultiZoneSliderStateId.zone3 => (
        isLeftButton: false,
        state: ControlState.slow,
      ),
      _ => throw ArgumentError.value(zoneId, 'zoneId', 'Unknown 3-zone id'),
    };
  }
  return switch (zoneId) {
    MultiZoneSliderStateId.center => (
      isLeftButton: true,
      state: ControlState.idle,
    ),
    MultiZoneSliderStateId.zone1 => (
      isLeftButton: true,
      state: ControlState.fast,
    ),
    MultiZoneSliderStateId.zone2 => (
      isLeftButton: true,
      state: ControlState.slow,
    ),
    MultiZoneSliderStateId.zone4 => (
      isLeftButton: false,
      state: ControlState.slow,
    ),
    MultiZoneSliderStateId.zone5 => (
      isLeftButton: false,
      state: ControlState.fast,
    ),
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
    // Generic path: a free-standing button (no ControlRole) placed anywhere
    // in the grid. See the class-level doc comment.
    if (config.role == null) {
      return buildGenericMultiZoneSlider(
        context: context,
        config: config,
        isDisabled: isDisabled,
        onStateIdCommand: onStateIdCommand,
        fiveZone: true,
      );
    }

    // Legacy paired path — no sibling config available through the uniform
    // interface — renders using config's own label for both sides as a
    // reasonable single-config fallback. Screens with both LEFT/RIGHT
    // configs available should call buildPaired instead (see
    // plc38_control_screen.dart's traverse axis).
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
      rotation: config.rotation,
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
  /// `onStateChanged(zoneId)` callback into two independent
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
    ButtonRotation rotation = ButtonRotation.none,
  }) {
    return MultiZoneSliderButton(
      startLabel: leftLabel,
      endLabel: rightLabel,
      startIcon: iconForRole(ControlRole.traverseLeft),
      endIcon: iconForRole(ControlRole.traverseRight),
      isDisabled: isDisabled,
      isStartZoneBlocked: isLeftZoneBlocked,
      isEndZoneBlocked: isRightZoneBlocked,
      // Explicit traverse theming for the crane role pairing — the widget's
      // own default is intentionally neutral (see MultiZoneSliderButton doc
      // comment) for freestanding/generic sliders.
      nearColor: AppColors.traverseColor,
      rotation: rotation,
      onStateChanged: (zoneId) {
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
    // Generic path: a free-standing button (no ControlRole) placed anywhere
    // in the grid. See the class-level doc comment on Bidirectional5StepStrategy.
    if (config.role == null) {
      return buildGenericMultiZoneSlider(
        context: context,
        config: config,
        isDisabled: isDisabled,
        onStateIdCommand: onStateIdCommand,
        fiveZone: false,
      );
    }

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
      startIcon: iconForRole(ControlRole.traverseLeft),
      endIcon: iconForRole(ControlRole.traverseRight),
      isDisabled: isDisabled,
      isStartZoneBlocked: isLeftZoneBlocked,
      isEndZoneBlocked: isRightZoneBlocked,
      variant: MultiZoneSliderVariant.threeZone,
      // See buildPaired's identical comment above.
      nearColor: AppColors.traverseColor,
      rotation: config.rotation,
      onStateChanged: (zoneId) {
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
// Generic (non-paired) build path — shared by both strategies
// ─────────────────────────────────────────────────────────────────────────────

/// Builds a free-standing MultiZoneSliderButton for [config] when it has no
/// ControlRole: a single ButtonConfig owns every zone directly through its
/// own stateMappings, dispatched via [onStateIdCommand] with the widget's
/// raw zone id — no crossTravelZoneId translation, no left/right pairing.
/// This is what makes the control genuinely "usable anywhere in the control
/// grid" rather than tied to the crane's traverse axis.
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

  return MultiZoneSliderButton(
    startLabel: config.label,
    endLabel: config.label,
    startIcon: config.icon ?? Icons.arrow_back_rounded,
    endIcon: config.icon ?? Icons.arrow_forward_rounded,
    isDisabled: isDisabled,
    variant: fiveZone
        ? MultiZoneSliderVariant.fiveZone
        : MultiZoneSliderVariant.threeZone,
    rotation: config.rotation,
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
