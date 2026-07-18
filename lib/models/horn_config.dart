import 'package:rev_crane_control_ops/models/plc_condition_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HornConfig
//
// Custom-properties bag for ButtonType.horn. The horn/buzzer is a PLC
// STATUS-DRIVEN FEEDBACK widget, never an output control: it never sends a
// PLC command of its own (see HornButtonStrategy) — [trigger] declares which
// live PLC output/status fields (PlcMapping variants, e.g. A2, A5+A6) make it
// sound, and [trigger.combinator] picks "any selected ON" vs "all selected
// ON". sound/haptic/pulse toggles only control the LOCAL presentation of an
// already-true condition; they never gate whether the condition itself is
// evaluated.
// ─────────────────────────────────────────────────────────────────────────────

enum HornSoundPattern { steady, pulsing, doubleBeep }

enum AlarmPriority { low, normal, high }

class HornConfig {
  const HornConfig({
    this.trigger = const PlcConditionConfig(),
    this.soundPattern = HornSoundPattern.steady,
    this.soundEnabled = true,
    this.hapticFeedback = true,
    this.visualPulseEnabled = true,
    this.priority = AlarmPriority.normal,
  });

  static const String customPropertiesKey = 'horn';

  /// Which live PLC output/status variants activate this buzzer, and
  /// whether any-of or all-of them must be ON. Empty = unconfigured = never
  /// sounds (see PlcConditionConfig.isActive).
  final PlcConditionConfig trigger;

  final HornSoundPattern soundPattern;
  final bool soundEnabled;
  final bool hapticFeedback;
  final bool visualPulseEnabled;
  final AlarmPriority priority;

  HornConfig copyWith({
    PlcConditionConfig? trigger,
    HornSoundPattern? soundPattern,
    bool? soundEnabled,
    bool? hapticFeedback,
    bool? visualPulseEnabled,
    AlarmPriority? priority,
  }) {
    return HornConfig(
      trigger: trigger ?? this.trigger,
      soundPattern: soundPattern ?? this.soundPattern,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      visualPulseEnabled: visualPulseEnabled ?? this.visualPulseEnabled,
      priority: priority ?? this.priority,
    );
  }

  Map<String, dynamic> toJson() => {
    'trigger': trigger.toJson(),
    'soundPattern': soundPattern.name,
    'soundEnabled': soundEnabled,
    'hapticFeedback': hapticFeedback,
    'visualPulseEnabled': visualPulseEnabled,
    'priority': priority.name,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory HornConfig.fromCustomProperties(Map<String, dynamic> properties) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return HornConfig.fromJson(raw);
    if (raw is Map) return HornConfig.fromJson(raw.cast<String, dynamic>());
    return const HornConfig();
  }

  factory HornConfig.fromJson(Map<String, dynamic> json) {
    final rawTrigger = json['trigger'];
    final trigger = rawTrigger is Map
        ? PlcConditionConfig.fromJson(rawTrigger.cast<String, dynamic>())
        : const PlcConditionConfig();
    return HornConfig(
      trigger: trigger,
      soundPattern: HornSoundPattern.values.firstWhere(
        (e) => e.name == json['soundPattern'],
        orElse: () => HornSoundPattern.steady,
      ),
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      visualPulseEnabled: json['visualPulseEnabled'] as bool? ?? true,
      priority: AlarmPriority.values.firstWhere(
        (e) => e.name == json['priority'],
        orElse: () => AlarmPriority.normal,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HornConfig &&
          other.trigger == trigger &&
          other.soundPattern == soundPattern &&
          other.soundEnabled == soundEnabled &&
          other.hapticFeedback == hapticFeedback &&
          other.visualPulseEnabled == visualPulseEnabled &&
          other.priority == priority;

  @override
  int get hashCode => Object.hash(
    trigger,
    soundPattern,
    soundEnabled,
    hapticFeedback,
    visualPulseEnabled,
    priority,
  );
}
