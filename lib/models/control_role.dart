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
    ControlRole.traverseLeft ||
    ControlRole.traverseRight => AxisKind.traverse,
    ControlRole.travelForward ||
    ControlRole.travelReverse => AxisKind.travel,
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
}
