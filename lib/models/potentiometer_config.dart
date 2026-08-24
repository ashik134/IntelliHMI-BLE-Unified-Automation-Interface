import 'dart:math' as math;

import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

class PotentiometerConfig implements AnalogWireConfig {
  const PotentiometerConfig({
    this.minValue = 0.0,
    this.maxValue = 100.0,
    this.stepSize = 1.0,
    this.defaultValue = 0.0,
    this.neutralValue = 0.0,
    this.springReturnEnabled = false,
    this.showValue = true,
    this.unit = '%',
    this.outputVariantId,
    this.outputChannel,
    this.outputEnabled = false,
  });

  static const String customPropertiesKey = 'potentiometer';

  @override
  final double minValue;
  @override
  final double maxValue;
  final double stepSize;
  final double defaultValue;

  /// Knob position the pointer springs back to on release when
  /// [springReturnEnabled] is true. Independent of [defaultValue] (which is
  /// only the initial value on first build) — mirrors AnalogSliderConfig's
  /// neutralValue.
  final double neutralValue;

  /// When true, releasing the knob smoothly animates it back to
  /// [neutralValue] instead of staying put. Defaults to false: today's
  /// existing behavior (stays wherever released), matching a real
  /// set-and-forget potentiometer.
  final bool springReturnEnabled;
  final bool showValue;
  final String unit;
  final String? outputVariantId;

  /// Which firmware analog channel (A1..A6) this control writes to — see
  /// AnalogWireConfig.outputChannel. Null until the operator picks one in
  /// the OUTPUT MAPPING editor.
  @override
  final AnalogOutputChannel? outputChannel;

  /// Opt-in "send to PLC" flag for this control's analog output. Defaults
  /// to false so a freshly-added control stays inert until the operator
  /// explicitly enables it in the OUTPUT MAPPING editor.
  @override
  final bool outputEnabled;

  double get range => maxValue - minValue;

  bool get hasUsableRange => maxValue > minValue;

  PotentiometerConfig normalized() {
    final safeMin = _finiteOr(minValue, 0.0);
    var safeMax = _finiteOr(maxValue, safeMin + 100.0);
    if (safeMax <= safeMin) safeMax = safeMin + 1.0;

    final safeRange = safeMax - safeMin;
    var safeStep = _finiteOr(stepSize.abs(), 1.0);
    if (safeStep <= 0.0) safeStep = 1.0;
    if (safeStep > safeRange) safeStep = safeRange;

    final safeDefault = _snapToStep(
      value: _finiteOr(defaultValue, safeMin),
      min: safeMin,
      max: safeMax,
      step: safeStep,
    );
    final safeNeutral = _finiteOr(
      neutralValue,
      safeMin,
    ).clamp(safeMin, safeMax).toDouble();

    return PotentiometerConfig(
      minValue: safeMin,
      maxValue: safeMax,
      stepSize: safeStep,
      defaultValue: safeDefault,
      neutralValue: safeNeutral,
      springReturnEnabled: springReturnEnabled,
      showValue: showValue,
      unit: unit.trim(),
      outputVariantId: _cleanVariantId(outputVariantId),
      outputChannel: outputChannel,
      outputEnabled: outputEnabled,
    );
  }

  double clampAndSnap(double value) {
    final config = normalized();
    return _snapToStep(
      value: value,
      min: config.minValue,
      max: config.maxValue,
      step: config.stepSize,
    );
  }

  double normalizedValueFor(double value) {
    final config = normalized();
    if (!config.hasUsableRange) return 0.0;
    return ((config.clampAndSnap(value) - config.minValue) / config.range)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double valueForNormalized(double normalizedValue) {
    final config = normalized();
    final t = normalizedValue.clamp(0.0, 1.0).toDouble();
    return config.clampAndSnap(config.minValue + config.range * t);
  }

  @override
  int get decimalPlaces {
    final text = stepSize.abs().toStringAsFixed(6);
    final trimmed = text.replaceFirst(RegExp(r'0+$'), '');
    final index = trimmed.indexOf('.');
    if (index == -1) return 0;
    return (trimmed.length - index - 1).clamp(0, 3).toInt();
  }

  String formatValue(double value) {
    final config = normalized();
    final number = config
        .clampAndSnap(value)
        .toStringAsFixed(config.decimalPlaces);
    final suffix = config.unit.trim();
    return suffix.isEmpty ? number : '$number$suffix';
  }

  /// Satisfies [AnalogWireConfig.clampAndSnapForWire] — identical to
  /// [clampAndSnap], just named for the wire-layer call site.
  @override
  double clampAndSnapForWire(double value) => clampAndSnap(value);

  PotentiometerConfig copyWith({
    double? minValue,
    double? maxValue,
    double? stepSize,
    double? defaultValue,
    double? neutralValue,
    bool? springReturnEnabled,
    bool? showValue,
    String? unit,
    String? outputVariantId,
    AnalogOutputChannel? outputChannel,
    bool? outputEnabled,
    bool clearOutputVariantId = false,
    bool clearOutputChannel = false,
  }) {
    return PotentiometerConfig(
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      stepSize: stepSize ?? this.stepSize,
      defaultValue: defaultValue ?? this.defaultValue,
      neutralValue: neutralValue ?? this.neutralValue,
      springReturnEnabled: springReturnEnabled ?? this.springReturnEnabled,
      showValue: showValue ?? this.showValue,
      unit: unit ?? this.unit,
      outputVariantId: clearOutputVariantId
          ? null
          : (outputVariantId ?? this.outputVariantId),
      outputChannel: clearOutputChannel
          ? null
          : (outputChannel ?? this.outputChannel),
      outputEnabled: outputEnabled ?? this.outputEnabled,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'minValue': minValue,
    'maxValue': maxValue,
    'stepSize': stepSize,
    'defaultValue': defaultValue,
    'neutralValue': neutralValue,
    'springReturnEnabled': springReturnEnabled,
    'showValue': showValue,
    'unit': unit,
    'outputVariantId': outputVariantId,
    'outputChannel': outputChannel?.token,
    'outputEnabled': outputEnabled,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory PotentiometerConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) {
      return PotentiometerConfig.fromJson(raw);
    }
    if (raw is Map) {
      return PotentiometerConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const PotentiometerConfig();
  }

  factory PotentiometerConfig.fromJson(Map<String, dynamic> json) {
    return PotentiometerConfig(
      minValue: _readDouble(json['minValue'], 0.0),
      maxValue: _readDouble(json['maxValue'], 100.0),
      stepSize: _readDouble(json['stepSize'], 1.0),
      defaultValue: _readDouble(json['defaultValue'], 0.0),
      neutralValue: _readDouble(json['neutralValue'], 0.0),
      springReturnEnabled: json['springReturnEnabled'] as bool? ?? false,
      showValue: json['showValue'] as bool? ?? true,
      unit: json['unit'] as String? ?? '%',
      outputVariantId: _cleanVariantId(json['outputVariantId']),
      outputChannel: AnalogOutputChannel.fromToken(json['outputChannel']),
      outputEnabled: json['outputEnabled'] as bool? ?? false,
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PotentiometerConfig &&
          other.minValue == minValue &&
          other.maxValue == maxValue &&
          other.stepSize == stepSize &&
          other.defaultValue == defaultValue &&
          other.neutralValue == neutralValue &&
          other.springReturnEnabled == springReturnEnabled &&
          other.showValue == showValue &&
          other.unit == unit &&
          other.outputVariantId == outputVariantId &&
          other.outputChannel == outputChannel &&
          other.outputEnabled == outputEnabled;

  @override
  int get hashCode => Object.hash(
    minValue,
    maxValue,
    stepSize,
    defaultValue,
    neutralValue,
    springReturnEnabled,
    showValue,
    unit,
    outputVariantId,
    outputChannel,
    outputEnabled,
  );
}

double _readDouble(dynamic value, double fallback) {
  if (value is num) return _finiteOr(value.toDouble(), fallback);
  return _finiteOr(double.tryParse('$value') ?? fallback, fallback);
}

double _finiteOr(double value, double fallback) {
  if (value.isNaN || value.isInfinite) return fallback;
  return value;
}

double _snapToStep({
  required double value,
  required double min,
  required double max,
  required double step,
}) {
  final clamped = math.min(max, math.max(min, value));
  final steps = ((clamped - min) / step).round();
  final snapped = min + steps * step;
  return math.min(max, math.max(min, snapped));
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

String? _cleanVariantId(Object? value) {
  final variant = PlcOutputVariant.fromStorageKey(value);
  if (variant != null) return variant.variantId;
  return _cleanNullable(value?.toString());
}
