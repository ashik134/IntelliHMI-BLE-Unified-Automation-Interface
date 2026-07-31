import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlRole / AxisKind
//
// Fixed semantic identity of every physical control on the crane HMI. This is
// the safety boundary between what the operator can customize (label,
// appearance, control type) and what is hardwired (which PlcOutputCommand
// boolean field fires). There is deliberately no generic/open-ended role —
// a button can never be rebound to an arbitrary PLC output.
// ─────────────────────────────────────────────────────────────────────────────

enum ControlRole {
  hoistUp,
  hoistDown,
  traverseLeft,
  traverseRight,
  travelForward,
  travelReverse,
  estop,
  resetEstop,
}

/// The three independently-configurable motion axes. PLC14/PLC21 only ever
/// render [hoist]; PLC38 renders all three.
enum AxisKind { hoist, traverse, travel }

extension ControlRoleInfo on ControlRole {
  /// The axis this role belongs to, or null for estop/resetEstop.
  AxisKind? get axis => switch (this) {
    ControlRole.hoistUp || ControlRole.hoistDown => AxisKind.hoist,
    ControlRole.traverseLeft || ControlRole.traverseRight => AxisKind.traverse,
    ControlRole.travelForward || ControlRole.travelReverse => AxisKind.travel,
    ControlRole.estop || ControlRole.resetEstop => null,
  };

  /// True for the six axis buttons; false for estop/resetEstop.
  bool get isMotionControl => axis != null;

  /// True for estop/resetEstop — always visible, never deletable, never
  /// wrapped in an editing overlay, appearance not customizable.
  bool get isSafetyControl => !isMotionControl;

  /// The opposite-direction role on the same axis. Informational only — the
  /// pairing is hardware-enforced (mutual exclusion) and never user-editable.
  ControlRole? get pairedRole => switch (this) {
    ControlRole.hoistUp => ControlRole.hoistDown,
    ControlRole.hoistDown => ControlRole.hoistUp,
    ControlRole.traverseLeft => ControlRole.traverseRight,
    ControlRole.traverseRight => ControlRole.traverseLeft,
    ControlRole.travelForward => ControlRole.travelReverse,
    ControlRole.travelReverse => ControlRole.travelForward,
    ControlRole.estop || ControlRole.resetEstop => null,
  };

  String get defaultLabel => switch (this) {
    ControlRole.hoistUp => 'UP',
    ControlRole.hoistDown => 'DOWN',
    ControlRole.traverseLeft => 'LEFT',
    ControlRole.traverseRight => 'RIGHT',
    ControlRole.travelForward => 'FWD',
    ControlRole.travelReverse => 'REV',
    ControlRole.estop => 'STOP',
    ControlRole.resetEstop => 'RESET E-STOP',
  };

  /// The PlcOutputCommand field this role drives. `resetEstop` has no field
  /// of its own (it's a controller-level action — CraneController.resetEStop
  /// — not a composed packet bit), so it maps to null.
  PlcOutputVariant? get plcMapping => switch (this) {
    ControlRole.hoistUp => PlcOutputVariant.df2,
    ControlRole.hoistDown => PlcOutputVariant.df3,
    ControlRole.traverseLeft => PlcOutputVariant.df5,
    ControlRole.traverseRight => PlcOutputVariant.df6,
    ControlRole.travelForward => PlcOutputVariant.df8,
    ControlRole.travelReverse => PlcOutputVariant.df9,
    ControlRole.estop => PlcOutputVariant.df1,
    ControlRole.resetEstop => null,
  };
}

extension AxisKindInfo on AxisKind {
  ControlRole get primaryRole => switch (this) {
    AxisKind.hoist => ControlRole.hoistUp,
    AxisKind.traverse => ControlRole.traverseLeft,
    AxisKind.travel => ControlRole.travelForward,
  };

  ControlRole get secondaryRole => switch (this) {
    AxisKind.hoist => ControlRole.hoistDown,
    AxisKind.traverse => ControlRole.traverseRight,
    AxisKind.travel => ControlRole.travelReverse,
  };

  String get displayName => switch (this) {
    AxisKind.hoist => 'HOIST',
    AxisKind.traverse => 'TRAVERSE',
    AxisKind.travel => 'TRAVEL',
  };

  /// The PLC speed-modifier field for this axis.
  PlcOutputVariant get fastMapping => switch (this) {
    AxisKind.hoist => PlcOutputVariant.df4,
    AxisKind.traverse => PlcOutputVariant.df7,
    AxisKind.travel => PlcOutputVariant.df10,
  };
}

extension PlcOutputVariantLegacyRoleInfo on PlcOutputVariant {
  /// Legacy role lookup used only while migrating older role-derived defaults
  /// into explicit per-state DF output mappings.
  ControlRole? get correspondingRole => switch (this) {
    PlcOutputVariant.df1 => ControlRole.estop,
    PlcOutputVariant.df2 => ControlRole.hoistUp,
    PlcOutputVariant.df3 => ControlRole.hoistDown,
    PlcOutputVariant.df5 => ControlRole.traverseLeft,
    PlcOutputVariant.df6 => ControlRole.traverseRight,
    PlcOutputVariant.df8 => ControlRole.travelForward,
    PlcOutputVariant.df9 => ControlRole.travelReverse,
    PlcOutputVariant.df4 ||
    PlcOutputVariant.df7 ||
    PlcOutputVariant.df10 => null,
  };
}

/// Virtual button-state keys used by the independent 3-zone cross-travel
/// sliders to assert the DF7 PLC field without activating either
/// direction bit. These are NOT [ButtonConfig] IDs — they exist only in
/// [CraneController]'s runtime button-state map and in
/// [Bidirectional3StepStrategy]'s command dispatch. Each slider owns its
/// own key so that one releasing does not clear the other's contribution.
const String kTraverseLeftFastKey = 'traverseLeftFast';
const String kTraverseRightFastKey = 'traverseRightFast';

/// Maps every virtual fast-key button ID to the single PLC field it asserts.
/// CraneController._fieldsFor and Bidirectional3StepStrategy both consult
/// this table so the mapping is defined in one place.
const Map<String, PlcOutputVariant> kVirtualFastKeyFields = {
  kTraverseLeftFastKey: PlcOutputVariant.df7,
  kTraverseRightFastKey: PlcOutputVariant.df7,
};

/// The only non-idle logical state a virtual fast-key ever reaches — these
/// keys are simple two-state (idle/active) pseudo-buttons.
const String kVirtualFastKeyActiveState = 'active';

/// Migrated stateMappings-shaped table for the virtual fast-assist keys,
/// baked in as static data (NOT derived live) reproducing exactly what
/// these keys have always asserted: idle -> {}, active -> {their one PLC
/// field}. This is not an "automatic derivation" — a virtual fast-key has
/// only ever had one possible meaning (asserting its own fixed field), so
/// there is no other field it could silently add. CraneController._fieldsFor
/// consults this table for virtual fast-key ids exactly like it consults a
/// real ButtonConfig.stateMappings for a real button id.
final Map<String, Map<String, ButtonStateOutputMapping>>
kVirtualFastKeyStateMappings = {
  for (final entry in kVirtualFastKeyFields.entries)
    entry.key: {
      'idle': const ButtonStateOutputMapping(stateId: 'idle'),
      kVirtualFastKeyActiveState: ButtonStateOutputMapping(
        stateId: kVirtualFastKeyActiveState,
        activeVariants: {entry.value},
      ),
    },
};

/// Virtual button-state keys used by a joystick to own several PLC fields
/// without borrowing another visible button's [ControlRole.name] key.
const String kJoystickVirtualButtonPrefix = 'joystick';

String joystickVirtualButtonId(String sourceButtonId, PlcOutputVariant field) =>
    '$kJoystickVirtualButtonPrefix:$sourceButtonId:${field.storageKey}';

PlcOutputVariant? joystickVirtualFieldFor(String buttonId) {
  final parts = buttonId.split(':');
  if (parts.length != 3 || parts.first != kJoystickVirtualButtonPrefix) {
    return null;
  }
  return PlcOutputVariant.fromStorageKey(parts.last);
}
