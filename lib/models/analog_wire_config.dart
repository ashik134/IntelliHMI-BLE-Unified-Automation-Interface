import 'dart:math' as math;

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalogWireConfig / AnalogRangeMixin / AnalogOutputChannel
//
// Shared contract for every control that writes to the ESP32 firmware's
// channel-addressed analog-output protocol (AnalogOutputCallbacks::onWrite in
// web_handler.h/main.cpp) through CraneController.setAnalogButtonValue ->
// BleService.writeAnalogOutput -> the encrypted analog-out characteristic.
// The firmware keeps six independent AnalogChannelState slots (A1..A6), each
// with its own persisted rangeMin/rangeMax; a RANGE:A{n}-{min},{max} command
// sets that scaling, and a DATA:A{n}-{value}[,A{m}-{value2},...] command
// pushes one or more raw engineering-unit values that the firmware maps to
// its 0..4095 PWM output using the channel's last-set range. PotentiometerConfig
// implements this interface directly; AnalogJoystickConfig/AnalogSliderConfig
// mix in [AnalogRangeMixin] for the shared min/max/neutral/step math.
// ─────────────────────────────────────────────────────────────────────────────

/// One of the firmware's six independently addressable analog output
/// channels (`AnalogChannelState analogChannels[NUM_ANALOG_CHANNELS]` in
/// web_handler.h). [token] is the exact "A1".."A6" identifier the firmware's
/// `parseAnalogChannelToken` expects inside RANGE:/DATA: command bodies.
enum AnalogOutputChannel {
  a1,
  a2,
  a3,
  a4,
  a5,
  a6;

  String get token => 'A${index + 1}';

  /// Display label for pickers — identical to [token] since operators refer
  /// to these channels by their wire identifier directly.
  String get label => token;

  static AnalogOutputChannel? fromToken(Object? raw) {
    if (raw == null) return null;
    final normalized = raw.toString().trim().toUpperCase();
    for (final channel in values) {
      if (channel.token == normalized) return channel;
    }
    return null;
  }
}

abstract interface class AnalogWireConfig {
  bool get outputEnabled;

  /// Which firmware channel this control writes to. Output stays inert
  /// (see CraneController.setAnalogButtonValue) until both this and
  /// [outputEnabled] are set — a freshly added control has no channel
  /// assigned yet.
  AnalogOutputChannel? get outputChannel;

  /// Engineering-unit output range. Sent to the firmware via a
  /// RANGE:A{n}-{min},{max} command and used there to scale DATA values
  /// onto the physical 0..4095 PWM output.
  double get minValue;
  double get maxValue;

  int get decimalPlaces;

  /// Clamps/snaps [value] into [minValue]..[maxValue] the same way this
  /// config's on-screen value display does, so what the operator sees is
  /// exactly what a DATA command sends.
  double clampAndSnapForWire(double value);
}

/// Shared min/max/neutral/step math for analog configs other than
/// [PotentiometerConfig] (which keeps its own independent, untouched
/// implementation). A mixing-in class must already be normalized (safe
/// min < max, positive step) — each concrete config's own `normalized()`
/// factory is responsible for that, mirroring PotentiometerConfig's pattern.
mixin AnalogRangeMixin {
  double get minValue;
  double get maxValue;
  double get neutralValue;
  double get stepSize;

  double get analogRange => maxValue - minValue;

  bool get hasUsableAnalogRange => maxValue > minValue;

  int get decimalPlaces {
    final text = stepSize.abs().toStringAsFixed(6);
    final trimmed = text.replaceFirst(RegExp(r'0+$'), '');
    final index = trimmed.indexOf('.');
    if (index == -1) return 0;
    return (trimmed.length - index - 1).clamp(0, 3).toInt();
  }

  double clampAndSnapAnalog(double value) {
    final step = stepSize.abs() > 0 ? stepSize.abs() : 1.0;
    final clamped = math.min(maxValue, math.max(minValue, value));
    final steps = ((clamped - minValue) / step).round();
    final snapped = minValue + steps * step;
    return math.min(maxValue, math.max(minValue, snapped));
  }

  /// Satisfies [AnalogWireConfig.clampAndSnapForWire] for every mixing-in
  /// config — identical clamp/snap behaviour, just named for the wire-layer
  /// call site.
  double clampAndSnapForWire(double value) => clampAndSnapAnalog(value);

  /// Maps a signed gesture value in [-1, 1] (e.g. joystick/slider drag
  /// position) to a real output value, anchored at [neutralValue] rather
  /// than assuming it sits at the range midpoint: `raw >= 0` scales from
  /// neutral up to [maxValue], `raw < 0` scales from neutral down to
  /// [minValue]. Collapses to ordinary linear interpolation when
  /// [neutralValue] is the midpoint, and is exactly what a one-sided analog
  /// slider needs when `neutralValue == minValue` (raw is then always >= 0).
  double signedToValue(double raw) {
    final clampedRaw = raw.clamp(-1.0, 1.0);
    final target = clampedRaw >= 0
        ? neutralValue + clampedRaw * (maxValue - neutralValue)
        : neutralValue + clampedRaw * (neutralValue - minValue);
    return clampAndSnapAnalog(target);
  }

  /// Absolute track position in [0, 1] across the full [minValue]..
  /// [maxValue] range (0 = minValue, 1 = maxValue) — for widgets whose
  /// gesture has a fixed physical position (e.g. a linear slider thumb),
  /// as opposed to [signedToValue]'s center-relative bipolar drag (e.g. a
  /// joystick, which always returns to a physical center regardless of
  /// where neutralValue maps in output space).
  double normalizedValueFor(double value) {
    if (!hasUsableAnalogRange) return 0.0;
    return ((clampAndSnapAnalog(value) - minValue) / analogRange)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double valueForNormalized(double t) {
    final clampedT = t.clamp(0.0, 1.0).toDouble();
    return clampAndSnapAnalog(minValue + analogRange * clampedT);
  }
}

double finiteOrAnalog(double value, double fallback) {
  if (value.isNaN || value.isInfinite) return fallback;
  return value;
}

double readAnalogDouble(dynamic value, double fallback) {
  if (value is num) return finiteOrAnalog(value.toDouble(), fallback);
  return finiteOrAnalog(double.tryParse('$value') ?? fallback, fallback);
}

String _fmtAnalogWireNumber(double value, int decimalPlaces) =>
    value.toStringAsFixed(decimalPlaces);

/// Builds the firmware's `A{n}-{min},{max}` RANGE command body for
/// [config]'s currently configured range. Returns null when no channel is
/// assigned — there is nothing to address the command to.
String? analogRangeToken(AnalogWireConfig config) {
  final channel = config.outputChannel;
  if (channel == null) return null;
  return '${channel.token}-'
      '${_fmtAnalogWireNumber(config.minValue, config.decimalPlaces)},'
      '${_fmtAnalogWireNumber(config.maxValue, config.decimalPlaces)}';
}

/// Builds the firmware's `A{n}-{value}` DATA command fragment for [config]
/// at [value] (clamped/snapped exactly like the on-screen display). Returns
/// null when no channel is assigned.
String? analogDataToken(AnalogWireConfig config, double value) {
  final channel = config.outputChannel;
  if (channel == null) return null;
  final clamped = config.clampAndSnapForWire(value);
  return '${channel.token}-'
      '${_fmtAnalogWireNumber(clamped, config.decimalPlaces)}';
}

/// Resolves the [AnalogWireConfig] a [ButtonConfig] carries in its
/// [ButtonConfig.customProperties], keyed by [ButtonConfig.type]. The single
/// call site for every control screen's `onAnalogCommand` handler — keeps
/// the type-to-config-model mapping in one place instead of duplicated
/// per-screen. Only ever called for button types whose strategy actually
/// invokes `onAnalogCommand` (see kButtonTypeStrategies); reaching the
/// fallback is a programming error, matching the same-shaped guards
/// elsewhere (e.g. logicalStateIdFor's horn/alarmIndicator cases).
AnalogWireConfig resolveAnalogWireConfig(ButtonConfig config) {
  switch (config.type) {
    case ButtonType.potentiometer:
      return PotentiometerConfig.fromCustomProperties(
        config.customProperties,
      ).normalized();
    case ButtonType.analogJoystick1D:
    case ButtonType.analogJoystick2D:
      return AnalogJoystickConfig.fromCustomProperties(
        config.customProperties,
      ).normalized();
    case ButtonType.analogSliderOT:
    case ButtonType.analogSliderTOT:
      return AnalogSliderConfig.fromCustomProperties(
        config.customProperties,
      ).normalized();
    default:
      throw UnsupportedError(
        'resolveAnalogWireConfig does not handle ${config.type}; only '
        'analog-output button types should ever invoke onAnalogCommand.',
      );
  }
}
