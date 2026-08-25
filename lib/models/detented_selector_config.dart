// ─────────────────────────────────────────────────────────────────────────────
// DetentedSelectorConfig / SelectorPosition
//
// Backs ButtonType.detentedSelector — a rotary selector switch with N fixed,
// hard detent positions (operator-configurable count), each independently
// labeled/iconed and independently mapped to PLC output variants via the
// normal ButtonConfig.stateMappings table (see button_logical_state.dart's
// doc comment on why this type is special-cased there instead of using a
// fixed ButtonLogicalState list: the position count is per-instance data,
// not a compile-time constant of the type).
//
// SelectorPosition.id is the stable stateMappings key for that position —
// generated once when the position is created (see
// DetentedSelectorConfig.withAddedPosition) and never re-derived from index,
// so reordering or deleting a middle position never reassigns another
// position's PLC mapping.
// ─────────────────────────────────────────────────────────────────────────────

class SelectorPosition {
  const SelectorPosition({required this.id, this.label, this.iconKey});

  /// Stable storage key — see file doc comment. Never renamed.
  final String id;

  final String? label;

  /// Icon-registry key (see button_icon_registry.dart) — never a raw
  /// IconData, for the same JSON round-trip reason every other per-item icon
  /// field in this codebase uses a key (see ToggleButtonConfig.leftIconKey).
  final String? iconKey;

  SelectorPosition copyWith({
    String? label,
    String? iconKey,
    bool clearLabel = false,
    bool clearIconKey = false,
  }) {
    return SelectorPosition(
      id: id,
      label: clearLabel ? null : (label ?? this.label),
      iconKey: clearIconKey ? null : (iconKey ?? this.iconKey),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'iconKey': iconKey};

  factory SelectorPosition.fromJson(Map<String, dynamic> json) {
    return SelectorPosition(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? json['id'] as String
          : 'pos_${identityHashCode(json)}',
      label: _cleanNullable(json['label'] as String?),
      iconKey: _cleanNullable(json['iconKey'] as String?),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectorPosition &&
          other.id == id &&
          other.label == label &&
          other.iconKey == iconKey;

  @override
  int get hashCode => Object.hash(id, label, iconKey);
}

class DetentedSelectorConfig {
  const DetentedSelectorConfig({
    this.positions = const [],
    this.sweepDegrees = 270.0,
    this.startAngleDegrees = 135.0,
    this.initialPositionIndex = 0,
    this.springReturnEnabled = false,
    this.neutralPositionIndex = 0,
    this.showReadout = true,
  });

  static const String customPropertiesKey = 'detentedSelector';

  static const int minPositions = 2;
  static const int maxPositions = 8;
  static const double minSweepDegrees = 60.0;
  static const double maxSweepDegrees = 340.0;

  /// Every selectable detent, in angular order (index 0 = first/lowest
  /// angle). Always normalized to at least [minPositions] entries — see
  /// [normalized].
  final List<SelectorPosition> positions;

  /// Total arc, in degrees, spanned from the first to the last position.
  /// Matches IndustrialPotentiometerControl's 270° default; user-adjustable
  /// so the operator can dial in any rotation range up to [maxSweepDegrees]
  /// (kept below 360 so first/last positions never visually coincide).
  final double sweepDegrees;

  /// Angle of position 0, in degrees, using the same math convention as
  /// IndustrialPotentiometerControl's `_kStartAngle` (0° = 3 o'clock,
  /// clockwise-positive). 135° matches that control's own opening angle, so
  /// a freshly-placed selector reads the same "starts at bottom-left" way.
  final double startAngleDegrees;

  /// Detent index selected when the widget is first placed/built.
  final int initialPositionIndex;

  /// When true, releasing the knob springs it back to [neutralPositionIndex]
  /// instead of staying at whatever detent it was turned to — mirrors
  /// PotentiometerConfig.springReturnEnabled/neutralValue.
  final bool springReturnEnabled;
  final int neutralPositionIndex;

  /// Shows the selected position's label plus a "DETENT i / N-1" caption
  /// inside the dial face. Off hides both, leaving just the tick ring and
  /// pointer.
  final bool showReadout;

  int get positionCount => positions.length;

  DetentedSelectorConfig normalized() {
    var list = positions;
    if (list.length < minPositions) {
      list = [
        ...list,
        for (var i = list.length; i < minPositions; i++)
          SelectorPosition(id: 'pos$i', label: 'Position ${i + 1}'),
      ];
    } else if (list.length > maxPositions) {
      list = list.sublist(0, maxPositions);
    }

    final seenIds = <String>{};
    final dedupedList = <SelectorPosition>[];
    for (var i = 0; i < list.length; i++) {
      final position = list[i];
      final id = position.id.trim().isEmpty ? 'pos$i' : position.id;
      final uniqueId = seenIds.add(id) ? id : '${id}_$i';
      dedupedList.add(
        uniqueId == position.id
            ? position
            : SelectorPosition(
                id: uniqueId,
                label: position.label,
                iconKey: position.iconKey,
              ),
      );
    }

    final safeSweep = _finiteOr(
      sweepDegrees,
      270.0,
    ).clamp(minSweepDegrees, maxSweepDegrees).toDouble();
    final safeStart = _finiteOr(startAngleDegrees, 135.0) % 360.0;
    final lastIndex = dedupedList.length - 1;
    final safeInitial = initialPositionIndex.clamp(0, lastIndex);
    final safeNeutral = neutralPositionIndex.clamp(0, lastIndex);

    return DetentedSelectorConfig(
      positions: dedupedList,
      sweepDegrees: safeSweep,
      startAngleDegrees: safeStart,
      initialPositionIndex: safeInitial,
      springReturnEnabled: springReturnEnabled,
      neutralPositionIndex: safeNeutral,
      showReadout: showReadout,
    );
  }

  /// Appends a new, freshly-and-uniquely-identified position — the only
  /// place a position id is ever minted from something other than JSON, so
  /// the uniqueness scheme (existing ids are always `pos<n>` from
  /// [normalized] or a prior call to this) only has to outrun itself.
  DetentedSelectorConfig withAddedPosition() {
    final n = positions.length;
    var candidateId = 'pos$n';
    var suffix = n;
    while (positions.any((p) => p.id == candidateId)) {
      suffix++;
      candidateId = 'pos$suffix';
    }
    return copyWith(
      positions: [
        ...positions,
        SelectorPosition(id: candidateId, label: 'Position ${n + 1}'),
      ],
    ).normalized();
  }

  DetentedSelectorConfig withRemovedPositionAt(int index) {
    if (index < 0 || index >= positions.length) return this;
    final next = [...positions]..removeAt(index);
    return copyWith(positions: next).normalized();
  }

  DetentedSelectorConfig withUpdatedPositionAt(
    int index,
    SelectorPosition Function(SelectorPosition) f,
  ) {
    if (index < 0 || index >= positions.length) return this;
    final next = [...positions];
    next[index] = f(next[index]);
    return copyWith(positions: next);
  }

  DetentedSelectorConfig copyWith({
    List<SelectorPosition>? positions,
    double? sweepDegrees,
    double? startAngleDegrees,
    int? initialPositionIndex,
    bool? springReturnEnabled,
    int? neutralPositionIndex,
    bool? showReadout,
  }) {
    return DetentedSelectorConfig(
      positions: positions ?? this.positions,
      sweepDegrees: sweepDegrees ?? this.sweepDegrees,
      startAngleDegrees: startAngleDegrees ?? this.startAngleDegrees,
      initialPositionIndex: initialPositionIndex ?? this.initialPositionIndex,
      springReturnEnabled: springReturnEnabled ?? this.springReturnEnabled,
      neutralPositionIndex: neutralPositionIndex ?? this.neutralPositionIndex,
      showReadout: showReadout ?? this.showReadout,
    );
  }

  Map<String, dynamic> toJson() => {
    'positions': positions.map((p) => p.toJson()).toList(),
    'sweepDegrees': sweepDegrees,
    'startAngleDegrees': startAngleDegrees,
    'initialPositionIndex': initialPositionIndex,
    'springReturnEnabled': springReturnEnabled,
    'neutralPositionIndex': neutralPositionIndex,
    'showReadout': showReadout,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory DetentedSelectorConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) {
      return DetentedSelectorConfig.fromJson(raw);
    }
    if (raw is Map) {
      return DetentedSelectorConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const DetentedSelectorConfig().normalized();
  }

  factory DetentedSelectorConfig.fromJson(Map<String, dynamic> json) {
    final rawPositions = (json['positions'] as List?) ?? const [];
    final positions = <SelectorPosition>[
      for (final raw in rawPositions)
        if (raw is Map<String, dynamic>)
          SelectorPosition.fromJson(raw)
        else if (raw is Map)
          SelectorPosition.fromJson(raw.cast<String, dynamic>()),
    ];
    return DetentedSelectorConfig(
      positions: positions,
      sweepDegrees: _readDouble(json['sweepDegrees'], 270.0),
      startAngleDegrees: _readDouble(json['startAngleDegrees'], 135.0),
      initialPositionIndex: _readInt(json['initialPositionIndex'], 0),
      springReturnEnabled: json['springReturnEnabled'] as bool? ?? false,
      neutralPositionIndex: _readInt(json['neutralPositionIndex'], 0),
      showReadout: json['showReadout'] as bool? ?? true,
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DetentedSelectorConfig &&
          _listEquals(other.positions, positions) &&
          other.sweepDegrees == sweepDegrees &&
          other.startAngleDegrees == startAngleDegrees &&
          other.initialPositionIndex == initialPositionIndex &&
          other.springReturnEnabled == springReturnEnabled &&
          other.neutralPositionIndex == neutralPositionIndex &&
          other.showReadout == showReadout;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(positions),
    sweepDegrees,
    startAngleDegrees,
    initialPositionIndex,
    springReturnEnabled,
    neutralPositionIndex,
    showReadout,
  );
}

bool _listEquals(List<SelectorPosition> a, List<SelectorPosition> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double _readDouble(dynamic value, double fallback) {
  if (value is num) return _finiteOr(value.toDouble(), fallback);
  return _finiteOr(double.tryParse('$value') ?? fallback, fallback);
}

int _readInt(dynamic value, int fallback) {
  if (value is num) return value.round();
  return int.tryParse('$value') ?? fallback;
}

double _finiteOr(double value, double fallback) {
  if (value.isNaN || value.isInfinite) return fallback;
  return value;
}
