import 'package:rev_crane_control_ops/models/button_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonLogicalState / ButtonTypeLogicalStates
//
// Declares the fixed state-id list + human labels for each ButtonType. State
// COUNT/IDENTITY is type-determined (this table) — state OUTPUT is entirely
// user-determined (ButtonConfig.stateMappings). An `isIdle` state's
// activeVariants are always forced to {} and rendered non-editable in the
// edit sheet: an idle/center state that could assert arbitrary outputs would
// be a safety footgun ("never truly off").
//
// Cross-travel's 5 (or 3) zones are each their OWN independently-mappable
// state — never collapsed into borrowed 'slow'/'fast' speed labels, which
// would smuggle speed semantics back into what must be a fully generic
// mapping. See CrossTravelStrategy/CrossTravelSlowOnlyStrategy for the
// gesture-to-zone-id resolution (crossTravelZoneId).
// ─────────────────────────────────────────────────────────────────────────────

class ButtonLogicalState {
  const ButtonLogicalState({
    required this.id,
    required this.label,
    required this.isIdle,
  });

  /// Stable storage key used as ButtonConfig.stateMappings' key. Never
  /// renamed even if the display label changes.
  final String id;

  final String label;

  /// True => activeVariants forced to {} everywhere (composer + UI), since
  /// idle/center must always be inert.
  final bool isIdle;
}

extension ButtonTypeLogicalStates on ButtonType {
  List<ButtonLogicalState> get logicalStates => switch (this) {
    ButtonType.pushButton => const [
      ButtonLogicalState(id: 'idle', label: 'Idle / Off', isIdle: true),
      ButtonLogicalState(id: 'active', label: 'Active / On', isIdle: false),
    ],
    ButtonType.toggle => const [
      ButtonLogicalState(id: 'left', label: 'Left', isIdle: false),
      ButtonLogicalState(id: 'center', label: 'Center / Idle', isIdle: true),
      ButtonLogicalState(id: 'right', label: 'Right', isIdle: false),
    ],
    ButtonType.sliderButton => const [
      ButtonLogicalState(id: 'idle', label: 'Center / Idle', isIdle: true),
      ButtonLogicalState(id: 'step1', label: 'Step 1', isIdle: false),
      ButtonLogicalState(id: 'step2', label: 'Step 2', isIdle: false),
    ],
    // Each of the 5 zones is its own independently-configurable state.
    // zone1/zone2 = left side (far/near), center = idle,
    // zone4/zone5 = right side (near/far) — see crossTravelZoneId.
    ButtonType.crossTravel => const [
      ButtonLogicalState(id: 'zone1', label: 'Zone 1', isIdle: false),
      ButtonLogicalState(id: 'zone2', label: 'Zone 2', isIdle: false),
      ButtonLogicalState(id: 'center', label: 'Center / Idle', isIdle: true),
      ButtonLogicalState(id: 'zone4', label: 'Zone 4', isIdle: false),
      ButtonLogicalState(id: 'zone5', label: 'Zone 5', isIdle: false),
    ],
    ButtonType.crossTravelSlowOnly => const [
      ButtonLogicalState(id: 'zone1', label: 'Zone 1', isIdle: false),
      ButtonLogicalState(id: 'center', label: 'Center / Idle', isIdle: true),
      ButtonLogicalState(id: 'zone3', label: 'Zone 3', isIdle: false),
    ],
    // The joystick's OWN stateMappings are unused for direct composition —
    // it decomposes into up to 4 independent virtual per-direction
    // sub-buttons at runtime, each shaped like a slider (idle/step1/step2).
    // Listed here for completeness / potential future direct use only.
    ButtonType.joystick => const [
      ButtonLogicalState(id: 'idle', label: 'Center / Idle', isIdle: true),
      ButtonLogicalState(id: 'step1', label: 'Step 1', isIdle: false),
      ButtonLogicalState(id: 'step2', label: 'Step 2', isIdle: false),
    ],
  };
}

/// Shared "3-state" logical states (idle/step1/step2) used both by
/// sliderButton's own ButtonConfig and by joystick's virtual per-direction
/// sub-buttons, which are not real ButtonConfigs but still need the same
/// state-id shape for their own stateMappings-equivalent table.
const List<ButtonLogicalState> kThreeStepLogicalStates = [
  ButtonLogicalState(id: 'idle', label: 'Center / Idle', isIdle: true),
  ButtonLogicalState(id: 'step1', label: 'Step 1', isIdle: false),
  ButtonLogicalState(id: 'step2', label: 'Step 2', isIdle: false),
];
