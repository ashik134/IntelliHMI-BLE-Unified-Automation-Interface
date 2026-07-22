import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

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
    this.activeVariants = const <PlcOutputVariant>{},
  });

  final String stateId;

  /// Never contains PlcOutputVariant.df1 — enforced here (isValid) and again in
  /// fromJson, which silently drops a DF1/E-STOP entry rather than trusting a
  /// hand-edited/corrupted JSON value. E-STOP stays controller-only.
  final Set<PlcOutputVariant> activeVariants;

  bool get isValid => !activeVariants.contains(PlcOutputVariant.df1);

  ButtonStateOutputMapping copyWith({
    String? stateId,
    Set<PlcOutputVariant>? activeVariants,
  }) {
    return ButtonStateOutputMapping(
      stateId: stateId ?? this.stateId,
      activeVariants: activeVariants ?? this.activeVariants,
    );
  }

  Map<String, dynamic> toJson() => {
    'stateId': stateId,
    'activeVariants': activeVariants.map((v) => v.storageKey).toList(),
  };

  factory ButtonStateOutputMapping.fromJson(Map<String, dynamic> json) {
    final rawVariants = (json['activeVariants'] as List?) ?? const [];
    final variants = <PlcOutputVariant>{};
    for (final raw in rawVariants) {
      final variant = PlcOutputVariant.fromStorageKey(raw);
      if (variant != null && variant != PlcOutputVariant.df1) {
        variants.add(variant);
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
