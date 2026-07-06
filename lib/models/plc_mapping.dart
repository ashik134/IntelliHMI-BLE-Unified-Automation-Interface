import 'package:rev_crane_control_ops/models/control_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlcMapping
//
// Closed enum over the 10 existing PlcOutputCommand boolean fields. This is
// the extension point for a future non-boolean wire-protocol change (needed
// for joystick/rotary/analog controls, which the current ASCII CSV format
// cannot carry) — deliberately NOT stringly-typed / open-ended today. Every
// ButtonConfig maps to exactly one of these; the closed set means a button
// can never be wired to an arbitrary/unsupported PLC output, mirroring the
// same safety guarantee ControlRole already provides.
// ─────────────────────────────────────────────────────────────────────────────

enum PlcMapping {
  estop,
  up,
  down,
  fastUd,
  left,
  right,
  fastLr,
  forward,
  reverse,
  fastFb,
}

extension PlcMappingInfo on PlcMapping {
  /// The ControlRole this field corresponds to 1:1, or null for the two
  /// speed-only "fast" flags, which have no independent role.
  ControlRole? get correspondingRole => switch (this) {
    PlcMapping.estop => ControlRole.estop,
    PlcMapping.up => ControlRole.hoistUp,
    PlcMapping.down => ControlRole.hoistDown,
    PlcMapping.left => ControlRole.traverseLeft,
    PlcMapping.right => ControlRole.traverseRight,
    PlcMapping.forward => ControlRole.travelForward,
    PlcMapping.reverse => ControlRole.travelReverse,
    PlcMapping.fastUd || PlcMapping.fastLr || PlcMapping.fastFb => null,
  };
}
