import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/services/saved_template_service.dart';

/// Opens the "Save Current Layout" dialog, then saves the in-progress edit
/// draft — widgets, positions, sizes, pages, labels, styles and PLC mappings
/// only, never runtime state (button/joystick live values, PLC outputs, BLE
/// connection, E-Stop latch — none of which lives on ControlLayoutConfig in
/// the first place) — as a new named custom template via
/// [SavedTemplateService]. Shows a success/error snackbar on completion.
Future<void> showSaveAsTemplateDialog(BuildContext context) async {
  final editCtrl = context.read<LayoutEditController>();
  final templateService = context.read<SavedTemplateService>();

  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => const _SaveAsTemplateDialog(),
  );
  if (name == null) return;

  final trimmed = name.trim();
  final saved = await templateService.saveTemplate(
    name: trimmed,
    bucket: editCtrl.activeBucket,
    config: editCtrl.draft,
  );

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        saved
            ? 'Template "$trimmed" saved successfully.'
            : 'A template named "$trimmed" already exists.',
      ),
      backgroundColor: saved ? AppColors.darkSuccess : AppColors.eStopColor,
    ),
  );
}

class _SaveAsTemplateDialog extends StatefulWidget {
  const _SaveAsTemplateDialog();

  @override
  State<_SaveAsTemplateDialog> createState() => _SaveAsTemplateDialogState();
}

class _SaveAsTemplateDialogState extends State<_SaveAsTemplateDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a template name.');
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      title: const Text(
        'Save Current Layout',
        style: TextStyle(color: AppColors.darkText),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        style: const TextStyle(color: AppColors.darkText, fontSize: 13.5),
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Template Name',
          hintText: 'My Control Layout',
          hintStyle: const TextStyle(color: AppColors.darkTextMuted),
          labelStyle: const TextStyle(color: AppColors.darkTextMuted),
          errorText: _error,
          counterStyle: const TextStyle(
            color: AppColors.darkTextMuted,
            fontSize: 11,
          ),
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.darkTextSub),
          ),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Save', style: TextStyle(color: AppColors.appBarGlow)),
        ),
      ],
    );
  }
}
