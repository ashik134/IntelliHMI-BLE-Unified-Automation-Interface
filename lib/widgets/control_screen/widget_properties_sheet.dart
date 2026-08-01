import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';

/// Opens a bottom sheet for viewing/editing the canvas-selected widget's
/// basic properties (label, enabled) and deleting it. Every field mutates
/// the LayoutEditController draft directly — same "nothing persists until
/// Save Layout / Done" contract as Layout Settings and every other
/// customization mutation.
Future<void> showWidgetPropertiesSheet(BuildContext context, String buttonId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WidgetPropertiesSheet(buttonId: buttonId),
  );
}

class WidgetPropertiesSheet extends StatefulWidget {
  const WidgetPropertiesSheet({super.key, required this.buttonId});

  final String buttonId;

  @override
  State<WidgetPropertiesSheet> createState() => _WidgetPropertiesSheetState();
}

class _WidgetPropertiesSheetState extends State<WidgetPropertiesSheet> {
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    final config = context
        .read<LayoutEditController>()
        .draft
        .resolvedButtons[widget.buttonId];
    _labelController = TextEditingController(text: config?.label ?? '');
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _delete(BuildContext context, String id) async {
    final result = context.read<LayoutEditController>().deleteButton(id);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not delete this widget.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final config = editCtrl.draft.resolvedButtons[widget.buttonId];

    if (config == null) {
      // Selection was cleared (e.g. deleted elsewhere) while this sheet was
      // open — close it rather than render a stale/broken editor.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const SizedBox.shrink();
    }

    final isSafetyControl = config.role != null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.darkBorder),
            boxShadow: AppMetrics.shadowMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.panelStroke,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Widget Properties',
                style: TextStyle(
                  color: AppColors.darkText,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _typeDisplayName(config.type),
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                enabled: !isSafetyControl,
                onChanged: (v) => editCtrl.updateButton(
                  config.id,
                  (b) => b.copyWith(label: v),
                ),
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 13.5,
                ),
                decoration: InputDecoration(
                  labelText: 'Label',
                  labelStyle: const TextStyle(color: AppColors.darkTextMuted),
                  filled: true,
                  fillColor: AppColors.darkBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.selectionViolet,
                      width: 1.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: AppColors.selectionViolet,
                title: const Text(
                  'Enabled',
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Disabled widgets stay on the grid but never send PLC output.',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 11.5,
                  ),
                ),
                value: config.enabled,
                onChanged: isSafetyControl
                    ? null
                    : (v) => editCtrl.updateButton(
                        config.id,
                        (b) => b.copyWith(enabled: v),
                      ),
              ),
              if (isSafetyControl) ...[
                const SizedBox(height: 4),
                const Text(
                  'Safety controls cannot be edited or removed.',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isSafetyControl
                          ? null
                          : () => _delete(context, config.id),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.eStopColor,
                        side: const BorderSide(color: AppColors.eStopColor),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.delete_rounded, size: 18),
                      label: const Text('Delete'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.selectionViolet,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _typeDisplayName(ButtonType type) => switch (type) {
  ButtonType.pushButton => 'Push Button',
  ButtonType.toggle => 'Toggle Switch',
  ButtonType.sliderButton => 'Slider Button',
  ButtonType.bidirectionalSlider5Step => '5-Zone Slider',
  ButtonType.bidirectionalSlider3Step => '3-Zone Slider',
  ButtonType.joystick => 'Joystick',
  ButtonType.potentiometer => 'Potentiometer',
  ButtonType.horn => 'Horn',
  ButtonType.alarmIndicator => 'Alarm Indicator',
  ButtonType.analogJoystick1D => 'Analog Joystick (1-Axis)',
  ButtonType.analogJoystick2D => 'Analog Joystick (2-Axis)',
  ButtonType.analogSliderOT => 'Analog Slider (O-T)',
  ButtonType.analogSliderTOT => 'Analog Slider (T-O-T)',
};
