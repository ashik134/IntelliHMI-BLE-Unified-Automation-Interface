import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/screens/widget_catalog_screen.dart';
import 'package:rev_crane_control_ops/utils/page_transitions.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/layout_settings_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/load_template_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditModeToolbarHost
//
// Always mounted at the bottom of the control screen's Stack; slides the
// customization toolbar up/down as Edit Mode toggles, so Done's exit slides
// away instead of vanishing instantly. Content is IgnorePointer-gated when
// not editing so it can never intercept touches meant for the canvas
// underneath while off-screen.
// ─────────────────────────────────────────────────────────────────────────────

class EditModeToolbarHost extends StatefulWidget {
  const EditModeToolbarHost({super.key, required this.isEditing});

  final bool isEditing;

  @override
  State<EditModeToolbarHost> createState() => _EditModeToolbarHostState();
}

class _EditModeToolbarHostState extends State<EditModeToolbarHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _offset = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    if (widget.isEditing) _controller.value = 1;
  }

  @override
  void didUpdateWidget(covariant EditModeToolbarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEditing == oldWidget.isEditing) return;
    if (widget.isEditing) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: _offset,
        child: IgnorePointer(
          ignoring: !widget.isEditing,
          child: const CustomizationToolbar(),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationToolbar
// ─────────────────────────────────────────────────────────────────────────────

class CustomizationToolbar extends StatelessWidget {
  const CustomizationToolbar({super.key});

  Future<void> _openCatalog(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(buildSlideFadeRoute((_) => const WidgetCatalogScreen()));
  }

  Future<void> _saveLayout(BuildContext context) async {
    final result = await context.read<LayoutEditController>().save();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.isValid ? 'Layout saved.' : result.firstError),
        backgroundColor: result.isValid
            ? AppColors.darkSuccess
            : AppColors.eStopColor,
      ),
    );
  }

  Future<void> _done(BuildContext context) async {
    final result = await context.read<LayoutEditController>().exit();
    if (!context.mounted || result.isValid) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: const Text(
          'Layout has errors',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: SingleChildScrollView(
          child: Text(
            result.errors.join('\n'),
            style: const TextStyle(color: AppColors.darkTextSub),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'OK',
              style: TextStyle(color: AppColors.appBarGlow),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
          boxShadow: AppMetrics.shadowMd,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ToolbarAction(
                      icon: Icons.widgets_rounded,
                      label: 'Widgets',
                      onTap: () => _openCatalog(context),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarAction(
                      icon: Icons.dashboard_customize_outlined,
                      label: 'Load Template',
                      onTap: () => showLoadTemplateSheet(context),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarAction(
                      icon: Icons.save_rounded,
                      label: 'Save Layout',
                      onTap: () => _saveLayout(context),
                    ),
                    const SizedBox(width: 8),
                    _ToolbarAction(
                      icon: Icons.tune_rounded,
                      label: 'Layout Settings',
                      onTap: () => showLayoutSettingsSheet(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            _DoneButton(onTap: () => _done(context)),
          ],
        ),
      ),
    );
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.darkBg,
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: AppColors.selectionViolet),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.darkTextSub,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.selectionViolet,
      borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(
            'Done',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
