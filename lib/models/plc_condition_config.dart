import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlcConditionCombinator / PlcConditionConfig
//
// Shared trigger-condition bag for PLC-status-DRIVEN feedback widgets (horn/
// buzzer, alarm indicator). These widgets never emit a PLC command — they
// only ever READ the live composed PlcOutputCommand (via
// CraneController.isFieldActive, see crane_controllers.dart) and decide
// whether their configured condition over [watchedFields] is currently true.
//
// "If DF2 is ON" -> watchedFields = {DF2}, combinator = any (or all, with one
// field they're equivalent).
// "If DF5 AND DF6 are ON" -> watchedFields = {DF5, DF6}, combinator = all.
// "If any of DF5, DF6 is ON" -> same fields, combinator = any.
// ─────────────────────────────────────────────────────────────────────────────

enum PlcConditionCombinator { any, all }

class PlcConditionConfig {
  const PlcConditionConfig({
    this.watchedFields = const <PlcOutputVariant>{},
    this.combinator = PlcConditionCombinator.any,
  });

  static const String customPropertiesKey = 'plcCondition';

  /// Never contains PlcOutputVariant.df1 — a feedback widget triggering off
  /// E-STOP directly would be a confusing secondary alarm channel for a
  /// condition that already has its own dedicated, protected UI everywhere
  /// else in the app. Enforced in normalized() and fromJson.
  final Set<PlcOutputVariant> watchedFields;
  final PlcConditionCombinator combinator;

  bool get hasCondition => watchedFields.isNotEmpty;

  /// Evaluates this condition against a live field-lookup callback (normally
  /// `CraneController.isFieldActive`). An empty [watchedFields] set is
  /// always inactive — an unconfigured feedback widget is inert, never
  /// "always on" by default.
  bool isActive(bool Function(PlcOutputVariant) fieldValue) {
    if (watchedFields.isEmpty) return false;
    return combinator == PlcConditionCombinator.all
        ? watchedFields.every(fieldValue)
        : watchedFields.any(fieldValue);
  }

  PlcConditionConfig normalized() {
    return PlcConditionConfig(
      watchedFields: watchedFields
          .where((m) => m != PlcOutputVariant.df1)
          .toSet(),
      combinator: combinator,
    );
  }

  PlcConditionConfig copyWith({
    Set<PlcOutputVariant>? watchedFields,
    PlcConditionCombinator? combinator,
  }) {
    return PlcConditionConfig(
      watchedFields: watchedFields ?? this.watchedFields,
      combinator: combinator ?? this.combinator,
    ).normalized();
  }

  PlcConditionConfig toggleField(PlcOutputVariant mapping) {
    final next = Set<PlcOutputVariant>.from(watchedFields);
    if (!next.add(mapping)) next.remove(mapping);
    return copyWith(watchedFields: next);
  }

  Map<String, dynamic> toJson() => {
    'watchedFields': watchedFields.map((m) => m.storageKey).toList(),
    'combinator': combinator.name,
  };

  factory PlcConditionConfig.fromJson(Map<String, dynamic> json) {
    final rawFields = (json['watchedFields'] as List?) ?? const [];
    final fields = <PlcOutputVariant>{};
    for (final raw in rawFields) {
      final variant = PlcOutputVariant.fromStorageKey(raw);
      if (variant != null && variant != PlcOutputVariant.df1) {
        fields.add(variant);
      }
    }
    return PlcConditionConfig(
      watchedFields: fields,
      combinator: PlcConditionCombinator.values.firstWhere(
        (e) => e.name == json['combinator'],
        orElse: () => PlcConditionCombinator.any,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlcConditionConfig &&
          other.combinator == combinator &&
          other.watchedFields.length == watchedFields.length &&
          other.watchedFields.containsAll(watchedFields);

  @override
  int get hashCode =>
      Object.hash(combinator, Object.hashAllUnordered(watchedFields));
}
