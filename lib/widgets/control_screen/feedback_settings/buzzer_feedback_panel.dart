import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/models/feedback/buzzer_feedback_config.dart';
import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Buzzer / Audible Alarm panel
//
//   More -> Feedback Settings -> Buzzer / Audible Alarm
//
// The layout's audible annunciator. Its activation is PLC-STATUS DRIVEN: only
// status the PLC has actually reported can start it, which is why sending an
// output never sounds it. The sound/haptic/pulse toggles below shape the LOCAL
// presentation of an already-true condition — they never gate whether the
// condition itself is evaluated.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showBuzzerFeedbackPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _BuzzerFeedbackPanel(),
  );
}

class _BuzzerFeedbackPanel extends StatelessWidget {
  const _BuzzerFeedbackPanel();

  void _update(BuildContext context, BuzzerFeedbackConfig next) {
    final controller = context.read<LayoutEditController>();
    controller.updateDraftFeedbackConfig(
      controller.draft.feedbackConfig.copyWith(buzzer: next),
    );
  }

  void _updateHorn(BuildContext context, HornConfig next) {
    final controller = context.read<LayoutEditController>();
    final feedback = controller.draft.feedbackConfig;
    _update(context, feedback.buzzer.copyWith(horn: next));
  }

  @override
  Widget build(BuildContext context) {
    final feedback = context
        .watch<LayoutEditController>()
        .draft
        .feedbackConfig;
    final buzzer = feedback.buzzer;
    final horn = buzzer.horn;

    return FeedbackSheetScaffold(
      title: 'Buzzer / Audible Alarm',
      subtitle: 'Activation source, sound behaviour and acknowledgement.',
      onBack: () => Navigator.of(context).pop(),
      closeLabel: 'Back to Feedback Settings',
      children: [
        const PropertyInfoBanner(
          text:
              'Only status received from the PLC can activate this local '
              'buzzer. Sending an output does not trigger it.',
        ),
        const PropertySectionHeader('Activation source', padTop: 4),
        PlcConditionEditor(
          title: 'Status fields',
          condition: horn.trigger,
          onChanged: (next) => _updateHorn(context, horn.copyWith(trigger: next)),
          emptyWarning: feedback.alarm.driveBuzzer
              ? null
              : 'No status field is selected, so the buzzer will stay idle. '
                    'You can also drive it from the Alarm Indicator, an analog '
                    'channel, or loss of communication.',
        ),
        if (feedback.alarm.driveBuzzer) ...[
          const SizedBox(height: 10),
          PropertyInfoBanner(
            text:
                'The Alarm Indicator is also configured to sound this buzzer '
                'from ${feedback.alarm.minimumBuzzerSeverity.name} severity '
                'upward.',
          ),
        ],
        const PropertySectionHeader('Local feedback'),
        PropertySwitchTile(
          title: 'Play local sound',
          subtitle: 'Sound starts only while the trigger is active.',
          value: horn.soundEnabled,
          onChanged: (value) =>
              _updateHorn(context, horn.copyWith(soundEnabled: value)),
        ),
        PropertySwitchTile(
          title: 'Haptic feedback',
          subtitle: 'Vibrate once when the trigger becomes active.',
          value: horn.hapticFeedback,
          onChanged: (value) =>
              _updateHorn(context, horn.copyWith(hapticFeedback: value)),
        ),
        PropertySwitchTile(
          title: 'Visual pulse',
          subtitle: 'Pulse the small horn icon while active.',
          value: horn.visualPulseEnabled,
          onChanged: (value) =>
              _updateHorn(context, horn.copyWith(visualPulseEnabled: value)),
        ),
        const PropertySectionHeader('Sound pattern'),
        PropertySegmented<HornSoundPattern>(
          options: const [
            (HornSoundPattern.steady, 'Steady'),
            (HornSoundPattern.pulsing, 'Pulsing'),
            (HornSoundPattern.doubleBeep, 'Double beep'),
          ],
          selected: horn.soundPattern,
          onChanged: (value) =>
              _updateHorn(context, horn.copyWith(soundPattern: value)),
        ),
        const PropertySectionHeader('Priority'),
        PropertySegmented<AlarmPriority>(
          options: const [
            (AlarmPriority.low, 'Low'),
            (AlarmPriority.normal, 'Normal'),
            (AlarmPriority.high, 'High'),
          ],
          selected: horn.priority,
          onChanged: (value) =>
              _updateHorn(context, horn.copyWith(priority: value)),
        ),
        const PropertySectionHeader('Acknowledgement'),
        PropertySwitchTile(
          title: 'Latched buzzer',
          subtitle:
              'Keep sounding after the trigger clears, until acknowledged.',
          value: buzzer.latched,
          onChanged: (value) =>
              _update(context, buzzer.copyWith(latched: value)),
        ),
        PropertySwitchTile(
          title: 'Allow silencing',
          subtitle:
              'Tap the AppBar buzzer to silence the current episode. It sounds '
              'again on the next activation.',
          value: buzzer.acknowledgeEnabled,
          onChanged: (value) =>
              _update(context, buzzer.copyWith(acknowledgeEnabled: value)),
        ),
        if (buzzer.latched && !buzzer.acknowledgeEnabled)
          const PropertyInfoBanner(
            text:
                'A latched buzzer with silencing off cannot be stopped by the '
                'operator once it starts.',
            isWarning: true,
          ),
        const PropertySectionHeader('Visibility'),
        PropertySwitchTile(
          title: 'AppBar indication',
          subtitle:
              'Show the compact buzzer beside the device title. Turning this '
              'off leaves it audible but invisible.',
          value: buzzer.showInAppBar,
          onChanged: (value) =>
              _update(context, buzzer.copyWith(showInAppBar: value)),
        ),
        if (!buzzer.showInAppBar && buzzer.acknowledgeEnabled)
          const PropertyInfoBanner(
            text:
                'With no AppBar indication there is nowhere to tap, so the '
                'buzzer cannot be silenced from the control screen.',
            isWarning: true,
          ),
      ],
    );
  }
}
