import 'package:rev_crane_control_ops/models/plc_mapping.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ButtonStateOutputMapping
//
// Maps one logical button state (e.g. 'idle', 'active', 'step1', 'zone1') to
// the set of PLC output variants that state activates. This is the ONLY
// thing that determines what a button's non-idle state asserts on the wire —
// no ControlRole/AxisKind derivation is consulted at composition time.
// Master invariant: no output variant is ever activated except by an
// explicit entry the user configured here for that exact state.
// ─────────────────────────────────────────────────────────────────────────────

class ButtonStateOutputMapping {
  const ButtonStateOutputMapping({
    required this.stateId,
    this.activeVariants = const <PlcMapping>{},
  });

  final String stateId;

  /// Never contains PlcMapping.estop — enforced here (isValid) and again in
  /// fromJson, which silently drops an estop entry rather than trusting a
  /// hand-edited/corrupted JSON value. E-STOP stays controller-only.
  final Set<PlcMapping> activeVariants;

  bool get isValid => !activeVariants.contains(PlcMapping.estop);

  ButtonStateOutputMapping copyWith({
    String? stateId,
    Set<PlcMapping>? activeVariants,
  }) {
    return ButtonStateOutputMapping(
      stateId: stateId ?? this.stateId,
      activeVariants: activeVariants ?? this.activeVariants,
    );
  }

  Map<String, dynamic> toJson() => {
    'stateId': stateId,
    // Serialized as PlcMapping.name strings (e.g. 'up'), not 'DFN' —
    // variantId/genericLabel are pure display concerns decoupled from
    // storage, so renaming the display convention never requires a
    // migration of persisted layouts.
    'activeVariants': activeVariants.map((v) => v.name).toList(),
  };

  factory ButtonStateOutputMapping.fromJson(Map<String, dynamic> json) {
    final rawVariants = (json['activeVariants'] as List?) ?? const [];
    final variants = <PlcMapping>{};
    for (final raw in rawVariants) {
      final name = raw.toString();
      for (final mapping in PlcMapping.values) {
        if (mapping.name == name) {
          // estop is structurally excluded even from corrupted/hand-edited
          // JSON — never smuggled into a button's activeVariants.
          if (mapping != PlcMapping.estop) variants.add(mapping);
          break;
        }
      }
    }
    return ButtonStateOutputMapping(
      stateId: json['stateId'] as String,
      activeVariants: variants,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonStateOutputMapping &&
          other.stateId == stateId &&
          other.activeVariants.length == activeVariants.length &&
          other.activeVariants.containsAll(activeVariants);

  @override
  int get hashCode =>
      Object.hash(stateId, Object.hashAllUnordered(activeVariants));
}
