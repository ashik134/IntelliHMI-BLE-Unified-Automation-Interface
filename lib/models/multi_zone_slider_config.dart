import 'dart:math' as math;

// ─────────────────────────────────────────────────────────────────────────────
// MultiZoneSliderConfig
//
// Backs both ButtonType.bidirectionalSlider5Step and .bidirectionalSlider3Step
// (see multi_zone_slider_strategy.dart / multi_zone_slider_button.dart).
// startLabel/endLabel let the operator rename the two independent endpoint
// labels IndustrialMultiZoneSlider already renders (e.g. "Slow"/"Fast" or
// "Left"/"Right") instead of both ends silently sharing ButtonConfig.label.
// deadZoneFraction/farZoneFraction expose the widget's center dead-band and
// (5-zone only) near/far zone boundary, previously hardcoded constants in
// _IndustrialMultiZoneSliderState.
// ─────────────────────────────────────────────────────────────────────────────

class MultiZoneSliderConfig {
  const MultiZoneSliderConfig({
    this.startLabel,
    this.endLabel,
    this.deadZoneFraction = 0.12,
    this.farZoneFraction = 0.62,
  });

  static const String customPropertiesKey = 'multiZoneSlider';

  static const double minDeadZoneFraction = 0.02;
  static const double maxDeadZoneFraction = 0.40;
  static const double minFarZoneFraction = 0.40;
  static const double maxFarZoneFraction = 0.90;

  /// Null falls back to the widget's default arrow icon + no override label
  /// (the negative-drag end).
  final String? startLabel;

  /// Positive-drag end.
  final String? endLabel;

  /// Fraction of half-track (from center) treated as neutral/idle.
  final double deadZoneFraction;

  /// Fraction of half-track beyond which a 5-zone slider reports the far
  /// (zone1/zone5) rather than near (zone2/zone4) state. Ignored by the
  /// 3-zone variant, which has no far zone.
  final double farZoneFraction;

  MultiZoneSliderConfig normalized() {
    var safeDeadZone = _finiteOr(deadZoneFraction, 0.12).clamp(
      minDeadZoneFraction,
      maxDeadZoneFraction,
    );
    var safeFarZone = _finiteOr(farZoneFraction, 0.62).clamp(
      minFarZoneFraction,
      maxFarZoneFraction,
    );
    if (safeFarZone <= safeDeadZone) {
      safeFarZone = math.min(maxFarZoneFraction, safeDeadZone + 0.1);
    }
    return MultiZoneSliderConfig(
      startLabel: _cleanNullable(startLabel),
      endLabel: _cleanNullable(endLabel),
      deadZoneFraction: safeDeadZone,
      farZoneFraction: safeFarZone,
    );
  }

  MultiZoneSliderConfig copyWith({
    String? startLabel,
    String? endLabel,
    double? deadZoneFraction,
    double? farZoneFraction,
    bool clearStartLabel = false,
    bool clearEndLabel = false,
  }) {
    return MultiZoneSliderConfig(
      startLabel: clearStartLabel ? null : (startLabel ?? this.startLabel),
      endLabel: clearEndLabel ? null : (endLabel ?? this.endLabel),
      deadZoneFraction: deadZoneFraction ?? this.deadZoneFraction,
      farZoneFraction: farZoneFraction ?? this.farZoneFraction,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'startLabel': startLabel,
    'endLabel': endLabel,
    'deadZoneFraction': deadZoneFraction,
    'farZoneFraction': farZoneFraction,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory MultiZoneSliderConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) {
      return MultiZoneSliderConfig.fromJson(raw);
    }
    if (raw is Map) {
      return MultiZoneSliderConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const MultiZoneSliderConfig();
  }

  factory MultiZoneSliderConfig.fromJson(Map<String, dynamic> json) {
    return MultiZoneSliderConfig(
      startLabel: _cleanNullable(json['startLabel'] as String?),
      endLabel: _cleanNullable(json['endLabel'] as String?),
      deadZoneFraction: _readDouble(json['deadZoneFraction'], 0.12),
      farZoneFraction: _readDouble(json['farZoneFraction'], 0.62),
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiZoneSliderConfig &&
          other.startLabel == startLabel &&
          other.endLabel == endLabel &&
          other.deadZoneFraction == deadZoneFraction &&
          other.farZoneFraction == farZoneFraction;

  @override
  int get hashCode =>
      Object.hash(startLabel, endLabel, deadZoneFraction, farZoneFraction);
}

double _readDouble(dynamic value, double fallback) {
  if (value is num) return _finiteOr(value.toDouble(), fallback);
  return fallback;
}

double _finiteOr(double value, double fallback) {
  if (value.isNaN || value.isInfinite) return fallback;
  return value;
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
