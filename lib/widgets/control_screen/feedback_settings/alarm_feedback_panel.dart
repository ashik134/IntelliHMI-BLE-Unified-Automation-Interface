import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/alarm_indicator_config.dart'
    show AlarmSeverity;
import 'package:rev_crane_control_ops/models/feedback/alarm_feedback_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart'
    show AlarmPriority;
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/color_picker_field.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Alarm Indicator panel
//
//   More -> Feedback Settings -> Alarm Indicator
//
// The layout-level annunciator: three PLC status conditions ranked
// warning < alarm < critical, plus how the resulting severity is presented
// (banner, AppBar, flashing, colour) and how it is cleared (latched,
// acknowledgement). Acknowledging is local — see FeedbackManager.acknowledge —
// so nothing configured here can write to the PLC.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showAlarmFeedbackPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AlarmFeedbackPanel(),
  );
}

class _AlarmFeedbackPanel extends StatelessWidget {
  const _AlarmFeedbackPanel();

  void _update(BuildContext context, AlarmFeedbackConfig next) {
    final controller = context.read<LayoutEditController>();
    controller.updateDraftFeedbackConfig(
      controller.draft.feedbackConfig.copyWith(alarm: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final config = context
        .watch<LayoutEditController>()
        .draft
        .feedbackConfig;
    final alarm = config.alarm;

    return FeedbackSheetScaffold(
      title: 'Alarm Indicator',
      subtitle: 'Severity triggers, presentation and acknowledgement.',
      onBack: () => Navigator.of(context).pop(),
      closeLabel: 'Back to Feedback Settings',
      children: [
        const PropertyInfoBanner(
          text:
              'Severities are evaluated critical first, then alarm, then '
              'warning, against status the PLC has confirmed. An unconfigured '
              'severity never matches.',
        ),
        const PropertySectionHeader('Name', padTop: 4),
        _AlarmLabelField(
          value: alarm.label,
          onChanged: (value) => _update(context, alarm.copyWith(label: value)),
        ),
        for (final severity in const [
          AlarmSeverity.warning,
          AlarmSeverity.alarm,
          AlarmSeverity.critical,
        ]) ...[
          PropertySectionHeader('${severity.displayLabel} trigger'),
          PlcConditionEditor(
            title: 'Feedback source',
            condition: alarm.triggerFor(severity),
            onChanged: (next) =>
                _update(context, alarm.withTrigger(severity, next)),
          ),
        ],
        if (!alarm.hasAnyTrigger) ...[
          const SizedBox(height: 12),
          const PropertyInfoBanner(
            text:
                'No severity has a trigger, so this alarm will always read '
                'Normal. Analog channels and loss of communication can still '
                'raise it if you enable those in their own areas.',
            isWarning: true,
          ),
        ],
        const PropertySectionHeader('Priority / severity behaviour'),
        PropertySegmented<AlarmPriority>(
          options: const [
            (AlarmPriority.low, 'Low'),
            (AlarmPriority.normal, 'Normal'),
            (AlarmPriority.high, 'High'),
          ],
          selected: alarm.priority,
          onChanged: (value) =>
              _update(context, alarm.copyWith(priority: value)),
        ),
        const SizedBox(height: 8),
        PropertySwitchTile(
          title: 'Latched alarm',
          subtitle:
              'Stay raised at the highest severity seen until acknowledged, '
              'even after the PLC condition clears.',
          value: alarm.latched,
          onChanged: (value) => _update(context, alarm.copyWith(latched: value)),
        ),
        PropertySwitchTile(
          title: 'Allow acknowledgement',
          subtitle:
              'Tap the banner or AppBar indicator to silence the current '
              'alarm. Local only — the PLC is never told.',
          value: alarm.acknowledgeEnabled,
          onChanged: (value) =>
              _update(context, alarm.copyWith(acknowledgeEnabled: value)),
        ),
        if (alarm.latched && !alarm.acknowledgeEnabled)
          const PropertyInfoBanner(
            text:
                'A latched alarm with acknowledgement off can only be cleared '
                'by restarting the session.',
            isWarning: true,
          ),
        const PropertySectionHeader('Presentation'),
        PropertySwitchTile(
          title: 'Alarm banner',
          subtitle: 'Overlay a severity banner across the top of the screen.',
          value: alarm.bannerEnabled,
          onChanged: (value) =>
              _update(context, alarm.copyWith(bannerEnabled: value)),
        ),
        PropertySwitchTile(
          title: 'AppBar indication',
          subtitle: 'Show a compact severity badge next to the device title.',
          value: alarm.appBarIndicatorEnabled,
          onChanged: (value) =>
              _update(context, alarm.copyWith(appBarIndicatorEnabled: value)),
        ),
        PropertySwitchTile(
          title: 'Flash while un-acknowledged',
          subtitle: 'Pulse the banner and badge until the alarm is cleared.',
          value: alarm.flashEnabled,
          onChanged: (value) =>
              _update(context, alarm.copyWith(flashEnabled: value)),
        ),
        const PropertySectionHeader('Indicator colours'),
        PropertyColorField(
          label: 'Warning',
          value: alarm.warningColor,
          onChanged: (color) => _update(
            context,
            alarm.copyWith(warningColor: color, clearWarningColor: color == null),
          ),
        ),
        PropertyColorField(
          label: 'Alarm',
          value: alarm.alarmColor,
          onChanged: (color) => _update(
            context,
            alarm.copyWith(alarmColor: color, clearAlarmColor: color == null),
          ),
        ),
        PropertyColorField(
          label: 'Critical',
          value: alarm.criticalColor,
          onChanged: (color) => _update(
            context,
            alarm.copyWith(
              criticalColor: color,
              clearCriticalColor: color == null,
            ),
          ),
        ),
        _SeverityPreview(config: alarm),
        const PropertySectionHeader('Buzzer link'),
        PropertySwitchTile(
          title: 'Sound the buzzer on alarm',
          subtitle:
              'Adds this alarm as a second activation source for the buzzer, '
              'alongside its own PLC trigger.',
          value: alarm.driveBuzzer,
          onChanged: (value) =>
              _update(context, alarm.copyWith(driveBuzzer: value)),
        ),
        if (alarm.driveBuzzer) ...[
          const SizedBox(height: 4),
          const Text(
            'Sound from severity',
            style: TextStyle(
              color: AppColors.darkText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          PropertySegmented<AlarmSeverity>(
            options: const [
              (AlarmSeverity.warning, 'Warning'),
              (AlarmSeverity.alarm, 'Alarm'),
              (AlarmSeverity.critical, 'Critical'),
            ],
            selected: alarm.minimumBuzzerSeverity,
            onChanged: (value) =>
                _update(context, alarm.copyWith(minimumBuzzerSeverity: value)),
          ),
        ],
      ],
    );
  }
}

class _AlarmLabelField extends StatefulWidget {
  const _AlarmLabelField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_AlarmLabelField> createState() => _AlarmLabelFieldState();
}

class _AlarmLabelFieldState extends State<_AlarmLabelField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PropertyTextField(
      controller: _controller,
      label: 'Alarm name',
      maxLength: 28,
      onChanged: widget.onChanged,
    );
  }
}

/// Swatch row showing the three severities as they will actually render, so a
/// custom colour can be judged against its neighbours rather than in isolation.
class _SeverityPreview extends StatelessWidget {
  const _SeverityPreview({required this.config});

  final AlarmFeedbackConfig config;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final severity in const [
          AlarmSeverity.warning,
          AlarmSeverity.alarm,
          AlarmSeverity.critical,
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FeedbackPalette.severity(
                    severity,
                    config: config,
                  ).withAlpha(38),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: FeedbackPalette.severity(severity, config: config),
                  ),
                ),
                child: Text(
                  severity.displayLabel.toUpperCase(),
                  style: TextStyle(
                    color: FeedbackPalette.severity(severity, config: config),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
