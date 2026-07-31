import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlRole
//
// Fixed identity of the two safety controls every layout always has. This is
// the safety boundary between what the operator can customize (label,
// appearance, control type, PLC output mapping) and what is hardwired: which
// PlcOutputVariant field E-STOP fires, and that E-STOP/Reset are never
// deletable or restylable. Every other control on the app is a fully generic
// ButtonConfig with no fixed role — its behavior comes entirely from its own
// stateMappings.
// ─────────────────────────────────────────────────────────────────────────────

enum ControlRole { estop, resetEstop }

extension ControlRoleInfo on ControlRole {
  String get defaultLabel => switch (this) {
    ControlRole.estop => 'STOP',
    ControlRole.resetEstop => 'RESET',
  };

  /// The PlcOutputCommand field this role drives. `resetEstop` has no field
  /// of its own (it's a controller-level action — CraneController.resetEStop
  /// — not a composed packet bit), so it maps to null.
  PlcOutputVariant? get plcMapping => switch (this) {
    ControlRole.estop => PlcOutputVariant.df1,
    ControlRole.resetEstop => null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Joystick virtual sub-buttons
//
// A joystick asserts up to 4 independent PLC fields (dual-axis) or 2
// (single-axis) without any of them being a real, addressable ButtonConfig of
// its own. Each direction gets a stable virtual id so
// ButtonConfig.joystickSubButtonMappings can be keyed consistently across
// renders. The direction identity itself carries no PLC meaning — the actual
// field(s) asserted for a direction come entirely from that map's
// stateMappings, resolved the same way any other button's stateMappings is.
// ─────────────────────────────────────────────────────────────────────────────

enum JoystickDirection { posX, negX, posY, negY }

const String kJoystickVirtualButtonPrefix = 'joystick';

String joystickVirtualButtonId(
  String sourceButtonId,
  JoystickDirection direction,
) => '$kJoystickVirtualButtonPrefix:$sourceButtonId:${direction.name}';

/// Returns the [JoystickDirection] encoded in [buttonId] if it's a joystick
/// virtual sub-button id, else null.
JoystickDirection? joystickDirectionFor(String buttonId) {
  final parts = buttonId.split(':');
  if (parts.length != 3 || parts.first != kJoystickVirtualButtonPrefix) {
    return null;
  }
  for (final direction in JoystickDirection.values) {
    if (direction.name == parts.last) return direction;
  }
  return null;
}
