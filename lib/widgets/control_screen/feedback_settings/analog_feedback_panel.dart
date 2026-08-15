import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/feedback_manager.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/hoist_notification.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback/feedback_palette.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_widgets.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/color_picker_field.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties/property_field_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Sensor Readings & Analog Values panel
//
//   More -> Feedback Settings -> Sensor Readings & Analog Values
//
// One editor per analog READER. A reader watches an H1/H2 channel the PLC
// pushes over the analog characteristic and can turn that firmware-scaled
// value into an engineering value: min/max calibration first, then the
// engineering span it maps onto, then a field offset. Thresholds band the
// result; the gauge, alarm link and buzzer link all read that band. Nothing
// here writes an analog output.
// ─────────────────────────────────────────────────────────────────────────────

/// Channel keys the firmware currently reports. A reader may point at any of
/// them; two readers on the same key is a legitimate (if unusual) dual
/// display, not an error.
const List<String> kKnownAnalogChannelKeys = HoistNotification.channelKeys;

Future<void> showAnalogFeedbackPanel(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AnalogFeedbackPanel(),
  );
}

class _AnalogFeedbackPanel extends StatefulWidget {
  const _AnalogFeedbackPanel();

  @override
  State<_AnalogFeedbackPanel> createState() => _AnalogFeedbackPanelState();
}

class _AnalogFeedbackPanelState extends State<_AnalogFeedbackPanel> {
  int _selected = 0;

  void _updateChannel(int index, AnalogFeedbackConfig next) {
    final controller = context.read<LayoutEditController>();
    final feedback = controller.draft.feedbackConfig;
    if (index < 0 || index >= feedback.analogChannels.length) return;
    final channels = [...feedback.analogChannels];
    channels[index] = next;
    controller.updateDraftFeedbackConfig(
      feedback.copyWith(analogChannels: channels),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final feedback = editCtrl.draft.feedbackConfig;
    final channels = feedback.analogChannels;
    final showRow = editCtrl.draft.arrangementConfig.showSensorRow;
    final index = channels.isEmpty
        ? -1
        : _selected.clamp(0, channels.length - 1);

    return FeedbackSheetScaffold(
      title: 'Sensor Readings & Analog Values',
      subtitle: 'Source, calibration, scaling, units and thresholds.',
      onBack: () => Navigator.of(context).pop(),
      closeLabel: 'Back to Feedback Settings',
      children: [
        const PropertySectionHeader('Sensor row', padTop: 4),
        PropertySwitchTile(
          title: 'Show sensor row',
          subtitle:
              'Master visibility for the whole analog strip. Individual '
              'readers can also be hidden below.',
          value: showRow,
          onChanged: (_) =>
              editCtrl.toggleArrangement(ArrangementToggle.sensorRow),
        ),
        if (channels.isEmpty)
          const PropertyInfoBanner(
            text: 'This layout has no analog readers configured.',
            isWarning: true,
          )
        else ...[
          const PropertySectionHeader('Reader'),
          PropertySegmented<int>(
            options: [
              for (var i = 0; i < channels.length; i++)
                (
                  i,
                  channels[i].label.trim().isEmpty
                      ? channels[i].channelKey
                      : '${channels[i].channelKey} · ${channels[i].label}',
                ),
            ],
            selected: index,
            onChanged: (value) => setState(() => _selected = value),
          ),
          const SizedBox(height: 8),
          _ChannelEditor(
            key: ValueKey('analog-channel-$index'),
            config: channels[index],
            onChanged: (next) => _updateChannel(index, next),
          ),
        ],
      ],
    );
  }
}

class _ChannelEditor extends StatefulWidget {
  const _ChannelEditor({
    super.key,
    required this.config,
    required this.onChanged,
  });

  final AnalogFeedbackConfig config;
  final ValueChanged<AnalogFeedbackConfig> onChanged;

  @override
  State<_ChannelEditor> createState() => _ChannelEditorState();
}

class _ChannelEditorState extends State<_ChannelEditor> {
  late final TextEditingController _label;
  late final TextEditingController _unit;
  late final TextEditingController _rawMin;
  late final TextEditingController _rawMax;
  late final TextEditingController _displayMin;
  late final TextEditingController _displayMax;
  late final TextEditingController _offset;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    _label = TextEditingController(text: config.label);
    _unit = TextEditingController(text: config.unit);
    _rawMin = TextEditingController(text: _format(config.rawMin));
    _rawMax = TextEditingController(text: _format(config.rawMax));
    _displayMin = TextEditingController(text: _format(config.displayMin));
    _displayMax = TextEditingController(text: _format(config.displayMax));
    _offset = TextEditingController(text: _format(config.calibrationOffset));
  }

  @override
  void dispose() {
    _label.dispose();
    _unit.dispose();
    _rawMin.dispose();
    _rawMax.dispose();
    _displayMin.dispose();
    _displayMax.dispose();
    _offset.dispose();
    super.dispose();
  }

  /// Trailing ".0" is noise in a calibration field, so whole numbers print
  /// without it while fractional ones keep their precision.
  static String _format(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';

  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    final onChanged = widget.onChanged;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PropertySwitchTile(
          title: 'Show this reader',
          value: config.visible,
          onChanged: (value) => onChanged(config.copyWith(visible: value)),
        ),
        const PropertySectionHeader('Feedback source'),
        PropertySegmented<String>(
          options: [for (final key in kKnownAnalogChannelKeys) (key, key)],
          selected: config.channelKey,
          onChanged: (value) => onChanged(config.copyWith(channelKey: value)),
        ),
        const SizedBox(height: 6),
        _LivePreview(config: config),
        const PropertySectionHeader('Label & units'),
        PropertyTextField(
          controller: _label,
          label: 'Reader name',
          maxLength: 20,
          onChanged: (value) => onChanged(config.copyWith(label: value)),
        ),
        PropertyTextField(
          controller: _unit,
          label: 'Unit (blank shows percent of full scale)',
          maxLength: 8,
          onChanged: (value) => onChanged(config.copyWith(unit: value)),
        ),
        const PropertySectionHeader('Min / max calibration'),
        const Text(
          'The firmware-scaled hoist values received at each end of the '
          'transducer range.',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FeedbackNumberField(
                controller: _rawMin,
                label: 'Received min',
                onChanged: (value) => onChanged(config.copyWith(rawMin: value)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FeedbackNumberField(
                controller: _rawMax,
                label: 'Received max',
                onChanged: (value) => onChanged(config.copyWith(rawMax: value)),
              ),
            ),
          ],
        ),
        const PropertySectionHeader('Analog scaling'),
        const Text(
          'The engineering span those values represent. Leave it equal to the '
          'received range to display the firmware value unchanged.',
          style: TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FeedbackNumberField(
                controller: _displayMin,
                label: 'Scaled min',
                onChanged: (value) =>
                    onChanged(config.copyWith(displayMin: value)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FeedbackNumberField(
                controller: _displayMax,
                label: 'Scaled max',
                onChanged: (value) =>
                    onChanged(config.copyWith(displayMax: value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FeedbackNumberField(
          controller: _offset,
          label: 'Calibration offset',
          suffix: config.unit.isEmpty ? null : config.unit,
          onChanged: (value) =>
              onChanged(config.copyWith(calibrationOffset: value)),
        ),
        const PropertySectionHeader('Warning / critical thresholds'),
        PropertyLabeledSlider(
          label: 'Warning at',
          value: config.warningFraction,
          min: 0,
          max: 1,
          divisions: 20,
          valueLabel: '${(config.warningFraction * 100).round()}%',
          onChanged: (value) =>
              onChanged(config.copyWith(warningFraction: value)),
        ),
        PropertyLabeledSlider(
          label: 'Critical at',
          value: config.criticalFraction,
          min: 0,
          max: 1,
          divisions: 20,
          valueLabel: '${(config.criticalFraction * 100).round()}%',
          onChanged: (value) =>
              onChanged(config.copyWith(criticalFraction: value)),
        ),
        const PropertySectionHeader('Indicator colour'),
        PropertyColorField(
          label: 'Channel colour',
          value: config.color,
          onChanged: (color) => onChanged(
            config.copyWith(color: color, clearColor: color == null),
          ),
        ),
        const PropertySectionHeader('Escalation'),
        PropertySwitchTile(
          title: 'Raise the alarm when critical',
          subtitle:
              'Escalates the layout alarm to Alarm severity while this reader '
              'is in its critical band.',
          value: config.raiseAlarm,
          onChanged: (value) => onChanged(config.copyWith(raiseAlarm: value)),
        ),
        PropertySwitchTile(
          title: 'Sound the buzzer when critical',
          value: config.soundBuzzer,
          onChanged: (value) => onChanged(config.copyWith(soundBuzzer: value)),
        ),
      ],
    );
  }
}

/// Shows the live firmware value next to what the current calibration turns it
/// into — the fastest way to tell whether a scaling entry is right.
class _LivePreview extends StatelessWidget {
  const _LivePreview({required this.config});

  final AnalogFeedbackConfig config;

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<FeedbackManager>();
    // A hidden reader has no snapshot entry, but its calibration still needs
    // to be checkable against live values — so fall back to null (rendered as
    // "not reporting") rather than pretending the channel reads zero.
    int? raw;
    for (final reading in manager.snapshot.analog) {
      if (reading.config.channelKey == config.channelKey) {
        raw = reading.rawValue;
        break;
      }
    }
    final rawValue = raw ?? 0;
    final scaled = config.scaledValue(rawValue);
    final zone = config.zoneFor(scaled);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              raw == null
                  ? '${config.channelKey} — not reporting'
                  : '${config.channelKey} received $rawValue',
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_right_alt_rounded,
            size: 18,
            color: AppColors.darkTextMuted,
          ),
          const SizedBox(width: 8),
          Text(
            '${scaled.toStringAsFixed(config.isUnscaled ? 0 : 2)}'
            '${config.unit.isEmpty ? '' : ' ${config.unit}'}',
            style: TextStyle(
              color: FeedbackPalette.analogZone(zone, AppColors.darkText),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
