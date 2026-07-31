import 'package:rev_crane_control_ops/models/analog_wire_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalogSliderConfig
//
// Backs both ButtonType.analogSliderOT and .analogSliderTOT. The one-side
// (O-T) vs two-side (T-O-T) distinction is NOT a mode flag here — it's
// purely where neutralValue sits relative to minValue/maxValue (O-T:
// neutral == minValue; T-O-T: neutral == midpoint). AnalogSliderStrategy
// only uses that distinction to seed a sensible *default* config for each
// ButtonType when a button is first created; this class itself is agnostic
// and fully user-editable afterwards.
// ─────────────────────────────────────────────────────────────────────────────

enum AnalogSliderOrientation { horizontal, vertical }

extension AnalogSliderOrientationInfo on AnalogSliderOrientation {
  String get label => switch (this) {
    AnalogSliderOrientation.horizontal => 'Horizontal',
    AnalogSliderOrientation.vertical => 'Vertical',
  };
}

class AnalogSliderConfig with AnalogRangeMixin implements AnalogWireConfig {
  const AnalogSliderConfig({
    this.minValue = 0.0,
    this.maxValue = 100.0,
    this.neutralValue = 0.0,
    this.stepSize = 1.0,
    this.springReturnEnabled = true,
    this.orientation = AnalogSliderOrientation.vertical,
    this.invert = false,
    this.outputEnabled = false,
    this.unit = '',
  });

  static const String customPropertiesKey = 'analogSlider';

  @override
  final double minValue;
  @override
  final double maxValue;
  @override
  final double neutralValue;
  @override
  final double stepSize;
  final bool springReturnEnabled;
  final AnalogSliderOrientation orientation;
  final bool invert;

  /// Opt-in "send to PLC" flag, same convention as PotentiometerConfig —
  /// defaults to false so a freshly-added control stays inert until the
  /// operator explicitly enables it.
  @override
  final bool outputEnabled;
  final String unit;

  /// True when [neutralValue] sits at either end of the range rather than
  /// between [minValue] and [maxValue] — the O-T (one-side) shape. Purely
  /// descriptive of the *current* config; not stored separately.
  bool get isOneSided =>
      neutralValue <= minValue || neutralValue >= maxValue;

  AnalogSliderConfig normalized() {
    final safeMin = finiteOrAnalog(minValue, 0.0);
    var safeMax = finiteOrAnalog(maxValue, safeMin + 100.0);
    if (safeMax <= safeMin) safeMax = safeMin + 1.0;
    final safeRange = safeMax - safeMin;

    var safeStep = finiteOrAnalog(stepSize.abs(), 1.0);
    if (safeStep <= 0.0) safeStep = 1.0;
    if (safeStep > safeRange) safeStep = safeRange;

    final safeNeutral = finiteOrAnalog(
      neutralValue,
      safeMin,
    ).clamp(safeMin, safeMax).toDouble();

    return AnalogSliderConfig(
      minValue: safeMin,
      maxValue: safeMax,
      neutralValue: safeNeutral,
      stepSize: safeStep,
      springReturnEnabled: springReturnEnabled,
      orientation: orientation,
      invert: invert,
      outputEnabled: outputEnabled,
      unit: unit.trim(),
    );
  }

  @override
  String wirePayload(double value) => normalized().analogWirePayload(value);

  AnalogSliderConfig copyWith({
    double? minValue,
    double? maxValue,
    double? neutralValue,
    double? stepSize,
    bool? springReturnEnabled,
    AnalogSliderOrientation? orientation,
    bool? invert,
    bool? outputEnabled,
    String? unit,
  }) {
    return AnalogSliderConfig(
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      neutralValue: neutralValue ?? this.neutralValue,
      stepSize: stepSize ?? this.stepSize,
      springReturnEnabled: springReturnEnabled ?? this.springReturnEnabled,
      orientation: orientation ?? this.orientation,
      invert: invert ?? this.invert,
      outputEnabled: outputEnabled ?? this.outputEnabled,
      unit: unit ?? this.unit,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'minValue': minValue,
    'maxValue': maxValue,
    'neutralValue': neutralValue,
    'stepSize': stepSize,
    'springReturnEnabled': springReturnEnabled,
    'orientation': orientation.name,
    'invert': invert,
    'outputEnabled': outputEnabled,
    'unit': unit,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory AnalogSliderConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return AnalogSliderConfig.fromJson(raw);
    if (raw is Map) {
      return AnalogSliderConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const AnalogSliderConfig();
  }

  factory AnalogSliderConfig.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, dynamic name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return AnalogSliderConfig(
      minValue: readAnalogDouble(json['minValue'], 0.0),
      maxValue: readAnalogDouble(json['maxValue'], 100.0),
      neutralValue: readAnalogDouble(json['neutralValue'], 0.0),
      stepSize: readAnalogDouble(json['stepSize'], 1.0),
      springReturnEnabled: json['springReturnEnabled'] as bool? ?? true,
      orientation: enumValue(
        AnalogSliderOrientation.values,
        json['orientation'],
        AnalogSliderOrientation.vertical,
      ),
      invert: json['invert'] as bool? ?? false,
      outputEnabled: json['outputEnabled'] as bool? ?? false,
      unit: json['unit'] as String? ?? '',
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalogSliderConfig &&
          other.minValue == minValue &&
          other.maxValue == maxValue &&
          other.neutralValue == neutralValue &&
          other.stepSize == stepSize &&
          other.springReturnEnabled == springReturnEnabled &&
          other.orientation == orientation &&
          other.invert == invert &&
          other.outputEnabled == outputEnabled &&
          other.unit == unit;

  @override
  int get hashCode => Object.hash(
    minValue,
    maxValue,
    neutralValue,
    stepSize,
    springReturnEnabled,
    orientation,
    invert,
    outputEnabled,
    unit,
  );
}
