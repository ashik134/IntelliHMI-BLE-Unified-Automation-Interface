import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationModeBar
//
// Floating pill shown while Customization Mode is active. Nothing in this
// bar touches LayoutSettingsController directly except commit() — every
// other action mutates the draft via CustomizationModeController, so it
// stays fully undoable/discardable until Apply is tapped.
// ─────────────────────────────────────────────────────────────────────────────

class CustomizationModeBar extends StatelessWidget {
  const CustomizationModeBar({super.key});

  Future<void> _confirmDiscard(BuildContext context) async {
    final customCtrl = context.read<CustomizationModeController>();
    if (!customCtrl.hasUnsavedChanges) {
      customCtrl.discard();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Discard changes?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: const Text(
          'All unapplied edits made in this session will be lost.',
          style: TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (confirmed == true) customCtrl.discard();
  }

  Future<void> _apply(BuildContext context) async {
    final customCtrl = context.read<CustomizationModeController>();
    final result = await customCtrl.commit();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.isValid ? 'Layout applied.' : result.firstError,
        ),
        backgroundColor: result.isValid ? AppColors.darkSuccess : AppColors.eStopColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final validation = customCtrl.lastValidation;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!validation.isValid)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.eStopColor.withAlpha(230),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        validation.firstError,
                        style: const TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.panel.withAlpha(245),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.darkBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(80),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _BarIconButton(
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo',
                    onTap: customCtrl.canUndo ? customCtrl.undo : null,
                  ),
                  _BarIconButton(
                    icon: Icons.redo_rounded,
                    tooltip: 'Redo',
                    onTap: customCtrl.canRedo ? customCtrl.redo : null,
                  ),
                  _BarIconButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: 'More',
                    onTap: () => _showOverflowMenu(context),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _confirmDiscard(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.darkTextSub,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton.icon(
                    onPressed: () => _apply(context),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Apply'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.darkSuccess,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showOverflowMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => _OverflowMenu(hostContext: context),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      color: onTap == null ? AppColors.disabled : AppColors.darkText,
      onPressed: onTap,
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({required this.hostContext});
  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _MenuTile(
            icon: Icons.dashboard_rounded,
            label: 'Layout Elements',
            onTap: () {
              Navigator.of(context).pop();
              _showLayoutElementsDialog(hostContext);
            },
          ),
          _MenuTile(
            icon: Icons.warning_amber_rounded,
            label: 'Safety Labels',
            onTap: () {
              Navigator.of(context).pop();
              _showSafetyLabelsDialog(hostContext);
            },
          ),
          _MenuTile(
            icon: Icons.copy_rounded,
            label: 'Export Layout (copy JSON)',
            onTap: () {
              Navigator.of(context).pop();
              _exportLayout(hostContext);
            },
          ),
          _MenuTile(
            icon: Icons.paste_rounded,
            label: 'Import Layout (paste JSON)',
            onTap: () {
              Navigator.of(context).pop();
              _importLayout(hostContext);
            },
          ),
          _MenuTile(
            icon: Icons.dashboard_customize_rounded,
            label: 'Load Template',
            onTap: () {
              Navigator.of(context).pop();
              _showTemplatesDialog(hostContext);
            },
          ),
          _MenuTile(
            icon: Icons.restore_rounded,
            label: 'Reset to Factory Defaults',
            iconColor: AppColors.eStopColor,
            onTap: () {
              Navigator.of(context).pop();
              _confirmResetToDefaults(hostContext);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _exportLayout(BuildContext context) {
    final draft = context.read<CustomizationModeController>().draft;
    Clipboard.setData(ClipboardData(text: draft.toJsonString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Layout copied to clipboard.')),
    );
  }

  Future<void> _importLayout(BuildContext context) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty.')),
      );
      return;
    }
    final customCtrl = context.read<CustomizationModeController>();
    final parsed = ControlLayoutConfig.fromJsonString(text);
    customCtrl.applyDraftChange(parsed);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Layout imported. Review, then Apply to save.'),
      ),
    );
  }

  void _showTemplatesDialog(BuildContext context) {
    const service = LayoutTemplateService();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Load Template', style: TextStyle(color: AppColors.darkText)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final template in service.templates)
                ListTile(
                  title: Text(
                    template.name,
                    style: const TextStyle(color: AppColors.darkText),
                  ),
                  subtitle: Text(
                    template.description,
                    style: const TextStyle(color: AppColors.darkTextSub, fontSize: 11),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    context.read<CustomizationModeController>().applyDraftChange(
                      template.build(),
                    );
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmResetToDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Reset to factory defaults?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: const Text(
          'This restores every control on this screen to its factory layout. '
          'Nothing is saved until you tap Apply.',
          style: TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<CustomizationModeController>().applyDraftChange(
        const ControlLayoutConfig(),
      );
    }
  }

  void _showLayoutElementsDialog(BuildContext context) {
    final customCtrl = context.read<CustomizationModeController>();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final arrangement = customCtrl.draft.arrangementConfig;

          void update(ControlArrangementConfig next) {
            final draft = customCtrl.draft;
            customCtrl.applyDraftChange(draft.copyWith(arrangementConfig: next));
            setDialogState(() {});
          }

          return AlertDialog(
            backgroundColor: AppColors.panel,
            title: const Text(
              'Layout Elements',
              style: TextStyle(color: AppColors.darkText),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Sensor row',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showSensorRow,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showSensorRow: v)),
                ),
                SwitchListTile(
                  title: const Text(
                    'Live LED row',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showLiveLEDs,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showLiveLEDs: v)),
                ),
                SwitchListTile(
                  title: const Text(
                    'Connection subtitle',
                    style: TextStyle(color: AppColors.darkText, fontSize: 13),
                  ),
                  activeThumbColor: AppColors.accent,
                  value: arrangement.showConnectionSubtitle,
                  onChanged: (v) =>
                      update(arrangement.copyWith(showConnectionSubtitle: v)),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSafetyLabelsDialog(BuildContext context) {
    final customCtrl = context.read<CustomizationModeController>();
    final labels = customCtrl.draft.labelConfig;
    final estopController = TextEditingController(text: labels.estopSwipeInstruction);
    final resetController = TextEditingController(text: labels.resetEstopLabel);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Safety Labels', style: TextStyle(color: AppColors.darkText)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: estopController,
              maxLength: ControlLabelConfig.maxInstructionLength,
              style: const TextStyle(color: AppColors.darkText),
              decoration: const InputDecoration(labelText: 'E-Stop instruction'),
            ),
            TextField(
              controller: resetController,
              maxLength: ControlLabelConfig.maxLabelLength,
              style: const TextStyle(color: AppColors.darkText),
              decoration: const InputDecoration(labelText: 'Reset E-Stop label'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final draft = customCtrl.draft;
              customCtrl.applyDraftChange(
                draft.copyWith(
                  labelConfig: draft.labelConfig.copyWith(
                    estopSwipeInstruction: estopController.text.trim(),
                    resetEstopLabel: resetController.text.trim(),
                  ),
                ),
              );
              Navigator.of(ctx).pop();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor = AppColors.darkTextSub,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(label, style: const TextStyle(color: AppColors.darkText, fontSize: 13)),
      onTap: onTap,
    );
  }
}
