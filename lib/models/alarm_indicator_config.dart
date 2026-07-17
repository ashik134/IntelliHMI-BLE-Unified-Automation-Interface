// ─────────────────────────────────────────────────────────────────────────────
// AlarmSeverity / AlarmIndicatorConfig
//
// AlarmIndicatorControl is primarily a MONITOR widget, not an output control:
// it renders a severity it is TOLD (via activeState today; via real PLC
// status feedback once that transport exists — see AlarmIndicatorStrategy),
// and never asserts a PLC output on its own. AlarmIndicatorConfig is the
// custom-properties bag (mirrors PotentiometerConfig/HornConfig's shape)
// carrying only presentation + optional acknowledge-action settings.
//
// `acknowledgeEnabled` gates whether a tap on a Muted-eligible alarm is
// allowed to call back into ButtonConfig.stateMappings['acknowledge'] at
// all — this is the "optional acknowledge/mute action if configured" the
// design calls for. It defaults to false: an indicator dropped onto the
// canvas is inert (view-only) until the user explicitly opts in, exactly
// like PotentiometerConfig.outputEnabled defaults to false.
// ─────────────────────────────────────────────────────────────────────────────

enum AlarmSeverity { normal, warning, alarm, critical, muted }

class AlarmIndicatorConfig {
  const AlarmIndicatorConfig({
    this.acknowledgeEnabled = false,
    this.showStatusText = true,
    this.showTimestamp = false,
  });

  static const String customPropertiesKey = 'alarmIndicator';

  /// Whether a tap while in an acknowledgeable severity is allowed to emit
  /// the 'acknowledge' logical state via onCommand. False = pure display,
  /// no interaction — matching "Do not send PLC output unless explicitly
  /// configured later."
  final bool acknowledgeEnabled;

  final bool showStatusText;
  final bool showTimestamp;

  AlarmIndicatorConfig copyWith({
    bool? acknowledgeEnabled,
    bool? showStatusText,
    bool? showTimestamp,
  }) {
    return AlarmIndicatorConfig(
      acknowledgeEnabled: acknowledgeEnabled ?? this.acknowledgeEnabled,
      showStatusText: showStatusText ?? this.showStatusText,
      showTimestamp: showTimestamp ?? this.showTimestamp,
    );
  }

  Map<String, dynamic> toJson() => {
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

  factory AlarmIndicatorConfig.fromJson(Map<String, dynamic> json) {
    return AlarmIndicatorConfig(
      acknowledgeEnabled: json['acknowledgeEnabled'] as bool? ?? false,
      showStatusText: json['showStatusText'] as bool? ?? true,
      showTimestamp: json['showTimestamp'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlarmIndicatorConfig &&
          other.acknowledgeEnabled == acknowledgeEnabled &&
          other.showStatusText == showStatusText &&
          other.showTimestamp == showTimestamp;

  @override
  int get hashCode =>
      Object.hash(acknowledgeEnabled, showStatusText, showTimestamp);
}
