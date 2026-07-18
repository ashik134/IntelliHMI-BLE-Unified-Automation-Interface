import 'package:rev_crane_control_ops/models/plc_condition_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AlarmSeverity / AlarmIndicatorConfig
//
// AlarmIndicatorControl is a PLC STATUS-DRIVEN FEEDBACK widget: it renders
// whichever severity's PlcConditionConfig currently evaluates true (checked
// most-severe first — critical, then alarm, then warning), and never asserts
// a PLC output on its own (see AlarmIndicatorStrategy). Muted/acknowledged
// suppresses the visual/sound escalation for the current alarm without
// un-configuring the trigger itself — see `acknowledgeEnabled`.
// ─────────────────────────────────────────────────────────────────────────────

enum AlarmSeverity { normal, warning, alarm, critical, muted }

class AlarmIndicatorConfig {
  const AlarmIndicatorConfig({
    this.warningTrigger = const PlcConditionConfig(),
    this.alarmTrigger = const PlcConditionConfig(),
    this.criticalTrigger = const PlcConditionConfig(),
    this.acknowledgeEnabled = false,
    this.showStatusText = true,
    this.showTimestamp = false,
  });

  static const String customPropertiesKey = 'alarmIndicator';

  /// Each severity's live PLC condition, checked critical -> alarm -> warning
  /// -> normal (see AlarmIndicatorStrategy.severityFor). Any left unconfigured
  /// (empty watchedFields) never matches — an indicator with no triggers
  /// configured always reads Normal.
  final PlcConditionConfig warningTrigger;
  final PlcConditionConfig alarmTrigger;
  final PlcConditionConfig criticalTrigger;

  /// Whether a tap while Muted-eligible (an active, non-normal severity) is
  /// allowed to locally acknowledge/mute the display. This NEVER sends a PLC
  /// output — acknowledging only affects this widget's own rendered
  /// severity, matching "Do not send PLC output unless explicitly configured
  /// later" / "should not send PLC output unless explicitly designed later."
  final bool acknowledgeEnabled;

  final bool showStatusText;
  final bool showTimestamp;

  AlarmIndicatorConfig copyWith({
    PlcConditionConfig? warningTrigger,
    PlcConditionConfig? alarmTrigger,
    PlcConditionConfig? criticalTrigger,
    bool? acknowledgeEnabled,
    bool? showStatusText,
    bool? showTimestamp,
  }) {
    return AlarmIndicatorConfig(
      warningTrigger: warningTrigger ?? this.warningTrigger,
      alarmTrigger: alarmTrigger ?? this.alarmTrigger,
      criticalTrigger: criticalTrigger ?? this.criticalTrigger,
      acknowledgeEnabled: acknowledgeEnabled ?? this.acknowledgeEnabled,
      showStatusText: showStatusText ?? this.showStatusText,
      showTimestamp: showTimestamp ?? this.showTimestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'warningTrigger': warningTrigger.toJson(),
    'alarmTrigger': alarmTrigger.toJson(),
    'criticalTrigger': criticalTrigger.toJson(),
    'acknowledgeEnabled': acknowledgeEnabled,
    'showStatusText': showStatusText,
    'showTimestamp': showTimestamp,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory AlarmIndicatorConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) {
      return AlarmIndicatorConfig.fromJson(raw);
    }
    if (raw is Map) {
      return AlarmIndicatorConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const AlarmIndicatorConfig();
  }

  static PlcConditionConfig _readTrigger(Map<String, dynamic> json, String key) {
    final raw = json[key];
    return raw is Map
        ? PlcConditionConfig.fromJson(raw.cast<String, dynamic>())
        : const PlcConditionConfig();
  }

  factory AlarmIndicatorConfig.fromJson(Map<String, dynamic> json) {
    return AlarmIndicatorConfig(
      warningTrigger: _readTrigger(json, 'warningTrigger'),
      alarmTrigger: _readTrigger(json, 'alarmTrigger'),
      criticalTrigger: _readTrigger(json, 'criticalTrigger'),
      acknowledgeEnabled: json['acknowledgeEnabled'] as bool? ?? false,
      showStatusText: json['showStatusText'] as bool? ?? true,
      showTimestamp: json['showTimestamp'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmIndicatorConfig &&
          other.warningTrigger == warningTrigger &&
          other.alarmTrigger == alarmTrigger &&
          other.criticalTrigger == criticalTrigger &&
          other.acknowledgeEnabled == acknowledgeEnabled &&
          other.showStatusText == showStatusText &&
          other.showTimestamp == showTimestamp;

  @override
  int get hashCode => Object.hash(
    warningTrigger,
    alarmTrigger,
    criticalTrigger,
    acknowledgeEnabled,
    showStatusText,
    showTimestamp,
  );
}
