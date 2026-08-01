import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

/// Opens the Layout Settings bottom sheet: labels, arrangement toggles, and
/// E-Stop sizing for the layout currently being edited. Every field mutates
/// the LayoutEditController draft directly (never LayoutSettingsController's
/// immediate-persist update* methods) so nothing here reaches
/// SharedPreferences until Save Layout / Done, matching every other
/// mutation in the customization workflow.
Future<void> showLayoutSettingsSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LayoutSettingsSheet(),
  );
}

class _LayoutSettingsSheet extends StatefulWidget {
  const _LayoutSettingsSheet();

  @override
  State<_LayoutSettingsSheet> createState() => _LayoutSettingsSheetState();
}

class _LayoutSettingsSheetState extends State<_LayoutSettingsSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _estopInstructionController;
  late final TextEditingController _resetLabelController;

  @override
  void initState() {
    super.initState();
    final labels = context.read<LayoutEditController>().draft.labelConfig;
    _titleController = TextEditingController(text: labels.screenTitle);
    _estopInstructionController = TextEditingController(
      text: labels.estopSwipeInstruction,
    );
    _resetLabelController = TextEditingController(text: labels.resetEstopLabel);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _estopInstructionController.dispose();
    _resetLabelController.dispose();
    super.dispose();
  }

  void _updateLabels(ControlLabelConfig Function(ControlLabelConfig) update) {
    final editCtrl = context.read<LayoutEditController>();
    editCtrl.updateDraftLabelConfig(update(editCtrl.draft.labelConfig));
  }

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final arrangement = editCtrl.draft.arrangementConfig;
    final sizing = editCtrl.draft.sizeConfig;
    final errors = editCtrl.lastValidation.errors;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
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
            child: SingleChildScrollView(
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
                    'Layout Settings',
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const _SectionLabel('LABELS'),
                  const SizedBox(height: 8),
                  _SettingsTextField(
                    label: 'Screen title',
                    controller: _titleController,
                    onChanged: (v) =>
                        _updateLabels((c) => c.copyWith(screenTitle: v)),
                  ),
                  const SizedBox(height: 10),
                  _SettingsTextField(
                    label: 'E-Stop swipe instruction',
                    controller: _estopInstructionController,
                    onChanged: (v) => _updateLabels(
                      (c) => c.copyWith(estopSwipeInstruction: v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SettingsTextField(
                    label: 'Reset E-Stop label',
                    controller: _resetLabelController,
                    onChanged: (v) =>
                        _updateLabels((c) => c.copyWith(resetEstopLabel: v)),
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('SYSTEM WIDGETS'),
                  const SizedBox(height: 4),
                  for (final toggle in ArrangementToggle.values)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeThumbColor: AppColors.selectionViolet,
                      title: Text(
                        _labelFor(toggle),
                        style: const TextStyle(
                          color: AppColors.darkText,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      value: toggle.isEnabledIn(arrangement),
                      onChanged: (_) => editCtrl.toggleArrangement(toggle),
                    ),
                  const SizedBox(height: 12),
                  const _SectionLabel('E-STOP SIZE'),
                  const SizedBox(height: 4),
                  _ScaleSlider(
                    label: 'Height scale',
                    value: sizing.estopButtonHeightScale,
                    min: ControlWidgetSizeConfig.minHeightScale,
                    max: ControlWidgetSizeConfig.maxHeightScale,
                    onChanged: (v) => editCtrl.updateDraftSizeConfig(
                      sizing.copyWith(estopButtonHeightScale: v),
                    ),
                  ),
                  _ScaleSlider(
                    label: 'Width scale',
                    value: sizing.estopButtonWidthScale,
                    min: ControlWidgetSizeConfig.minWidthScale,
                    max: ControlWidgetSizeConfig.maxWidthScale,
                    onChanged: (v) => editCtrl.updateDraftSizeConfig(
                      sizing.copyWith(estopButtonWidthScale: v),
                    ),
                  ),
                  if (errors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.eStopColor.withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.eStopColor.withAlpha(90),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final error in errors)
                            Text(
                              error,
                              style: const TextStyle(
                                color: AppColors.eStopColor,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
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
            ),
          ),
        ),
      ),
    );
  }

  String _labelFor(ArrangementToggle toggle) => switch (toggle) {
    ArrangementToggle.sensorRow => 'Sensor Row',
    ArrangementToggle.liveLeds => 'Live LED Row',
    ArrangementToggle.connectionSubtitle => 'Connection Subtitle',
  };
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: AppColors.darkTextMuted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _SettingsTextField extends StatelessWidget {
  const _SettingsTextField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(color: AppColors.darkText, fontSize: 13.5),
      decoration: InputDecoration(
        labelText: label,
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
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: AppColors.selectionViolet,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
