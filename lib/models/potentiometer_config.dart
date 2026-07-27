import 'dart:math' as math;

import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

class PotentiometerConfig {
  const PotentiometerConfig({
    this.minValue = 0.0,
    this.maxValue = 100.0,
    this.stepSize = 1.0,
    this.defaultValue = 0.0,
    this.showValue = true,
    this.unit = '%',
    this.outputVariantId,
    this.outputChannel = '',
    this.outputEnabled = false,
  });

  static const String customPropertiesKey = 'potentiometer';

  final double minValue;
  final double maxValue;
  final double stepSize;
  final double defaultValue;
  final bool showValue;
  final String unit;
  final String? outputVariantId;
  final String outputChannel;

  /// Reserved for the future analog writer. It intentionally defaults to
  /// false because the current BLE protocol only carries boolean fields.
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

    return PotentiometerConfig(
      minValue: safeMin,
      maxValue: safeMax,
      stepSize: safeStep,
      defaultValue: safeDefault,
      showValue: showValue,
      unit: unit.trim(),
      outputVariantId: _cleanVariantId(outputVariantId),
      outputChannel: outputChannel.trim(),
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

  /// Builds the "min,max,value" wire payload for the BLE analog-output
  /// protocol: bare numbers, no unit suffix, clamped to this config's range.
  /// [value] is clamped/snapped the same way [formatValue] displays it, so
  /// what the operator sees on screen is exactly what the PLC receives.
  String wirePayload(double value) {
    final config = normalized();
    String fmt(double v) => v.toStringAsFixed(config.decimalPlaces);
    return '${fmt(config.minValue)},${fmt(config.maxValue)},'
        '${fmt(config.clampAndSnap(value))}';
  }

  PotentiometerConfig copyWith({
    double? minValue,
    double? maxValue,
    double? stepSize,
    double? defaultValue,
    bool? showValue,
    String? unit,
    String? outputVariantId,
    String? outputChannel,
    bool? outputEnabled,
    bool clearOutputVariantId = false,
  }) {
    return PotentiometerConfig(
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      stepSize: stepSize ?? this.stepSize,
      defaultValue: defaultValue ?? this.defaultValue,
      showValue: showValue ?? this.showValue,
      unit: unit ?? this.unit,
      outputVariantId: clearOutputVariantId
          ? null
          : (outputVariantId ?? this.outputVariantId),
      outputChannel: outputChannel ?? this.outputChannel,
      outputEnabled: outputEnabled ?? this.outputEnabled,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'minValue': minValue,
    'maxValue': maxValue,
    'stepSize': stepSize,
    'defaultValue': defaultValue,
    'showValue': showValue,
    'unit': unit,
    'outputVariantId': outputVariantId,
    'outputChannel': outputChannel,
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
      showValue: json['showValue'] as bool? ?? true,
      unit: json['unit'] as String? ?? '%',
      outputVariantId: _cleanVariantId(json['outputVariantId']),
      outputChannel: json['outputChannel'] as String? ?? '',
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
