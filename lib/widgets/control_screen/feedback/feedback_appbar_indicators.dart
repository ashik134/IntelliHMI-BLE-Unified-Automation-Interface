import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/compact_plc_status_buzzer.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeedbackAppBarIndicators
//
// The AppBar end of the feedback architecture: alarm severity, link health and
// the buzzer, each shown only when its own area of Feedback Settings asks for
// AppBar indication. Every value comes from FeedbackManager already resolved —
// these widgets evaluate nothing and command nothing.
// ─────────────────────────────────────────────────────────────────────────────

class FeedbackAppBarIndicators extends StatelessWidget {
  const FeedbackAppBarIndicators({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FeedbackManager>();
    final config = manager.config;
    final snapshot = manager.snapshot;

    final showAlarm =
        config.alarm.appBarIndicatorEnabled &&
        (snapshot.severity.isAnnunciating || snapshot.acknowledged);
    final showComms = config.system.showHeartbeatInAppBar;
    final showBuzzer = config.buzzer.showInAppBar;

    if (!showAlarm && !showComms && !showBuzzer) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showAlarm) ...[
          const SizedBox(width: 8),
          _AlarmBadge(
            severity: snapshot.acknowledged
                ? AlarmSeverity.muted
                : snapshot.severity,
            rawSeverity: snapshot.rawSeverity,
            config: config.alarm,
            onAcknowledge:
                config.alarm.acknowledgeEnabled && !snapshot.acknowledged
                ? manager.acknowledge
                : null,
          ),
        ],
        if (showComms) ...[
          const SizedBox(width: 8),
          _CommsBadge(health: snapshot.comms),
        ],
        if (showBuzzer) ...[
          const SizedBox(width: 8),
          CompactPlcStatusBuzzer(
            config: config.buzzer.horn,
            isActive: snapshot.buzzerActive,
            onSilence:
                config.buzzer.acknowledgeEnabled && snapshot.buzzerActive
                ? manager.acknowledge
                : null,
          ),
        ],
      ],
    );
  }
}

class _AlarmBadge extends StatelessWidget {
  const _AlarmBadge({
    required this.severity,
    required this.rawSeverity,
    required this.config,
    required this.onAcknowledge,
  });

  final AlarmSeverity severity;
  final AlarmSeverity rawSeverity;
  final AlarmFeedbackConfig config;

  /// Null when acknowledgement is off or the alarm is already acknowledged —
  /// the badge then reports without being tappable.
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackPalette.severity(severity, config: config);
    final message = severity == AlarmSeverity.muted
        ? '${config.label} acknowledged — still ${rawSeverity.displayLabel}'
        : '${config.label} — ${severity.displayLabel}'
              '${onAcknowledge != null ? '. Tap to acknowledge.' : ''}';

    return Tooltip(
      message: message,
      child: GestureDetector(
        onTap: onAcknowledge,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withAlpha(50),
            shape: BoxShape.circle,
            border: Border.all(color: color),
          ),
          child: Icon(
            severity == AlarmSeverity.muted
                ? Icons.notifications_paused_rounded
                : Icons.warning_amber_rounded,
            size: 16,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _CommsBadge extends StatelessWidget {
  const _CommsBadge({required this.health});

  final CommsHealth health;

  @override
  Widget build(BuildContext context) {
    final color = FeedbackPalette.comms(health);
    return Tooltip(
      message: '${FeedbackPalette.commsLabel(health)} — derived from PLC '
          'status notifications, not a poll',
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.idleColor.withAlpha(120),
          shape: BoxShape.circle,
          border: Border.all(color: color.withAlpha(150)),
        ),
        child: Icon(
          switch (health) {
            CommsHealth.live => Icons.wifi_tethering_rounded,
            CommsHealth.stale => Icons.wifi_tethering_error_rounded_outlined,
            CommsHealth.offline => Icons.wifi_tethering_off_rounded,
          },
          size: 16,
          color: color,
        ),
      ),
    );
  }
}
