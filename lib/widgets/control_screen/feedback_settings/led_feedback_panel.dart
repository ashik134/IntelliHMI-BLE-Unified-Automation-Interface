import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart' show PlcType;
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/feedback/led_feedback_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/color_picker_field.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LED Indicator Row panel
//
//   More -> Feedback Settings -> LED Indicator Row
//
// Input/output feedback presentation. Each LED shows two independent values —
// the ring is what the app COMMANDED, the core what the PLC CONFIRMED — and
// this panel only styles them. Turning off "show pending state" makes both
// halves report the confirmed value, which removes the amber disagreement
// blink; it does not change what is sent, because this row never sends.
// ─────────────────────────────────────────────────────────────────────────────

/// Channels each PLC model exposes on the wire. PLC14/PLC21 carry the first
/// four fields; PLC38 carries all ten.
List<PlcOutputVariant> ledVariantsForPlc(PlcType plcType) {
  final count = plcType == PlcType.plc38 ? 10 : 4;
  return PlcOutputVariant.values.take(count).toList(growable: false);
}

Future<void> showLedFeedbackPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LedFeedbackPanel(),
  );
}

class _LedFeedbackPanel extends StatefulWidget {
  const _LedFeedbackPanel();

  @override
  State<_LedFeedbackPanel> createState() => _LedFeedbackPanelState();
}

class _LedFeedbackPanelState extends State<_LedFeedbackPanel> {
  PlcOutputVariant? _selected;

  void _updateRow(BuildContext context, LedRowFeedbackConfig next) {
    final controller = context.read<LayoutEditController>();
    controller.updateDraftFeedbackConfig(
      controller.draft.feedbackConfig.copyWith(ledRow: next),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final draft = editCtrl.draft;
    final row = draft.feedbackConfig.ledRow;
    final plcType = context.select<CraneController, PlcType>(
      (c) => c.connectedPlcType,
    );
    final variants = ledVariantsForPlc(plcType);
    final mapped = draft.mappedOutputVariants;
    final selected = _selected ?? variants.first;
    final channel = row.channelFor(selected);

    return FeedbackSheetScaffold(
      title: 'LED Indicator Row',
      subtitle: 'Per-channel labels, colours and pending behaviour.',
      onBack: () => Navigator.of(context).pop(),
      closeLabel: 'Back to Feedback Settings',
      children: [
        const PropertySectionHeader('Row', padTop: 4),
        PropertySwitchTile(
          title: 'Show LED row',
          subtitle: 'Master visibility for the whole indicator strip.',
          value: draft.arrangementConfig.showLiveLEDs,
          onChanged: (_) =>
              editCtrl.toggleArrangement(ArrangementToggle.liveLeds),
        ),
        PropertySwitchTile(
          title: 'Show commanded-vs-confirmed state',
          subtitle:
              'Blink amber while the app has commanded a channel the PLC has '
              'not confirmed yet. Off shows confirmed state only.',
          value: row.showPendingState,
          onChanged: (value) =>
              _updateRow(context, row.copyWith(showPendingState: value)),
        ),
        PropertySwitchTile(
          title: 'Show unmapped channels',
          subtitle:
              'Keep channels no control in this layout can drive, drawn as a '
              'dashed grey ring.',
          value: row.showUnmappedChannels,
          onChanged: (value) =>
              _updateRow(context, row.copyWith(showUnmappedChannels: value)),
        ),
        const PropertySectionHeader('Preview'),
        _RowPreview(row: row, variants: variants, mapped: mapped),
        const PropertySectionHeader('Channel'),
        PropertySegmented<PlcOutputVariant>(
          options: [
            for (final variant in variants)
              (
                variant,
                row.channelFor(variant).label ??
                    (variant.isEmergencyStop ? 'ESTOP' : variant.storageKey),
              ),
          ],
          selected: selected,
          onChanged: (value) => setState(() => _selected = value),
        ),
        const SizedBox(height: 10),
        if (selected.isEmergencyStop)
          const PropertyInfoBanner(
            text:
                'DF1 is the controller-owned E-STOP channel. Its appearance is '
                'configurable, but it is always driven by the safety path and '
                'can never be a feedback trigger elsewhere.',
          ),
        if (!mapped.contains(selected))
          const PropertyInfoBanner(
            text:
                'No control in this layout drives this channel, so it renders '
                'as a spare.',
          ),
        _ChannelEditor(
          key: ValueKey('led-channel-${selected.storageKey}'),
          variant: selected,
          config: channel,
          onChanged: (next) =>
              _updateRow(context, row.withChannel(selected, next)),
        ),
      ],
    );
  }
}

class _ChannelEditor extends StatefulWidget {
  const _ChannelEditor({
    super.key,
    required this.variant,
    required this.config,
    required this.onChanged,
  });

  final PlcOutputVariant variant;
  final LedChannelFeedbackConfig config;
  final ValueChanged<LedChannelFeedbackConfig> onChanged;

  @override
  State<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<_ChannelEditor> {
  late final TextEditingController _label;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(
      text:
          widget.config.label ??
          (widget.variant.isEmergencyStop
              ? 'ESTOP'
              : widget.variant.storageKey),
    );
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final variant = widget.variant;
    final onChanged = widget.onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PropertySwitchTile(
          title: 'Show this channel',
          value: config.visible,
          onChanged: (value) => onChanged(config.copyWith(visible: value)),
        ),
        const PropertySectionHeader('Label'),
        PropertyTextField(
          controller: _label,
          label: 'Channel name (${variant.storageKey})',
          maxLength: 8,
          onChanged: (value) {
            final trimmed = value.trim();
            onChanged(
              trimmed.isEmpty
                  ? config.copyWith(clearLabel: true)
                  : config.copyWith(label: trimmed),
            );
          },
        ),
        const PropertySectionHeader('Indicator colours'),
        PropertyColorField(
          label: 'Active (confirmed ON)',
          value: config.activeColor,
          onChanged: (color) => onChanged(
            config.copyWith(
              activeColor: color,
              clearActiveColor: color == null,
            ),
          ),
        ),
        PropertyColorField(
          label: 'Inactive / ready (confirmed OFF)',
          value: config.inactiveColor,
          onChanged: (color) => onChanged(
            config.copyWith(
              inactiveColor: color,
              clearInactiveColor: color == null,
            ),
          ),
        ),
        const Text(
          'Default leaves the LED dark when off, except E-STOP which shows a '
          'lit ready state.',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
        const PropertySectionHeader('Flashing / pulsing'),
        PropertySwitchTile(
          title: 'Pulse while inactive',
          subtitle:
              'Breathe the ready colour so a healthy channel reads as live '
              'rather than merely unlit. Needs an inactive colour.',
          value: FeedbackPalette.ledPulsesWhenInactive(variant, config),
          onChanged: (value) =>
              onChanged(config.copyWith(pulseWhenInactive: value)),
        ),
        PropertySwitchTile(
          title: 'Blink while pending',
          subtitle:
              'Blink amber on this channel while the command and the PLC '
              'readback disagree.',
          value: config.blinkWhenPending,
          onChanged: (value) =>
              onChanged(config.copyWith(blinkWhenPending: value)),
        ),
      ],
    );
  }
}

/// Renders the row exactly as the control screen will, from the draft config —
/// colours and labels can be judged in place instead of imagined.
class _RowPreview extends StatelessWidget {
  const _RowPreview({
    required this.row,
    required this.variants,
    required this.mapped,
  });

  final LedRowFeedbackConfig row;
  final List<PlcOutputVariant> variants;
  final Set<PlcOutputVariant> mapped;

  @override
  Widget build(BuildContext context) {
    final specs = <LedSpec>[];
    for (final variant in variants) {
      final channel = row.channelFor(variant);
      if (!channel.visible) continue;
      final isMapped = mapped.contains(variant);
      if (!isMapped && !row.showUnmappedChannels) continue;
      // A static, all-off preview: the point is to judge labels and colours,
      // not to mirror live plant state, which the row on the screen behind
      // this sheet is already showing.
      specs.add(
        LedSpec(
          label:
              channel.label ??
              (variant.isEmergencyStop ? 'ESTOP' : variant.storageKey),
          pin: variant.storageKey,
          active: false,
          color: FeedbackPalette.ledActive(variant, channel),
          inactiveColor: FeedbackPalette.ledInactive(variant, channel),
          pulseWhenInactive: FeedbackPalette.ledPulsesWhenInactive(
            variant,
            channel,
          ),
        ),
      );
    }
    if (specs.isEmpty) {
      return const PropertyInfoBanner(
        text: 'Every channel is hidden, so the row will not render.',
        isWarning: true,
      );
    }
    return LiveLedRow(leds: specs);
  }
}
