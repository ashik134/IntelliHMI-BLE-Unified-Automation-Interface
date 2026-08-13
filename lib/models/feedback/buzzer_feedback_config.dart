import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/models/plc_condition_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

/// Fresh layouts sound the buzzer when any non-E-STOP digital status reported
/// by the PLC is active. DF1 keeps its dedicated safety indication and is
/// never a feedback trigger (see PlcConditionConfig.watchedFields).
const HornConfig kDefaultBuzzerHornConfig = HornConfig(
  trigger: PlcConditionConfig(
    watchedFields: <PlcOutputVariant>{
      PlcOutputVariant.df2,
      PlcOutputVariant.df3,
      PlcOutputVariant.df4,
      PlcOutputVariant.df5,
      PlcOutputVariant.df6,
      PlcOutputVariant.df7,
      PlcOutputVariant.df8,
      PlcOutputVariant.df9,
      PlcOutputVariant.df10,
    },
  ),
  hapticFeedback: false,
);

// ─────────────────────────────────────────────────────────────────────────────
// BuzzerFeedbackConfig
//
// The layout's audible-alarm channel. [horn] is the existing HornConfig — PLC
// trigger condition, sound pattern, priority, and the local sound/haptic/pulse
// toggles — shared verbatim with the in-canvas horn widget so one mental model
// covers both. The fields added here are the ones that only make sense for the
// layout-wide buzzer: where it is shown, and how an operator may silence it.
//
// Like every feedback model, this only ever READS PLC status. Silencing is
// local presentation state held by FeedbackManager; it never writes an output,
// so acknowledging the app's buzzer cannot acknowledge the plant's.
// ─────────────────────────────────────────────────────────────────────────────

class BuzzerFeedbackConfig {
  const BuzzerFeedbackConfig({
    this.horn = kDefaultBuzzerHornConfig,
    this.showInAppBar = true,
    this.latched = false,
    this.acknowledgeEnabled = true,
  });

  /// Trigger + sound behaviour. See HornConfig.
  final HornConfig horn;

  /// AppBar indication — the small compact horn beside the device title.
  /// Turning this off leaves the buzzer audible but with no visual presence.
  final bool showInAppBar;

  /// Keeps sounding after the trigger clears until acknowledged. With
  /// [acknowledgeEnabled] off as well, a latched buzzer can only be silenced
  /// by disabling its sound in these settings — deliberately awkward, since
  /// that combination has no operator-facing escape.
  final bool latched;

  /// Whether tapping the AppBar indicator silences the current episode.
  final bool acknowledgeEnabled;

  /// Convenience passthroughs — the sheets and the manager both read these far
  /// more often than the nested [horn] itself.
  bool get soundEnabled => horn.soundEnabled;
  AlarmPriority get priority => horn.priority;
  HornSoundPattern get soundPattern => horn.soundPattern;

  BuzzerFeedbackConfig copyWith({
    HornConfig? horn,
    bool? showInAppBar,
    bool? latched,
    bool? acknowledgeEnabled,
  }) {
    return BuzzerFeedbackConfig(
      horn: horn ?? this.horn,
      showInAppBar: showInAppBar ?? this.showInAppBar,
      latched: latched ?? this.latched,
      acknowledgeEnabled: acknowledgeEnabled ?? this.acknowledgeEnabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'horn': horn.toJson(),
    'showInAppBar': showInAppBar,
    'latched': latched,
    'acknowledgeEnabled': acknowledgeEnabled,
  };

  factory BuzzerFeedbackConfig.fromJson(Map<String, dynamic> json) {
    final rawHorn = json['horn'];
    return BuzzerFeedbackConfig(
      horn: rawHorn is Map
          ? HornConfig.fromJson(rawHorn.cast<String, dynamic>())
          : kDefaultBuzzerHornConfig,
      showInAppBar: json['showInAppBar'] as bool? ?? true,
      latched: json['latched'] as bool? ?? false,
      acknowledgeEnabled: json['acknowledgeEnabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BuzzerFeedbackConfig &&
          other.horn == horn &&
          other.showInAppBar == showInAppBar &&
          other.latched == latched &&
          other.acknowledgeEnabled == acknowledgeEnabled;

  @override
  int get hashCode =>
      Object.hash(horn, showInAppBar, latched, acknowledgeEnabled);
}
