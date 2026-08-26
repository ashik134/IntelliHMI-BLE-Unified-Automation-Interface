import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/feedback/feedback_settings_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/alarm_feedback_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/analog_feedback_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/buzzer_feedback_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/led_feedback_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/system_feedback_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Feedback Settings
//
//   Customization Toolbar -> More -> Feedback Settings
//
// The central configuration area for everything the app ANNUNCIATES: alarms,
// the buzzer, sensor/analog readings, the LED indicator row, PLC status and
// the communication heartbeat. Control-button configuration stays where it
// was — the Widgets catalogue and the Widget Properties sheet — and nothing
// reachable from here can send a PLC command; the whole feedback stack reads
// through FeedbackManager's write-free FeedbackSource.
//
// This file is the hub. Each area is a sheet of its own, opened on top so
// Back returns here rather than dropping the operator back onto the canvas.
// Every field writes to the LayoutEditController DRAFT, so changes preview
// live behind the sheet and reach SharedPreferences only on Save Layout /
// Done, exactly like every other customization surface.
// ─────────────────────────────────────────────────────────────────────────────

/// Opens the Feedback Settings hub. The whole visit — including any area
/// panels opened from it — collapses into a single undo entry (see
/// LayoutEditController.beginHistoryBatch), matching the Layout Settings and
/// Widget Properties sheets.
Future<void> showFeedbackSettingsSheet(BuildContext context) async {
  final editCtrl = context.read<LayoutEditController>();
  editCtrl.beginHistoryBatch();
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _FeedbackSettingsSheet(),
    );
  } finally {
    editCtrl.endHistoryBatch();
  }
}

class _FeedbackSettingsSheet extends StatelessWidget {
  const _FeedbackSettingsSheet();

  @override
  Widget build(BuildContext context) {
    final config = context.watch<LayoutEditController>().draft.feedbackConfig;
    final arrangement = context
        .watch<LayoutEditController>()
        .draft
        .arrangementConfig;

    return FeedbackSheetScaffold(
      title: 'Feedback Settings',
      subtitle:
          'Alarms, buzzer, sensor values, LED and status indication. '
          'Feedback reads PLC status only — it never sends a command.',
      children: [
        const _LiveFeedbackStrip(),
        const PropertySectionHeader('Annunciation', padTop: 14),
        FeedbackNavTile(
          icon: Icons.crisis_alert_rounded,
          title: 'Alarm Indicator',
          subtitle:
              'Warning / alarm / critical triggers, latching, acknowledgement, '
              'banner and AppBar indication.',
          summary: _alarmSummary(config),
          accent: FeedbackPalette.severity(AlarmSeverity.alarm),
          onTap: () => showAlarmFeedbackPanel(context),
        ),
        FeedbackNavTile(
          icon: Icons.campaign_rounded,
          title: 'Buzzer / Audible Alarm',
          subtitle:
              'PLC trigger, sound pattern, priority, haptics and visual pulse.',
          summary: _buzzerSummary(config),
          onTap: () => showBuzzerFeedbackPanel(context),
        ),
        const PropertySectionHeader('Values'),
        FeedbackNavTile(
          icon: Icons.speed_rounded,
          title: 'Sensor Readings & Analog Values',
          subtitle:
              'Source channel, label, units, min/max calibration, scaling, '
              'offset, warning and critical thresholds.',
          summary: _analogSummary(config, showRow: arrangement.showSensorRow),
          onTap: () => showAnalogFeedbackPanel(context),
        ),
        const PropertySectionHeader('Status'),
        FeedbackNavTile(
          icon: Icons.blur_circular_rounded,
          title: 'LED Indicator Row',
          subtitle:
              'Input/output feedback: per-channel labels, colours, pulsing '
              'and commanded-vs-confirmed behaviour.',
          summary: _ledSummary(config, showRow: arrangement.showLiveLEDs),
          onTap: () => showLedFeedbackPanel(context),
        ),
        FeedbackNavTile(
          icon: Icons.wifi_tethering_rounded,
          title: 'PLC Status & Communication',
          subtitle:
              'Status chip, connection subtitle, heartbeat timeout and '
              'loss-of-link escalation.',
          summary: _systemSummary(
            config,
            showSubtitle: arrangement.showConnectionSubtitle,
          ),
          onTap: () => showSystemFeedbackPanel(context),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summaries
// ─────────────────────────────────────────────────────────────────────────────

String _alarmSummary(FeedbackSettingsConfig config) {
  final alarm = config.alarm;
  if (!alarm.hasAnyTrigger) return 'No severity trigger configured';
  final configured = <String>[
    if (alarm.warningTrigger.hasCondition) 'Warning',
    if (alarm.alarmTrigger.hasCondition) 'Alarm',
    if (alarm.criticalTrigger.hasCondition) 'Critical',
  ].join(' · ');
  final mode = alarm.latched ? 'latched' : 'non-latched';
  return '$configured · $mode';
}

String _buzzerSummary(FeedbackSettingsConfig config) {
  final buzzer = config.buzzer;
  if (!buzzer.horn.trigger.hasCondition && !config.alarm.driveBuzzer) {
    return 'No activation source — silent';
  }
  final watched = buzzer.horn.trigger.watchedFields.length;
  final source = watched == 0
      ? 'Alarm-driven'
      : '$watched status field${watched == 1 ? '' : 's'}';
  return '$source · ${buzzer.soundEnabled ? 'sound on' : 'sound off'} · '
      '${buzzer.priority.name} priority';
}

String _analogSummary(FeedbackSettingsConfig config, {required bool showRow}) {
  if (!showRow) return 'Sensor row hidden';
  final visible = config.visibleAnalogChannels;
  if (visible.isEmpty) return 'No reader visible';
  final scaled = visible.where((c) => !c.isUnscaled).length;
  final units = visible
      .map((c) => c.unit.trim())
      .where((u) => u.isNotEmpty)
      .toSet();
  final suffix = scaled == 0
      ? 'firmware values'
      : units.isEmpty
      ? '$scaled scaled'
      : units.join(', ');
  return '${visible.length} reader${visible.length == 1 ? '' : 's'} · $suffix';
}

String _ledSummary(FeedbackSettingsConfig config, {required bool showRow}) {
  if (!showRow) return 'LED row hidden';
  final customized = config.ledRow.channels.length;
  final pending = config.ledRow.showPendingState
      ? 'pending shown'
      : 'confirmed only';
  return customized == 0
      ? 'Default channels · $pending'
      : '$customized channel${customized == 1 ? '' : 's'} customized · $pending';
}

String _systemSummary(
  FeedbackSettingsConfig config, {
  required bool showSubtitle,
}) {
  final system = config.system;
  final parts = <String>[
    system.showStatusChip ? 'Status chip on' : 'Status chip off',
    if (showSubtitle) 'subtitle on',
    system.heartbeatEnabled
        ? 'heartbeat ${system.heartbeatTimeoutSeconds}s'
        : 'heartbeat off',
  ];
  return parts.join(' · ');
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiveFeedbackStrip
// ─────────────────────────────────────────────────────────────────────────────

/// What FeedbackManager is resolving right now, shown inside the settings
/// screen so a trigger can be verified against the live plant without closing
/// the sheet. Read-only — tapping nothing here changes any state.
class _LiveFeedbackStrip extends StatelessWidget {
  const _LiveFeedbackStrip();

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FeedbackManager>();
    final snapshot = manager.snapshot;
    final severityColor = FeedbackPalette.severity(
      snapshot.severity,
      config: manager.config.alarm,
    );
    final statusChips = <Widget>[
      FeedbackStatusChip(
        icon: snapshot.isAnnunciating
            ? Icons.warning_amber_rounded
            : Icons.check_circle_outline_rounded,
        label: snapshot.severity.displayLabel,
        color: severityColor,
        expanded: true,
      ),
      FeedbackStatusChip(
        icon: snapshot.buzzerActive
            ? Icons.campaign_rounded
            : Icons.notifications_off_outlined,
        label: snapshot.buzzerActive ? 'Buzzer active' : 'Buzzer idle',
        color: snapshot.buzzerActive
            ? AppColors.fastColorLight
            : AppColors.darkTextMuted,
        expanded: true,
      ),
      FeedbackStatusChip(
        icon: Icons.wifi_tethering_rounded,
        label: FeedbackPalette.commsLabel(snapshot.comms),
        color: FeedbackPalette.comms(snapshot.comms),
        expanded: true,
      ),
      for (final reading in snapshot.analog)
        FeedbackStatusChip(
          icon: Icons.speed_rounded,
          label:
              '${reading.displayLabel} '
              '${reading.value.toStringAsFixed(reading.config.isUnscaled ? 0 : 1)}'
              '${reading.config.unit.isEmpty ? '' : ' ${reading.config.unit}'}',
          color: FeedbackPalette.analogZone(reading.zone, AppColors.darkInfo),
          expanded: true,
        ),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.selectionViolet,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(dimension: 7),
              ),
              SizedBox(width: 7),
              Text(
                'LIVE STATUS',
                style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.05,
                ),
              ),
              Spacer(),
              Icon(
                Icons.sync_rounded,
                size: 13,
                color: AppColors.darkTextMuted,
              ),
              SizedBox(width: 5),
              Text(
                'Updates in real time',
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final preferredColumns = constraints.maxWidth >= 840
                  ? 5
                  : constraints.maxWidth >= 520
                  ? 3
                  : constraints.maxWidth >= 300
                  ? 2
                  : 1;
              final columns = statusChips.length < preferredColumns
                  ? statusChips.length
                  : preferredColumns;
              final chipWidth =
                  (constraints.maxWidth - ((columns - 1) * 8)) / columns;

              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final chip in statusChips)
                    SizedBox(width: chipWidth, child: chip),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
