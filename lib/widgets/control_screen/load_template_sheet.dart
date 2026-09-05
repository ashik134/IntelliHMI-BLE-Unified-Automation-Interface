import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/saved_template.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/services/saved_template_service.dart';

/// Opens a bottom sheet listing built-in starting-point layouts (see
/// LayoutTemplateService) plus any user-saved "Save as Template" layouts for
/// the active PLC bucket (see SavedTemplateService). Selecting one REPLACES
/// the entire draft — if the draft already has unsaved changes, confirms
/// first so a widget the operator just added from the catalog isn't
/// silently lost.
Future<void> showLoadTemplateSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _LoadTemplateSheet(),
  );
}

class _LoadTemplateSheet extends StatefulWidget {
  const _LoadTemplateSheet();

  @override
  State<_LoadTemplateSheet> createState() => _LoadTemplateSheetState();
}

class _LoadTemplateSheetState extends State<_LoadTemplateSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SavedTemplateService>().load();
    });
  }

  Future<bool> _confirmReplace(BuildContext context, String name) async {
    final editCtrl = context.read<LayoutEditController>();
    if (!editCtrl.hasUnsavedChanges) return true;
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
          'Loading "$name" replaces your in-progress changes. '
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
    return confirmed == true;
  }

  Future<void> _onSelectBuiltIn(
    BuildContext context,
    LayoutTemplate template,
  ) async {
    if (!await _confirmReplace(context, template.name)) return;
    if (!context.mounted) return;
    context.read<LayoutEditController>().applyTemplate(template);
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _onSelectSaved(
    BuildContext context,
    SavedTemplate template,
  ) async {
    if (!await _confirmReplace(context, template.name)) return;
    if (!context.mounted) return;
    context.read<LayoutEditController>().applySavedTemplate(template.config);
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final templates = const LayoutTemplateService().templates;
    final bucket = context.watch<LayoutEditController>().activeBucket;
    final savedTemplates = context.watch<SavedTemplateService>().templatesFor(
      bucket,
    );
    return SafeArea(
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
                    onTap: () => _onSelectBuiltIn(context, template),
                  ),
                if (savedTemplates.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 4),
                    child: Text(
                      'MY TEMPLATES',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  for (final template in savedTemplates)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.bookmark_rounded,
                        color: AppColors.darkTextMuted,
                        size: 20,
                      ),
                      title: Text(
                        template.name,
                        style: const TextStyle(
                          color: AppColors.darkText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.darkTextMuted,
                      ),
                      onTap: () => _onSelectSaved(context, template),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
