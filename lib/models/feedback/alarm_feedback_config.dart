import 'package:flutter/painting.dart' show Color;

import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/horn_config.dart'
    show AlarmPriority;
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlarmFeedbackConfig
//
// The LAYOUT-LEVEL alarm channel: one annunciator for the whole screen, fed by
// three PLC status conditions (warning / alarm / critical, evaluated
// most-severe first) plus, optionally, analog channels in their critical band
// and loss of communication. It is the escalation target every other feedback
// area points at, and — like every other feedback model here — it only ever
// READS PlcConditionConfig against CraneController.isReportedFieldActive. It
// cannot assert an output; acknowledging is local UI state (see
// FeedbackManager.acknowledge).
//
// Distinct from AlarmIndicatorConfig, which configures ONE placed alarm-
// indicator widget on the canvas. This one has no tile: it drives the banner,
// the AppBar indication, and the buzzer link.
// ─────────────────────────────────────────────────────────────────────────────

class AlarmFeedbackConfig {
  const AlarmFeedbackConfig({
    this.label = 'System Alarm',
    this.warningTrigger = const PlcConditionConfig(),
    this.alarmTrigger = const PlcConditionConfig(),
    this.criticalTrigger = const PlcConditionConfig(),
    this.priority = AlarmPriority.normal,
    this.latched = false,
    this.acknowledgeEnabled = true,
    this.flashEnabled = true,
    this.bannerEnabled = true,
    this.appBarIndicatorEnabled = true,
    this.driveBuzzer = false,
    this.minimumBuzzerSeverity = AlarmSeverity.alarm,
    this.warningColor,
    this.alarmColor,
    this.criticalColor,
  });

  /// Name shown on the banner and read out by the AppBar indicator's tooltip.
  final String label;

  /// Feedback SOURCE per severity. Each is an "any of"/"all of" set of PLC
  /// status fields; an unconfigured (empty) trigger never matches, so a
  /// layout that has configured nothing simply never annunciates.
  final PlcConditionConfig warningTrigger;
  final PlcConditionConfig alarmTrigger;
  final PlcConditionConfig criticalTrigger;

  /// Severity/priority of the annunciation itself — passed through to the
  /// buzzer tone when [driveBuzzer] is on.
  final AlarmPriority priority;

  /// Latched alarms stay raised after the trigger clears, until the operator
  /// acknowledges. Non-latched alarms follow the PLC exactly.
  final bool latched;

  /// Whether a tap on the banner / AppBar indicator may acknowledge. With
  /// [latched] on and this off, an alarm can only clear by the condition
  /// clearing — the standard "no silent bypass" configuration.
  final bool acknowledgeEnabled;

  /// Flashing/pulsing of the banner and indicator while un-acknowledged.
  final bool flashEnabled;

  /// Where the alarm shows: the overlay banner across the top of the control
  /// body, and/or the small AppBar indicator.
  final bool bannerEnabled;
  final bool appBarIndicatorEnabled;

  /// Whether reaching [minimumBuzzerSeverity] also sounds the layout buzzer.
  /// The buzzer's own PLC trigger is independent and still applies — this
  /// only adds the alarm as a second activation source.
  final bool driveBuzzer;
  final AlarmSeverity minimumBuzzerSeverity;

  /// Per-severity indicator colour overrides; null uses the standard
  /// amber/orange/red escalation palette.
  final Color? warningColor;
  final Color? alarmColor;
  final Color? criticalColor;

  bool get hasAnyTrigger =>
      warningTrigger.hasCondition ||
      alarmTrigger.hasCondition ||
      criticalTrigger.hasCondition;

  PlcConditionConfig triggerFor(AlarmSeverity severity) => switch (severity) {
    AlarmSeverity.critical => criticalTrigger,
    AlarmSeverity.alarm => alarmTrigger,
    AlarmSeverity.warning => warningTrigger,
    AlarmSeverity.normal || AlarmSeverity.muted => const PlcConditionConfig(),
  };

  AlarmFeedbackConfig withTrigger(
    AlarmSeverity severity,
    PlcConditionConfig trigger,
  ) => switch (severity) {
    AlarmSeverity.critical => copyWith(criticalTrigger: trigger),
    AlarmSeverity.alarm => copyWith(alarmTrigger: trigger),
    AlarmSeverity.warning => copyWith(warningTrigger: trigger),
    AlarmSeverity.normal || AlarmSeverity.muted => this,
  };

  Color? colorFor(AlarmSeverity severity) => switch (severity) {
    AlarmSeverity.critical => criticalColor,
    AlarmSeverity.alarm => alarmColor,
    AlarmSeverity.warning => warningColor,
    AlarmSeverity.normal || AlarmSeverity.muted => null,
  };

  /// Evaluates the three triggers most-severe first against a live field
  /// lookup — normally `CraneController.isReportedFieldActive`, never a
  /// commanded/optimistic value.
  AlarmSeverity severityFor(bool Function(PlcOutputVariant) fieldValue) {
    if (criticalTrigger.isActive(fieldValue)) return AlarmSeverity.critical;
    if (alarmTrigger.isActive(fieldValue)) return AlarmSeverity.alarm;
    if (warningTrigger.isActive(fieldValue)) return AlarmSeverity.warning;
    return AlarmSeverity.normal;
  }

  AlarmFeedbackConfig copyWith({
    String? label,
    PlcConditionConfig? warningTrigger,
    PlcConditionConfig? alarmTrigger,
    PlcConditionConfig? criticalTrigger,
    AlarmPriority? priority,
    bool? latched,
    bool? acknowledgeEnabled,
    bool? flashEnabled,
    bool? bannerEnabled,
    bool? appBarIndicatorEnabled,
    bool? driveBuzzer,
    AlarmSeverity? minimumBuzzerSeverity,
    Color? warningColor,
    Color? alarmColor,
    Color? criticalColor,
    bool clearWarningColor = false,
    bool clearAlarmColor = false,
    bool clearCriticalColor = false,
  }) {
    return AlarmFeedbackConfig(
      label: label ?? this.label,
      warningTrigger: warningTrigger ?? this.warningTrigger,
      alarmTrigger: alarmTrigger ?? this.alarmTrigger,
      criticalTrigger: criticalTrigger ?? this.criticalTrigger,
      priority: priority ?? this.priority,
      latched: latched ?? this.latched,
      acknowledgeEnabled: acknowledgeEnabled ?? this.acknowledgeEnabled,
      flashEnabled: flashEnabled ?? this.flashEnabled,
      bannerEnabled: bannerEnabled ?? this.bannerEnabled,
      appBarIndicatorEnabled:
          appBarIndicatorEnabled ?? this.appBarIndicatorEnabled,
      driveBuzzer: driveBuzzer ?? this.driveBuzzer,
      minimumBuzzerSeverity:
          minimumBuzzerSeverity ?? this.minimumBuzzerSeverity,
      warningColor: clearWarningColor ? null : (warningColor ?? this.warningColor),
      alarmColor: clearAlarmColor ? null : (alarmColor ?? this.alarmColor),
      criticalColor: clearCriticalColor
          ? null
          : (criticalColor ?? this.criticalColor),
    );
  }

  Map<String, dynamic> toJson() => {
    'label': label,
    'warningTrigger': warningTrigger.toJson(),
    'alarmTrigger': alarmTrigger.toJson(),
    'criticalTrigger': criticalTrigger.toJson(),
    'priority': priority.name,
    'latched': latched,
    'acknowledgeEnabled': acknowledgeEnabled,
    'flashEnabled': flashEnabled,
    'bannerEnabled': bannerEnabled,
    'appBarIndicatorEnabled': appBarIndicatorEnabled,
    'driveBuzzer': driveBuzzer,
    'minimumBuzzerSeverity': minimumBuzzerSeverity.name,
    'warningColor': warningColor?.toARGB32(),
    'alarmColor': alarmColor?.toARGB32(),
    'criticalColor': criticalColor?.toARGB32(),
  };

  static PlcConditionConfig _readTrigger(
    Map<String, dynamic> json,
    String key,
  ) {
    final raw = json[key];
    return raw is Map
        ? PlcConditionConfig.fromJson(raw.cast<String, dynamic>())
        : const PlcConditionConfig();
  }

  static Color? _readColor(Map<String, dynamic> json, String key) {
    final raw = json[key] as num?;
    return raw != null ? Color(raw.toInt()) : null;
  }

  factory AlarmFeedbackConfig.fromJson(Map<String, dynamic> json) {
    return AlarmFeedbackConfig(
      label: json['label'] as String? ?? 'System Alarm',
      warningTrigger: _readTrigger(json, 'warningTrigger'),
      alarmTrigger: _readTrigger(json, 'alarmTrigger'),
      criticalTrigger: _readTrigger(json, 'criticalTrigger'),
      priority: AlarmPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => AlarmPriority.normal,
      ),
      latched: json['latched'] as bool? ?? false,
      acknowledgeEnabled: json['acknowledgeEnabled'] as bool? ?? true,
      flashEnabled: json['flashEnabled'] as bool? ?? true,
      bannerEnabled: json['bannerEnabled'] as bool? ?? true,
      appBarIndicatorEnabled: json['appBarIndicatorEnabled'] as bool? ?? true,
      driveBuzzer: json['driveBuzzer'] as bool? ?? false,
      minimumBuzzerSeverity: AlarmSeverity.values.firstWhere(
        (e) => e.name == json['minimumBuzzerSeverity'],
        orElse: () => AlarmSeverity.alarm,
      ),
      warningColor: _readColor(json, 'warningColor'),
      alarmColor: _readColor(json, 'alarmColor'),
      criticalColor: _readColor(json, 'criticalColor'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmFeedbackConfig &&
          other.label == label &&
          other.warningTrigger == warningTrigger &&
          other.alarmTrigger == alarmTrigger &&
          other.criticalTrigger == criticalTrigger &&
          other.priority == priority &&
          other.latched == latched &&
          other.acknowledgeEnabled == acknowledgeEnabled &&
          other.flashEnabled == flashEnabled &&
          other.bannerEnabled == bannerEnabled &&
          other.appBarIndicatorEnabled == appBarIndicatorEnabled &&
          other.driveBuzzer == driveBuzzer &&
          other.minimumBuzzerSeverity == minimumBuzzerSeverity &&
          other.warningColor == warningColor &&
          other.alarmColor == alarmColor &&
          other.criticalColor == criticalColor;

  @override
  int get hashCode => Object.hash(
    label,
    warningTrigger,
    alarmTrigger,
    criticalTrigger,
    priority,
    latched,
    acknowledgeEnabled,
    flashEnabled,
    bannerEnabled,
    appBarIndicatorEnabled,
    driveBuzzer,
    minimumBuzzerSeverity,
    warningColor,
    alarmColor,
    criticalColor,
  );
}

/// Escalation order for the three annunciating severities plus normal.
/// `muted` is a presentation state (an acknowledged alarm), never a rank, so
/// it deliberately sorts below normal.
extension AlarmSeverityRank on AlarmSeverity {
  int get rank => switch (this) {
    AlarmSeverity.muted => -1,
    AlarmSeverity.normal => 0,
    AlarmSeverity.warning => 1,
    AlarmSeverity.alarm => 2,
    AlarmSeverity.critical => 3,
  };

  bool get isAnnunciating => rank > 0;

  String get displayLabel => switch (this) {
    AlarmSeverity.muted => 'Acknowledged',
    AlarmSeverity.normal => 'Normal',
    AlarmSeverity.warning => 'Warning',
    AlarmSeverity.alarm => 'Alarm',
    AlarmSeverity.critical => 'Critical',
  };
}
