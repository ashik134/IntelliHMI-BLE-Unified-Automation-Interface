// ─────────────────────────────────────────────────────────────────────────────
// SystemFeedbackConfig
//
// PLC STATUS + COMMUNICATION/HEARTBEAT indication — the feedback that is about
// the link itself rather than about any one field. The heartbeat is derived,
// not transmitted: the PLC does not send a dedicated keep-alive, so "alive"
// means "a status notification arrived within [heartbeatTimeoutSeconds]" (see
// FeedbackManager, which times it against CraneController.lastPlcStatusAt).
//
// Nothing here polls or pings the PLC — a heartbeat implemented by writing to
// the device would be a control command, which feedback is never allowed to
// issue. Silence is simply observed.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolved health of the PLC link, most-healthy first.
enum CommsHealth {
  /// Connected and a status notification arrived within the timeout.
  live,

  /// Connected, but nothing has been heard for longer than the timeout.
  stale,

  /// Transport is down.
  offline,
}

class SystemFeedbackConfig {
  const SystemFeedbackConfig({
    this.showStatusChip = true,
    this.heartbeatEnabled = true,
    this.heartbeatTimeoutSeconds = defaultHeartbeatTimeoutSeconds,
    this.showHeartbeatInAppBar = true,
    this.raiseAlarmOnCommsLoss = false,
    this.soundBuzzerOnCommsLoss = false,
  });

  static const int defaultHeartbeatTimeoutSeconds = 10;
  static const int minHeartbeatTimeoutSeconds = 2;
  static const int maxHeartbeatTimeoutSeconds = 120;

  /// The live status chip along the bottom of the control body
  /// (StatusBarChip) — the layout's plain "what is the PLC doing right now"
  /// readout.
  final bool showStatusChip;

  /// Whether staleness is evaluated at all. Off means the link is only ever
  /// reported as [CommsHealth.live] or [CommsHealth.offline], from the
  /// transport's own connection state.
  final bool heartbeatEnabled;

  /// Silence tolerated before the link is called [CommsHealth.stale].
  final int heartbeatTimeoutSeconds;

  /// AppBar indication for the link's health.
  final bool showHeartbeatInAppBar;

  /// Whether losing the link escalates the layout alarm / sounds the buzzer.
  /// Both default off: on a hand-held HMI a normal walk-out-of-range should
  /// not read as a plant alarm unless the site wants it to.
  final bool raiseAlarmOnCommsLoss;
  final bool soundBuzzerOnCommsLoss;

  Duration get heartbeatTimeout => Duration(seconds: heartbeatTimeoutSeconds);

  SystemFeedbackConfig copyWith({
    bool? showStatusChip,
    bool? heartbeatEnabled,
    int? heartbeatTimeoutSeconds,
    bool? showHeartbeatInAppBar,
    bool? raiseAlarmOnCommsLoss,
    bool? soundBuzzerOnCommsLoss,
  }) {
    return SystemFeedbackConfig(
      showStatusChip: showStatusChip ?? this.showStatusChip,
      heartbeatEnabled: heartbeatEnabled ?? this.heartbeatEnabled,
      heartbeatTimeoutSeconds:
          (heartbeatTimeoutSeconds ?? this.heartbeatTimeoutSeconds).clamp(
            minHeartbeatTimeoutSeconds,
            maxHeartbeatTimeoutSeconds,
          ),
      showHeartbeatInAppBar:
          showHeartbeatInAppBar ?? this.showHeartbeatInAppBar,
      raiseAlarmOnCommsLoss:
          raiseAlarmOnCommsLoss ?? this.raiseAlarmOnCommsLoss,
      soundBuzzerOnCommsLoss:
          soundBuzzerOnCommsLoss ?? this.soundBuzzerOnCommsLoss,
    );
  }

  Map<String, dynamic> toJson() => {
    'showStatusChip': showStatusChip,
    'heartbeatEnabled': heartbeatEnabled,
    'heartbeatTimeoutSeconds': heartbeatTimeoutSeconds,
    'showHeartbeatInAppBar': showHeartbeatInAppBar,
    'raiseAlarmOnCommsLoss': raiseAlarmOnCommsLoss,
    'soundBuzzerOnCommsLoss': soundBuzzerOnCommsLoss,
  };

  factory SystemFeedbackConfig.fromJson(Map<String, dynamic> json) {
    final timeout =
        (json['heartbeatTimeoutSeconds'] as num?)?.toInt() ??
        defaultHeartbeatTimeoutSeconds;
    return SystemFeedbackConfig(
      showStatusChip: json['showStatusChip'] as bool? ?? true,
      heartbeatEnabled: json['heartbeatEnabled'] as bool? ?? true,
      heartbeatTimeoutSeconds: timeout.clamp(
        minHeartbeatTimeoutSeconds,
        maxHeartbeatTimeoutSeconds,
      ),
      showHeartbeatInAppBar: json['showHeartbeatInAppBar'] as bool? ?? true,
      raiseAlarmOnCommsLoss: json['raiseAlarmOnCommsLoss'] as bool? ?? false,
      soundBuzzerOnCommsLoss: json['soundBuzzerOnCommsLoss'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SystemFeedbackConfig &&
          other.showStatusChip == showStatusChip &&
          other.heartbeatEnabled == heartbeatEnabled &&
          other.heartbeatTimeoutSeconds == heartbeatTimeoutSeconds &&
          other.showHeartbeatInAppBar == showHeartbeatInAppBar &&
          other.raiseAlarmOnCommsLoss == raiseAlarmOnCommsLoss &&
          other.soundBuzzerOnCommsLoss == soundBuzzerOnCommsLoss;

  @override
  int get hashCode => Object.hash(
    showStatusChip,
    heartbeatEnabled,
    heartbeatTimeoutSeconds,
    showHeartbeatInAppBar,
    raiseAlarmOnCommsLoss,
    soundBuzzerOnCommsLoss,
  );
}
