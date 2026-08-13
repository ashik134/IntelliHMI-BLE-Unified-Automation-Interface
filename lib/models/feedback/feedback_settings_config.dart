import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/buzzer_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/led_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackSettingsConfig
//
// Every non-control feedback/status setting in one bag — the model behind
// Customization Toolbar -> More -> Feedback Settings. It is deliberately kept
// separate from ButtonConfig and from the control-button configuration path:
// a feedback area describes how the app ANNUNCIATES what the PLC, the sensors
// and the transport report, and nothing here can ever produce a PLC write.
//
//   PLC / Sensor / System Status
//           |
//     FeedbackManager        <- reads this config, resolves live state
//           |
//   Alarm / Buzzer / LED / Value / Status UI
//
// Adding a new feedback area means adding a field here, a section to
// FeedbackSettingsSheet, and a resolver in FeedbackManager — the three places
// the architecture above names, and no others.
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackSettingsConfig {
  const FeedbackSettingsConfig({
    this.buzzer = const BuzzerFeedbackConfig(),
    this.alarm = const AlarmFeedbackConfig(),
    this.analogChannels = kDefaultAnalogFeedbackChannels,
    this.ledRow = const LedRowFeedbackConfig(),
    this.system = const SystemFeedbackConfig(),
  });

  /// Audible alarm — PLC trigger, pattern, priority, AppBar presence.
  final BuzzerFeedbackConfig buzzer;

  /// Layout-level alarm annunciator — severity triggers, latching,
  /// acknowledgement, banner/AppBar indication.
  final AlarmFeedbackConfig alarm;

  /// Analog value readers / sensor readings, in display order.
  final List<AnalogFeedbackConfig> analogChannels;

  /// Input/output feedback — the live LED indicator row.
  final LedRowFeedbackConfig ledRow;

  /// PLC status indication and communication/heartbeat health.
  final SystemFeedbackConfig system;

  List<AnalogFeedbackConfig> get visibleAnalogChannels => [
    for (final channel in analogChannels)
      if (channel.visible) channel,
  ];

  FeedbackSettingsConfig copyWith({
    BuzzerFeedbackConfig? buzzer,
    AlarmFeedbackConfig? alarm,
    List<AnalogFeedbackConfig>? analogChannels,
    LedRowFeedbackConfig? ledRow,
    SystemFeedbackConfig? system,
  }) {
    return FeedbackSettingsConfig(
      buzzer: buzzer ?? this.buzzer,
      alarm: alarm ?? this.alarm,
      analogChannels: analogChannels ?? this.analogChannels,
      ledRow: ledRow ?? this.ledRow,
      system: system ?? this.system,
    );
  }

  Map<String, dynamic> toJson() => {
    'buzzer': buzzer.toJson(),
    'alarm': alarm.toJson(),
    'analogChannels': [for (final c in analogChannels) c.toJson()],
    'ledRow': ledRow.toJson(),
    'system': system.toJson(),
  };

  factory FeedbackSettingsConfig.fromJson(Map<String, dynamic> json) {
    final rawChannels = json['analogChannels'];
    final channels = <AnalogFeedbackConfig>[];
    if (rawChannels is List) {
      for (final raw in rawChannels) {
        if (raw is Map) {
          channels.add(
            AnalogFeedbackConfig.fromJson(raw.cast<String, dynamic>()),
          );
        }
      }
    }
    return FeedbackSettingsConfig(
      buzzer: _read(json, 'buzzer', BuzzerFeedbackConfig.fromJson) ??
          const BuzzerFeedbackConfig(),
      alarm: _read(json, 'alarm', AlarmFeedbackConfig.fromJson) ??
          const AlarmFeedbackConfig(),
      // An explicitly empty list is a valid choice (all readers removed); only
      // a missing key falls back to the stock channels.
      analogChannels: rawChannels is List
          ? channels
          : kDefaultAnalogFeedbackChannels,
      ledRow: _read(json, 'ledRow', LedRowFeedbackConfig.fromJson) ??
          const LedRowFeedbackConfig(),
      system: _read(json, 'system', SystemFeedbackConfig.fromJson) ??
          const SystemFeedbackConfig(),
    );
  }

  static T? _read<T>(
    Map<String, dynamic> json,
    String key,
    T Function(Map<String, dynamic>) parse,
  ) {
    final raw = json[key];
    if (raw is Map) return parse(raw.cast<String, dynamic>());
    return null;
  }

  /// Builds the pre-Feedback-Settings shape: layouts saved at schemaVersion 10
  /// stored the AppBar buzzer as a bare [HornConfig] under
  /// `appBarBuzzerConfig`, and had no other feedback configuration at all.
  /// Everything else takes its default, which reproduces the old rendering
  /// exactly — so an upgrading install sees no visual change until it opens
  /// Feedback Settings.
  factory FeedbackSettingsConfig.fromLegacyBuzzer(HornConfig horn) {
    return FeedbackSettingsConfig(buzzer: BuzzerFeedbackConfig(horn: horn));
  }

  static bool _channelsEqual(
    List<AnalogFeedbackConfig> a,
    List<AnalogFeedbackConfig> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedbackSettingsConfig &&
          other.buzzer == buzzer &&
          other.alarm == alarm &&
          other.ledRow == ledRow &&
          other.system == system &&
          _channelsEqual(other.analogChannels, analogChannels);

  @override
  int get hashCode => Object.hash(
    buzzer,
    alarm,
    ledRow,
    system,
    Object.hashAll(analogChannels),
  );
}
