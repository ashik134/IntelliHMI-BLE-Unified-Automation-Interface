import 'package:flutter/painting.dart' show Color;
import 'package:rev_crane_control_ops/models/hoist_notification.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalogFeedbackConfig
//
// One analog READER channel — a sensor reading / analog value display, never
// an analog output. The channel value arrives from the PLC's analog
// characteristic after AES-GCM decryption of an `H1,<v>` / `H2,<v>` hoist
// notification. The firmware has already applied its 400-count deadband and
// 3.0303 scale; everything here describes any further operator calibration
// into engineering units and annunciation. No field on this class can produce
// a PLC write — see FeedbackManager.
//
// Two separate ranges, deliberately:
//   * [rawMin]/[rawMax]  — the span received from the firmware. This is
//     calibration after the firmware's own deadband and scaling.
//   * [displayMin]/[displayMax] — the engineering span those counts mean
//     ("0..25 tonnes"). This is scaling.
// [calibrationOffset] is applied last, in engineering units, so a field zero
// trim never has to be back-converted into counts.
// ─────────────────────────────────────────────────────────────────────────────

/// Operating band a scaled reading falls into. Mirrors the gauge's own
/// [GaugeZone] but lives here so the manager can resolve a band without
/// importing any widget code.
enum AnalogFeedbackZone { normal, warning, critical }

class AnalogFeedbackConfig {
  const AnalogFeedbackConfig({
    required this.channelKey,
    this.label = '',
    this.unit = '',
    this.rawMin = 0,
    this.rawMax = defaultFirmwareFullScale,
    this.displayMin = 0,
    this.displayMax = defaultFirmwareFullScale,
    this.calibrationOffset = 0,
    this.warningFraction = defaultWarningFraction,
    this.criticalFraction = defaultCriticalFraction,
    this.color,
    this.visible = true,
    this.raiseAlarm = false,
    this.soundBuzzer = false,
  });

  /// Full scale after the firmware applies `(raw - 400) * 3.0303f` to a
  /// 12-bit ADC reading and casts the result to `uint16_t`.
  static const double defaultFirmwareFullScale =
      HoistNotification.firmwareFullScale;

  /// Full scale used by layouts saved against the former A1/A2 wire format.
  static const double _legacyAdcFullScale = 4095;

  static const double defaultWarningFraction = 0.75;
  static const double defaultCriticalFraction = 0.90;

  /// Feedback SOURCE: which hoist channel this reader watches (`H1` or `H2`,
  /// matched against CraneController.analogValues' keys). Never a writable
  /// target.
  final String channelKey;

  /// Operator-facing name. Empty falls back to the channel key at render time
  /// so an unnamed channel is still identifiable.
  final String label;

  /// Engineering unit printed next to the reading. Empty makes the gauge show
  /// percent of full scale instead.
  final String unit;

  /// Raw transducer span — see the class doc comment.
  final double rawMin;
  final double rawMax;

  /// Engineering span the raw span maps onto.
  final double displayMin;
  final double displayMax;

  /// Field zero trim, added after scaling, in engineering units.
  final double calibrationOffset;

  /// Fractions of the engineering span at which the reading escalates.
  /// Always `0 <= warning <= critical <= 1` — enforced by [normalized].
  final double warningFraction;
  final double criticalFraction;

  /// Channel identity colour; null uses the theme default for the channel's
  /// position, matching ButtonStyleConfig's nullable "use the default"
  /// contract everywhere else in this app.
  final Color? color;

  /// Per-channel visibility. Independent of the sensor row's own master
  /// toggle (ControlArrangementConfig.showSensorRow), which hides the whole
  /// strip.
  final bool visible;

  /// Whether crossing into [AnalogFeedbackZone.critical] escalates the
  /// layout's feedback severity (banner / AppBar indication), and whether it
  /// may sound the buzzer. Both are annunciation only.
  final bool raiseAlarm;
  final bool soundBuzzer;

  /// Engineering value for [raw] counts. Deliberately NOT clamped: an
  /// over-range transducer must read over-range rather than silently pin to
  /// full scale. [zoneFraction] does the clamping for display purposes.
  double scaledValue(num raw) {
    final rawSpan = rawMax - rawMin;
    if (!rawSpan.isFinite || rawSpan == 0) {
      return displayMin + calibrationOffset;
    }
    final t = (raw - rawMin) / rawSpan;
    return displayMin + t * (displayMax - displayMin) + calibrationOffset;
  }

  /// Clamped 0..1 position of an already-[scaledValue]d reading on the
  /// engineering span — what the gauge sweep and the zone lookup both use.
  double zoneFraction(double scaled) {
    final span = displayMax - displayMin;
    if (!span.isFinite || span == 0 || !scaled.isFinite) return 0;
    return ((scaled - displayMin) / span).clamp(0.0, 1.0).toDouble();
  }

  AnalogFeedbackZone zoneFor(double scaled) {
    final fraction = zoneFraction(scaled);
    if (fraction >= criticalFraction) return AnalogFeedbackZone.critical;
    if (fraction >= warningFraction) return AnalogFeedbackZone.warning;
    return AnalogFeedbackZone.normal;
  }

  /// Whether the received firmware values and displayed values use the same
  /// span — i.e. the channel has no additional app-side scaling.
  bool get isUnscaled =>
      rawMin == displayMin && rawMax == displayMax && calibrationOffset == 0;

  /// Repairs any combination the sheets could produce: inverted or zero-width
  /// spans, out-of-order thresholds, non-finite numbers. Applied by
  /// [copyWith] and [fromJson] so no downstream consumer has to re-check.
  AnalogFeedbackConfig normalized() {
    final safeRawMin = rawMin.isFinite ? rawMin : 0.0;
    var safeRawMax = rawMax.isFinite ? rawMax : defaultFirmwareFullScale;
    if (safeRawMax <= safeRawMin) safeRawMax = safeRawMin + 1;

    final safeDisplayMin = displayMin.isFinite ? displayMin : 0.0;
    var safeDisplayMax = displayMax.isFinite
        ? displayMax
        : defaultFirmwareFullScale;
    if (safeDisplayMax <= safeDisplayMin) safeDisplayMax = safeDisplayMin + 1;

    final safeWarning = warningFraction.isFinite
        ? warningFraction.clamp(0.0, 1.0).toDouble()
        : defaultWarningFraction;
    final safeCritical = criticalFraction.isFinite
        ? criticalFraction.clamp(0.0, 1.0).toDouble()
        : defaultCriticalFraction;

    return AnalogFeedbackConfig(
      channelKey: channelKey,
      label: label,
      unit: unit,
      rawMin: safeRawMin,
      rawMax: safeRawMax,
      displayMin: safeDisplayMin,
      displayMax: safeDisplayMax,
      calibrationOffset: calibrationOffset.isFinite ? calibrationOffset : 0,
      // A warning threshold above the critical one would make the warning band
      // unreachable — collapse it onto critical instead of silently ignoring.
      warningFraction: safeWarning > safeCritical ? safeCritical : safeWarning,
      criticalFraction: safeCritical,
      color: color,
      visible: visible,
      raiseAlarm: raiseAlarm,
      soundBuzzer: soundBuzzer,
    );
  }

  AnalogFeedbackConfig copyWith({
    String? channelKey,
    String? label,
    String? unit,
    double? rawMin,
    double? rawMax,
    double? displayMin,
    double? displayMax,
    double? calibrationOffset,
    double? warningFraction,
    double? criticalFraction,
    Color? color,
    bool clearColor = false,
    bool? visible,
    bool? raiseAlarm,
    bool? soundBuzzer,
  }) {
    return AnalogFeedbackConfig(
      channelKey: channelKey ?? this.channelKey,
      label: label ?? this.label,
      unit: unit ?? this.unit,
      rawMin: rawMin ?? this.rawMin,
      rawMax: rawMax ?? this.rawMax,
      displayMin: displayMin ?? this.displayMin,
      displayMax: displayMax ?? this.displayMax,
      calibrationOffset: calibrationOffset ?? this.calibrationOffset,
      warningFraction: warningFraction ?? this.warningFraction,
      criticalFraction: criticalFraction ?? this.criticalFraction,
      color: clearColor ? null : (color ?? this.color),
      visible: visible ?? this.visible,
      raiseAlarm: raiseAlarm ?? this.raiseAlarm,
      soundBuzzer: soundBuzzer ?? this.soundBuzzer,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'channelKey': channelKey,
    'label': label,
    'unit': unit,
    'rawMin': rawMin,
    'rawMax': rawMax,
    'displayMin': displayMin,
    'displayMax': displayMax,
    'calibrationOffset': calibrationOffset,
    'warningFraction': warningFraction,
    'criticalFraction': criticalFraction,
    'color': color?.toARGB32(),
    'visible': visible,
    'raiseAlarm': raiseAlarm,
    'soundBuzzer': soundBuzzer,
  };

  factory AnalogFeedbackConfig.fromJson(Map<String, dynamic> json) {
    final rawColor = json['color'] as num?;
    final storedChannelKey =
        json['channelKey'] as String? ?? HoistNotification.hoist1Key;
    final isLegacyChannel =
        storedChannelKey == 'A1' || storedChannelKey == 'A2';
    final channelKey = switch (storedChannelKey) {
      'A1' => HoistNotification.hoist1Key,
      'A2' => HoistNotification.hoist2Key,
      _ => storedChannelKey,
    };
    final storedRawMax =
        (json['rawMax'] as num?)?.toDouble() ?? defaultFirmwareFullScale;
    final storedDisplayMax =
        (json['displayMax'] as num?)?.toDouble() ?? defaultFirmwareFullScale;

    return AnalogFeedbackConfig(
      channelKey: channelKey,
      label: json['label'] as String? ?? '',
      unit: json['unit'] as String? ?? '',
      rawMin: (json['rawMin'] as num?)?.toDouble() ?? 0,
      rawMax: isLegacyChannel && storedRawMax == _legacyAdcFullScale
          ? defaultFirmwareFullScale
          : storedRawMax,
      displayMin: (json['displayMin'] as num?)?.toDouble() ?? 0,
      displayMax: isLegacyChannel && storedDisplayMax == _legacyAdcFullScale
          ? defaultFirmwareFullScale
          : storedDisplayMax,
      calibrationOffset: (json['calibrationOffset'] as num?)?.toDouble() ?? 0,
      warningFraction:
          (json['warningFraction'] as num?)?.toDouble() ??
          defaultWarningFraction,
      criticalFraction:
          (json['criticalFraction'] as num?)?.toDouble() ??
          defaultCriticalFraction,
      color: rawColor != null ? Color(rawColor.toInt()) : null,
      visible: json['visible'] as bool? ?? true,
      raiseAlarm: json['raiseAlarm'] as bool? ?? false,
      soundBuzzer: json['soundBuzzer'] as bool? ?? false,
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalogFeedbackConfig &&
          other.channelKey == channelKey &&
          other.label == label &&
          other.unit == unit &&
          other.rawMin == rawMin &&
          other.rawMax == rawMax &&
          other.displayMin == displayMin &&
          other.displayMax == displayMax &&
          other.calibrationOffset == calibrationOffset &&
          other.warningFraction == warningFraction &&
          other.criticalFraction == criticalFraction &&
          other.color == color &&
          other.visible == visible &&
          other.raiseAlarm == raiseAlarm &&
          other.soundBuzzer == soundBuzzer;

  @override
  int get hashCode => Object.hash(
    channelKey,
    label,
    unit,
    rawMin,
    rawMax,
    displayMin,
    displayMax,
    calibrationOffset,
    warningFraction,
    criticalFraction,
    color,
    visible,
    raiseAlarm,
    soundBuzzer,
  );
}

/// The hoist channels a fresh layout reads. Values use the firmware's
/// post-deadband, post-scale range and are displayed unchanged by default.
const List<AnalogFeedbackConfig> kDefaultAnalogFeedbackChannels = [
  AnalogFeedbackConfig(
    channelKey: HoistNotification.hoist1Key,
    label: 'Load 1',
  ),
  AnalogFeedbackConfig(
    channelKey: HoistNotification.hoist2Key,
    label: 'Load 2',
  ),
];
