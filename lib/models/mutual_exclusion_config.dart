// ─────────────────────────────────────────────────────────────────────────────
// MutualExclusionConfig
//
// Per-button mutual-exclusion / inclusive-pairing rule set. A new generic
// button ships with an empty config by default; a legacy migrated button
// keeps whatever pairing legacy_layout_migration.dart baked in for it.
// ─────────────────────────────────────────────────────────────────────────────

class MutualExclusionConfig {
  const MutualExclusionConfig({
    this.excludedButtonIds = const <String>{},
    this.inclusiveButtonIds = const <String>{},
  });

  /// Buttons that must be forced idle/disabled while this button is active
  /// (safety interlock — e.g. two opposite-direction outputs that must never
  /// both be asserted). A symmetric pairing should write both directions so
  /// a single button's config is sufficient to read the relationship without
  /// cross-referencing its partner.
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
    Set<String> readSet(String key) =>
        ((json[key] as List?) ?? const []).map((e) => e.toString()).toSet();
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
