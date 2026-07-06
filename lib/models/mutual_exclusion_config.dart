import 'package:rev_crane_control_ops/models/control_role.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MutualExclusionConfig
//
// Per-button mutual-exclusion / inclusive-pairing rule set. Replaces
// ControlRoleInfo.pairedRole's hardcoded, structurally-enforced pairing with
// a configurable-but-safely-defaulted equivalent (see
// MutualExclusionDefaults below) — pairedRole itself is untouched and still
// used as the seed source here and by the legacy axis path.
// ─────────────────────────────────────────────────────────────────────────────

class MutualExclusionConfig {
  const MutualExclusionConfig({
    this.excludedButtonIds = const <String>{},
    this.inclusiveButtonIds = const <String>{},
  });

  /// Buttons that must be forced idle/disabled while this button is active
  /// (safety interlock — e.g. hoistUp excludes hoistDown). Seeding writes
  /// both directions (see [MutualExclusionDefaults]) so a single button's
  /// config is sufficient to read the relationship without cross-referencing
  /// its partner.
  final Set<String> excludedButtonIds;

  /// Buttons explicitly PERMITTED (not required) to be active simultaneously
  /// with this one. Mostly informational today; modeled as a real set so a
  /// future combined-motion validator can consult it instead of just
  /// "not excluded = allowed."
  final Set<String> inclusiveButtonIds;

  bool excludes(String buttonId) => excludedButtonIds.contains(buttonId);

  MutualExclusionConfig copyWith({
    Set<String>? excludedButtonIds,
    Set<String>? inclusiveButtonIds,
  }) {
    return MutualExclusionConfig(
      excludedButtonIds: excludedButtonIds ?? this.excludedButtonIds,
      inclusiveButtonIds: inclusiveButtonIds ?? this.inclusiveButtonIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'excludedButtonIds': excludedButtonIds.toList(),
    'inclusiveButtonIds': inclusiveButtonIds.toList(),
  };

  factory MutualExclusionConfig.fromJson(Map<String, dynamic> json) {
    Set<String> readSet(String key) => ((json[key] as List?) ?? const [])
        .map((e) => e.toString())
        .toSet();
    return MutualExclusionConfig(
      excludedButtonIds: readSet('excludedButtonIds'),
      inclusiveButtonIds: readSet('inclusiveButtonIds'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MutualExclusionConfig &&
          _setEquals(other.excludedButtonIds, excludedButtonIds) &&
          _setEquals(other.inclusiveButtonIds, inclusiveButtonIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(excludedButtonIds),
    Object.hashAllUnordered(inclusiveButtonIds),
  );
}

bool _setEquals(Set<String> a, Set<String> b) {
  if (a.length != b.length) return false;
  return a.containsAll(b);
}

// ─────────────────────────────────────────────────────────────────────────────
// MutualExclusionDefaults
// ─────────────────────────────────────────────────────────────────────────────

extension MutualExclusionDefaults on ControlRole {
  /// The DEFAULT exclusion set for this role's button id, seeded from
  /// today's hardware-mandated pairing (ControlRoleInfo.pairedRole). This is
  /// what a brand-new/migrated ButtonConfig ships with; the user can edit or
  /// clear it afterward via the BEHAVIOR tab (with a confirmation warning
  /// when removing a same-axis opposite-direction exclusion — see
  /// ButtonEditSheet's BEHAVIOR tab).
  MutualExclusionConfig get defaultMutualExclusion {
    final paired = pairedRole;
    return MutualExclusionConfig(
      excludedButtonIds: paired != null ? {paired.name} : const {},
    );
  }
}
