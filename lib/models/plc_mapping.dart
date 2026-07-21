import 'package:rev_crane_control_ops/models/control_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlcMapping
//
// Closed enum over the 10 existing PlcOutputCommand boolean fields — the
// generic PLC packet [DF1, DF2, DF3, DF4, DF5, DF6, DF7, DF8, DF9, DF10],
// where DF1 is fixed for E-STOP. This is the extension point for a future
// non-boolean wire-protocol change (needed for joystick/rotary/analog
// controls, which the current ASCII CSV format cannot carry) — deliberately
// NOT stringly-typed / open-ended today. Every ButtonConfig maps to exactly
// one of these; the closed set means a button can never be wired to an
// arbitrary/unsupported PLC output, mirroring the same safety guarantee
// ControlRole already provides.
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

  /// Generic wire-position identity: 'DF1'..'DF10' ("Data Field N"), 1:1
  /// with this enum's declared index (index 0 = DF1 = estop). This is a pure
  /// display/config alias — PlcMapping itself stays the closed safety enum;
  /// variantId lets the rest of the app speak generic "DF2".."DF10"
  /// PLC-output-variant naming instead of crane-specific field names,
  /// without a second enum.
  String get variantId => 'DF${index + 1}';

  /// True for DF2..DF10 — the user-configurable output variants. False only
  /// for estop, which stays fixed/protected and is never user-remappable.
  bool get isUserConfigurable => this != PlcMapping.estop;

  /// Generic display label shown in configuration UI, e.g. "DF1 / E-STOP",
  /// "DF2". Supersedes the old semantic per-role labels ("Hoist Up", etc.)
  /// for user-facing text now that buttons are no longer crane-specific.
  String get genericLabel =>
      this == PlcMapping.estop ? 'DF1 / E-STOP' : variantId;

  /// Resolves a generic variant id string (e.g. 'DF6') back to its
  /// PlcMapping, or null if [id] doesn't match any known variant.
  static PlcMapping? fromVariantId(String id) {
    for (final mapping in PlcMapping.values) {
      if (mapping.variantId == id) return mapping;
    }
    return null;
  }
}
