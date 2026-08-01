import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';

/// Opens a bottom sheet listing built-in starting-point layouts (see
/// LayoutTemplateService). Selecting one REPLACES the entire draft — if the
/// draft already has unsaved changes, confirms first so a widget the
/// operator just added from the catalog isn't silently lost.
Future<void> showLoadTemplateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LoadTemplateSheet(),
  );
}

class _LoadTemplateSheet extends StatelessWidget {
  const _LoadTemplateSheet();

  Future<void> _onSelect(BuildContext context, LayoutTemplate template) async {
    final editCtrl = context.read<LayoutEditController>();
    if (editCtrl.hasUnsavedChanges) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.panel,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.darkBorder),
          ),
          title: const Text(
            'Replace current layout?',
            style: TextStyle(color: AppColors.darkText),
          ),
          content: Text(
            'Loading "${template.name}" replaces your in-progress changes. '
            'This can still be undone by not pressing Save Layout or Done.',
            style: const TextStyle(color: AppColors.darkTextSub),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.darkTextSub),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Replace',
                style: TextStyle(color: AppColors.appBarGlow),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    editCtrl.applyTemplate(template);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final templates = const LayoutTemplateService().templates;
    return SafeArea(
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
              'Load Template',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            for (final template in templates)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  template.name,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  template.description,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 12,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.darkTextMuted,
                ),
                onTap: () => _onSelect(context, template),
              ),
          ],
        ),
      ),
    );
  }
}
