import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/feedback/system_feedback_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PLC Status & Communication panel
//
//   More -> Feedback Settings -> PLC Status & Communication
//
// Status indication that is about the link rather than any one field: the
// bottom status chip, the AppBar connection subtitle, and the derived
// heartbeat.
//
// The heartbeat is DERIVED, never transmitted. This PLC sends status on
// change, so "alive" means a notification arrived within the timeout — the app
// does not poll or ping to produce one, because a keep-alive write would be a
// control command, which feedback is never allowed to issue.
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showSystemFeedbackPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SystemFeedbackPanel(),
  );
}

class _SystemFeedbackPanel extends StatelessWidget {
  const _SystemFeedbackPanel();

  void _update(BuildContext context, SystemFeedbackConfig next) {
    final controller = context.read<LayoutEditController>();
    controller.updateDraftFeedbackConfig(
      controller.draft.feedbackConfig.copyWith(system: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final draft = editCtrl.draft;
    final system = draft.feedbackConfig.system;
    final health = context.watch<FeedbackManager>().snapshot.comms;

    return FeedbackSheetScaffold(
      title: 'PLC Status & Communication',
      subtitle: 'Status indication, heartbeat and loss-of-link behaviour.',
      onBack: () => Navigator.of(context).pop(),
      closeLabel: 'Back to Feedback Settings',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: FeedbackStatusChip(
            icon: Icons.wifi_tethering_rounded,
            label: FeedbackPalette.commsLabel(health),
            color: FeedbackPalette.comms(health),
          ),
        ),
        const PropertySectionHeader('Status indicators'),
        PropertySwitchTile(
          title: 'Status chip',
          subtitle:
              'The live "what the PLC is doing" chip along the bottom of the '
              'control body.',
          value: system.showStatusChip,
          onChanged: (value) =>
              _update(context, system.copyWith(showStatusChip: value)),
        ),
        PropertySwitchTile(
          title: 'Connection subtitle',
          subtitle: 'The small connection line under the AppBar title.',
          value: draft.arrangementConfig.showConnectionSubtitle,
          onChanged: (_) =>
              editCtrl.toggleArrangement(ArrangementToggle.connectionSubtitle),
        ),
        const PropertySectionHeader('Heartbeat'),
        const PropertyInfoBanner(
          text:
              'The PLC reports on change, so a quiet link is normal on an idle '
              'machine. Set the timeout above the longest expected quiet '
              'period.',
        ),
        PropertySwitchTile(
          title: 'Monitor communication',
          subtitle:
              'Report the link as stale when nothing has been received for '
              'longer than the timeout.',
          value: system.heartbeatEnabled,
          onChanged: (value) =>
              _update(context, system.copyWith(heartbeatEnabled: value)),
        ),
        if (system.heartbeatEnabled) ...[
          PropertyLabeledSlider(
            label: 'Timeout',
            value: system.heartbeatTimeoutSeconds.toDouble(),
            min: SystemFeedbackConfig.minHeartbeatTimeoutSeconds.toDouble(),
            max: SystemFeedbackConfig.maxHeartbeatTimeoutSeconds.toDouble(),
            divisions:
                SystemFeedbackConfig.maxHeartbeatTimeoutSeconds -
                SystemFeedbackConfig.minHeartbeatTimeoutSeconds,
            valueLabel: '${system.heartbeatTimeoutSeconds}s',
            onChanged: (value) => _update(
              context,
              system.copyWith(heartbeatTimeoutSeconds: value.round()),
            ),
          ),
          PropertySwitchTile(
            title: 'AppBar indication',
            subtitle: 'Show link health next to the device title.',
            value: system.showHeartbeatInAppBar,
            onChanged: (value) =>
                _update(context, system.copyWith(showHeartbeatInAppBar: value)),
          ),
        ],
        const PropertySectionHeader('Loss of communication'),
        PropertySwitchTile(
          title: 'Raise the alarm',
          subtitle:
              'A stale link raises Warning; a dropped link raises Critical.',
          value: system.raiseAlarmOnCommsLoss,
          onChanged: (value) =>
              _update(context, system.copyWith(raiseAlarmOnCommsLoss: value)),
        ),
        PropertySwitchTile(
          title: 'Sound the buzzer',
          value: system.soundBuzzerOnCommsLoss,
          onChanged: (value) =>
              _update(context, system.copyWith(soundBuzzerOnCommsLoss: value)),
        ),
        if ((system.raiseAlarmOnCommsLoss || system.soundBuzzerOnCommsLoss) &&
            !system.heartbeatEnabled)
          const PropertyInfoBanner(
            text:
                'With monitoring off, only a fully dropped connection can '
                'trigger these — a silent but connected link will not.',
          ),
      ],
    );
  }
}
