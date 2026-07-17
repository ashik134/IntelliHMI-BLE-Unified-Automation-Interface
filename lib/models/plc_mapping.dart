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

  /// Generic wire-position identity: 'a1'..'a10', 1:1 with this enum's
  /// declared index (index 0 = a1 = estop). This is a pure display/config
  /// alias — PlcMapping itself stays the closed safety enum; variantId lets
  /// the rest of the app speak generic "a2".."a10" PLC-output-variant
  /// naming instead of crane-specific field names, without a second enum.
  String get variantId => 'a${index + 1}';

  /// True for a2..a10 — the user-configurable output variants. False only
  /// for estop, which stays fixed/protected and is never user-remappable.
  bool get isUserConfigurable => this != PlcMapping.estop;

  /// Generic display label shown in configuration UI, e.g. "A1 / E-STOP",
  /// "A2". Supersedes the old semantic per-role labels ("Hoist Up", etc.)
  /// for user-facing text now that buttons are no longer crane-specific.
  String get genericLabel =>
      this == PlcMapping.estop ? 'A1 / E-STOP' : variantId.toUpperCase();

  /// Resolves a generic variant id string (e.g. 'a6') back to its
  /// PlcMapping, or null if [id] doesn't match any known variant.
  static PlcMapping? fromVariantId(String id) {
    for (final mapping in PlcMapping.values) {
      if (mapping.variantId == id) return mapping;
    }
    return null;
  }
}
