import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/feedback_settings/feedback_settings_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/grid_layout_toolbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/layout_settings_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/load_template_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/page_transition_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/save_as_template_dialog.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EditModeToolbarHost
// ─────────────────────────────────────────────────────────────────────────────

class EditModeToolbarHost extends StatelessWidget {
  const EditModeToolbarHost({super.key, required this.isEditing});

  final bool isEditing;

  static const Duration _duration = Duration(milliseconds: 280);

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !isEditing,
        child: AnimatedSlide(
          duration: _duration,
          curve: Curves.easeOutCubic,
          offset: isEditing ? Offset.zero : const Offset(0, 0.5),
          child: AnimatedOpacity(
            duration: _duration,
            curve: Curves.easeOutCubic,
            opacity: isEditing ? 1 : 0,
            child: const CustomizationToolbar(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationToolbar
// ─────────────────────────────────────────────────────────────────────────────

class CustomizationToolbar extends StatefulWidget {
  const CustomizationToolbar({super.key});

  @override
  State<CustomizationToolbar> createState() => _CustomizationToolbarState();
}

class _CustomizationToolbarState extends State<CustomizationToolbar> {
  final ScrollController _scrollController = ScrollController();

  String? _activeAction;

  // ── Grid Layout tool ─────────────────────────────────────────────────────
  //
  // The Layout button no longer navigates/opens a sheet — it swaps this
  // toolbar's own content in place for GridLayoutToolbar (see build()'s
  // AnimatedSwitcher below), never leaving the control screen or the
  // current edit session. Pure presentation state, same category as
  // [_activeAction]: [_pendingGridSelection] only stages a choice (card
  // highlight) until the operator taps Apply, which is the only place the
  // draft actually changes (LayoutEditController.applyGridLayout). While
  // the panel is open, the normal action row (including Done) isn't
  // present, so there is no way to lose a staged-but-unapplied selection
  // through an unrelated action — Back/Apply are the only two ways out.
  bool _showGridLayoutPanel = false;
  GridLayoutOption? _pendingGridSelection;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openGridLayoutPanel(BuildContext context) {
    final current = context.read<LayoutEditController>().draft.gridLayout;
    setState(() {
      _pendingGridSelection = current;
      _showGridLayoutPanel = true;
    });
  }

  void _closeGridLayoutPanel() {
    setState(() {
      _showGridLayoutPanel = false;
      _pendingGridSelection = null;
    });
  }

  void _applyGridLayout(BuildContext context) {
    final option = _pendingGridSelection;
    if (option != null) {
      context.read<LayoutEditController>().applyGridLayout(option);
    }
    _closeGridLayoutPanel();
  }

  Future<void> _run(String id, Future<void> Function() action) async {
    setState(() => _activeAction = id);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _activeAction = null);
    }
  }

  // No Navigator push here by design — the catalogue renders as a sliding
  // overlay within the control screen's own Stack (see
  // CatalogueOverlayHost), not as its own route. See
  // _DraggableCatalogCard's doc comment (widget_catalog_screen.dart) for why
  // a pushed/popped route silently breaks mid-placement dragging.
  void _openCatalog(BuildContext context) {
    context.read<LayoutEditController>().enterCatalogueBrowsing();
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

  void _requireSelection(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select a widget on the canvas first.')),
    );
  }

  Future<void> _properties(BuildContext context) async {
    final id = context.read<LayoutEditController>().selectedButtonId;
    if (id == null) {
      _requireSelection(context);
      return;
    }
    await showWidgetPropertiesSheet(context, id);
  }

  void _duplicate(BuildContext context) {
    final editCtrl = context.read<LayoutEditController>();
    final id = editCtrl.selectedButtonId;
    if (id == null) {
      _requireSelection(context);
      return;
    }
    final result = editCtrl.duplicateButton(id);
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not duplicate this widget.'),
        ),
      );
    }
  }

  Future<void> _more(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MoreActionsSheet(
        onSaveLayout: () => _saveLayout(context),
        onSaveAsTemplate: () => showSaveAsTemplateDialog(context),
        onOpenLayoutSettings: () => showLayoutSettingsSheet(context),
        onOpenFeedbackSettings: () => showFeedbackSettingsSheet(context),
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
    final items = <_ToolbarActionSpec>[
      _ToolbarActionSpec(
        id: 'widgets',
        icon: Icons.widgets_rounded,
        label: 'Controls',
        onTap: () => _openCatalog(context),
      ),
      _ToolbarActionSpec(
        id: 'layout',
        icon: Icons.grid_view_rounded,
        label: 'Layout',
        onTap: () => _openGridLayoutPanel(context),
      ),
      _ToolbarActionSpec(
        id: 'template',
        icon: Icons.dashboard_customize_outlined,
        label: 'Template',
        onTap: () => _run('template', () => showLoadTemplateSheet(context)),
      ),
      _ToolbarActionSpec(
        id: 'properties',
        icon: Icons.edit_note_rounded,
        label: 'Properties',
        onTap: () => _run('properties', () => _properties(context)),
      ),
      _ToolbarActionSpec(
        id: 'transition',
        icon: Icons.swap_horiz_rounded,
        label: 'Transition',
        onTap: () => _run('transition', () => showPageTransitionSheet(context)),
      ),
      _ToolbarActionSpec(
        id: 'duplicate',
        icon: Icons.copy_rounded,
        label: 'Duplicate',
        onTap: () => _duplicate(context),
      ),
      _ToolbarActionSpec(
        id: 'more',
        icon: Icons.more_horiz_rounded,
        label: 'More',
        onTap: () => _run('more', () => _more(context)),
      ),
    ];

    final currentGridLayout = context
        .select<LayoutEditController, GridLayoutOption>(
          (c) => c.draft.gridLayout,
        );

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 96,
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(child: _ToolbarReadabilityScrim()),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: _showGridLayoutPanel
                  ? GridLayoutToolbar(
                      key: const ValueKey('gridLayoutPanel'),
                      selected: _pendingGridSelection ?? currentGridLayout,
                      onSelect: (option) =>
                          setState(() => _pendingGridSelection = option),
                      onCancel: _closeGridLayoutPanel,
                      onApply: () => _applyGridLayout(context),
                    )
                  : _buildActionsRow(
                      context,
                      items,
                      key: const ValueKey('actionsRow'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsRow(
    BuildContext context,
    List<_ToolbarActionSpec> items, {
    required Key key,
  }) {
    return Row(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 2),
              itemBuilder: (context, i) {
                final spec = items[i];
                return _ToolbarCircleButton(
                  icon: spec.icon,
                  label: spec.label,
                  selected: _activeAction == spec.id,
                  onTap: spec.onTap,
                );
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: _DoneCircleButton(onTap: () => _done(context)),
        ),
      ],
    );
  }
}

class _ToolbarActionSpec {
  const _ToolbarActionSpec({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String id;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class _ToolbarReadabilityScrim extends StatelessWidget {
  const _ToolbarReadabilityScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withAlpha(0), Colors.black.withAlpha(115)],
          stops: const [0.0, 0.85],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ToolbarCircleButton
// ─────────────────────────────────────────────────────────────────────────────

const double _kToolbarSlotWidth = 74;
const double _kToolbarCircleDiameter = 52;

class _ToolbarCircleButton extends StatefulWidget {
  const _ToolbarCircleButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ToolbarCircleButton> createState() => _ToolbarCircleButtonState();
}

class _ToolbarCircleButtonState extends State<_ToolbarCircleButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.selected
        ? AppColors.selectionViolet
        : AppColors.darkText;
    final labelColor = widget.selected
        ? AppColors.selectionViolet
        : AppColors.darkTextSub;
    final circleColor = _pressed
        ? AppColors.toolbarCircleBgPressed
        : (widget.selected
              ? AppColors.toolbarCircleBgSelected
              : AppColors.toolbarCircleBg);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: SizedBox(
        width: _kToolbarSlotWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: Duration(milliseconds: _pressed ? 90 : 120),
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 90),
                width: _kToolbarCircleDiameter,
                height: _kToolbarCircleDiameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  border: widget.selected
                      ? Border.all(color: AppColors.selectionViolet, width: 1.4)
                      : null,
                ),
                child: Icon(widget.icon, size: 23, color: iconColor),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                decoration: TextDecoration.none,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _DoneCircleButton
// ─────────────────────────────────────────────────────────────────────────────

class _DoneCircleButton extends StatefulWidget {
  const _DoneCircleButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DoneCircleButton> createState() => _DoneCircleButtonState();
}

class _DoneCircleButtonState extends State<_DoneCircleButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapCancel: () => _setPressed(false),
      onTapUp: (_) => _setPressed(false),
      onTap: widget.onTap,
      child: SizedBox(
        width: _kToolbarSlotWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: _pressed ? 0.96 : 1.0,
              duration: Duration(milliseconds: _pressed ? 90 : 120),
              curve: Curves.easeOut,
              child: Container(
                width: _kToolbarCircleDiameter,
                height: _kToolbarCircleDiameter,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _pressed
                      ? AppColors.selectionVioletDeep
                      : AppColors.selectionViolet,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.selectionGlow,
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 24,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Done',
              style: TextStyle(
                decoration: TextDecoration.none,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MoreActionsSheet
// ─────────────────────────────────────────────────────────────────────────────

/// Two clearly separated groups, because they configure different things:
/// LAYOUT is about the arrangement of controls the operator drives, FEEDBACK &
/// STATUS is about what the app annunciates back. Buzzer configuration used to
/// sit here as its own entry; it now lives inside Feedback Settings alongside
/// every other feedback area, so there is exactly one route to it.
class _MoreActionsSheet extends StatelessWidget {
  const _MoreActionsSheet({
    required this.onSaveLayout,
    required this.onSaveAsTemplate,
    required this.onOpenLayoutSettings,
    required this.onOpenFeedbackSettings,
  });

  final VoidCallback onSaveLayout;
  final VoidCallback onSaveAsTemplate;
  final VoidCallback onOpenLayoutSettings;
  final VoidCallback onOpenFeedbackSettings;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
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
              'More',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const _MoreSectionLabel('LAYOUT'),
            _MoreActionTile(
              icon: Icons.save_rounded,
              title: 'Save Layout',
              subtitle: 'Persist changes without leaving Edit Mode.',
              onTap: () {
                Navigator.of(context).pop();
                onSaveLayout();
              },
            ),
            _MoreActionTile(
              icon: Icons.bookmark_add_rounded,
              title: 'Save as Template',
              subtitle: 'Save this layout as a reusable custom template.',
              onTap: () {
                Navigator.of(context).pop();
                onSaveAsTemplate();
              },
            ),
            _MoreActionTile(
              icon: Icons.tune_rounded,
              title: 'Layout Settings',
              subtitle: 'E-Stop instructions, arrangement, and sizing.',
              onTap: () {
                Navigator.of(context).pop();
                onOpenLayoutSettings();
              },
            ),
            const _MoreSectionLabel('FEEDBACK & STATUS'),
            _MoreActionTile(
              icon: Icons.notifications_active_rounded,
              title: 'Feedback Settings',
              subtitle:
                  'Alarms, buzzer, sensor readings, LED and status indication, '
                  'calibration and heartbeat — all in one place.',
              featured: true,
              onTap: () {
                Navigator.of(context).pop();
                onOpenFeedbackSettings();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreSectionLabel extends StatelessWidget {
  const _MoreSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

class _MoreActionTile extends StatelessWidget {
  const _MoreActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Draws the tile as a filled card rather than a plain row — used for the
  /// section's primary destination so it reads as the way in, not one option
  /// among several.
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
          decoration: BoxDecoration(
            color: featured
                ? AppColors.selectionViolet.withAlpha(22)
                : AppColors.darkBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: featured
                  ? AppColors.selectionViolet.withAlpha(110)
                  : AppColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.selectionViolet),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.darkText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.darkTextMuted,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
