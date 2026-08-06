import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ControlCanvas
//
// Renders the paged control grid (generic, roleless ButtonConfigs — the two
// safety controls are rendered separately by SafetyActionPanel and never
// reach here, since [buildControlGridPages] is called with an empty roles
// list). Live mode renders real, fully-interactive buttons. Edit mode wraps
// each occupied cell in an AbsorbPointer (never sends a PLC command while
// editing) plus tap-to-select/delete chrome; vacant cells are inert — the
// Widget Catalog (via the customization toolbar) is the only way to add a
// widget this pass, there is no drag/resize yet.
// ─────────────────────────────────────────────────────────────────────────────

// Matches SettlingPreviewOverlay's own settle-animation timing, so a widget
// displaced by the live insertion preview and the newly-placed widget
// settling into its target cell read as one consistent motion.
const Duration _kRepositionDuration = Duration(milliseconds: 220);

class ControlCanvas extends StatefulWidget {
  const ControlCanvas({
    super.key,
    required this.layoutCfg,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    this.onStateIdCommand,
    this.onAnalogCommand,
    this.selectedButtonId,
    this.onSelectButton,
    this.onDeleteButton,
    this.onEditButton,
    this.pageTransitionStyle = CanvasPageTransitionStyle.slide,
    this.pageController,
  });

  final ControlLayoutConfig layoutCfg;
  final bool isEditing;
  final ControlState Function(ButtonConfig config) activeStateFor;
  final bool Function(ButtonConfig config) isDisabled;
  final ButtonCommandCallback onCommand;
  final ButtonStateIdCommandCallback? onStateIdCommand;
  final AnalogButtonCommandCallback? onAnalogCommand;
  final String? selectedButtonId;
  final ValueChanged<String?>? onSelectButton;
  final ValueChanged<String>? onDeleteButton;

  /// Pencil-badge tap — see _OccupiedCell's always-visible edit affordance.
  /// Distinct from [onSelectButton]: callers should both select the button
  /// AND open its properties sheet from this callback.
  final ValueChanged<String>? onEditButton;

  /// Edit Mode-only page-swipe preview style (see
  /// CanvasPageTransitionStyle's doc comment) — inert in live mode, which
  /// never allows page-swiping at all (see [isEditing]'s physics below).
  final CanvasPageTransitionStyle pageTransitionStyle;

  /// Externally-owned page controller, so a widget-placement drop landing
  /// on a different page can animate this PageView there (see
  /// LayoutEditController.handleCatalogueDrop / PlacementSurface). Falls
  /// back to an internally-owned one — and only disposes that one, never a
  /// caller-supplied controller — when omitted (every call site that isn't
  /// wiring up placement).
  final PageController? pageController;

  @override
  State<ControlCanvas> createState() => _ControlCanvasState();
}

class _ControlCanvasState extends State<ControlCanvas> {
  PageController? _ownedPageController;

  PageController get _pageController =>
      widget.pageController ?? (_ownedPageController ??= PageController());

  @override
  void dispose() {
    _ownedPageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.layoutCfg.gridLayout;
    final pages = buildControlGridPages(
      layoutCfg: widget.layoutCfg,
      roles: const <ControlRole>[],
      slotCount: grid.slotCount,
      columns: grid.columns,
      rows: grid.rows,
    );

    return PageView.builder(
      controller: _pageController,
      physics: widget.isEditing
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: pages.isEmpty ? 1 : pages.length,
      itemBuilder: (context, pageIndex) {
        final page = pageIndex < pages.length ? pages[pageIndex] : null;
        final content = LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = constraints.maxWidth / grid.columns;
            final cellHeight = constraints.maxHeight / grid.rows;
            final occupiedSlots = <int>{
              for (final item in page?.items ?? const <ControlGridItem>[])
                ...item.occupiedSlots,
            };

            return Stack(
              children: [
                for (final item in page?.items ?? const <ControlGridItem>[])
                  AnimatedPositioned(
                    key: ValueKey(item.config.id),
                    duration: _kRepositionDuration,
                    curve: Curves.easeOutCubic,
                    left: item.gridX * cellWidth,
                    top: item.gridY * cellHeight,
                    width: item.colSpan * cellWidth,
                    height: item.rowSpan * cellHeight,
                    child: _OccupiedCell(
                      config: item.config,
                      isEditing: widget.isEditing,
                      isSelected:
                          widget.isEditing &&
                          item.config.id == widget.selectedButtonId,
                      activeState: widget.activeStateFor(item.config),
                      isDisabled: widget.isDisabled(item.config),
                      onCommand: widget.onCommand,
                      onStateIdCommand: widget.onStateIdCommand,
                      onAnalogCommand: widget.onAnalogCommand,
                      onTap: () => widget.onSelectButton?.call(item.config.id),
                      onDelete: () =>
                          widget.onDeleteButton?.call(item.config.id),
                      onEdit: () {
                        widget.onSelectButton?.call(item.config.id);
                        widget.onEditButton?.call(item.config.id);
                      },
                    ),
                  ),
                if (widget.isEditing)
                  for (var slot = 0; slot < grid.slotCount; slot++)
                    if (!occupiedSlots.contains(slot))
                      AnimatedPositioned(
                        key: ValueKey(
                          'vacant_${page?.pageIndex ?? pageIndex}_$slot',
                        ),
                        duration: _kRepositionDuration,
                        curve: Curves.easeOutCubic,
                        left: (slot % grid.columns) * cellWidth,
                        top: (slot ~/ grid.columns) * cellHeight,
                        width: cellWidth,
                        height: cellHeight,
                        child: const _VacantCell(),
                      ),
              ],
            );
          },
        );

        if (widget.pageTransitionStyle != CanvasPageTransitionStyle.fade) {
          return content;
        }
        // Fade preview: cross-fades pages by distance from the controller's
        // current scroll offset instead of the PageView's built-in slide.
        // Guarded by hasClients/haveDimensions since itemBuilder can run
        // before the Scrollable beneath this PageView has attached a
        // position (e.g. the very first frame).
        return AnimatedBuilder(
          animation: _pageController,
          child: content,
          builder: (context, child) {
            var page = pageIndex.toDouble();
            if (_pageController.hasClients &&
                _pageController.position.haveDimensions) {
              page = _pageController.page ?? page;
            }
            final opacity = (1 - (page - pageIndex).abs()).clamp(0.0, 1.0);
            return Opacity(opacity: opacity, child: child);
          },
        );
      },
    );
  }
}

class _OccupiedCell extends StatelessWidget {
  const _OccupiedCell({
    required this.config,
    required this.isEditing,
    required this.isSelected,
    required this.activeState,
    required this.isDisabled,
    required this.onCommand,
    required this.onStateIdCommand,
    required this.onAnalogCommand,
    required this.onTap,
    required this.onDelete,
    required this.onEdit,
  });

  final ButtonConfig config;
  final bool isEditing;
  final bool isSelected;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandCallback onCommand;
  final ButtonStateIdCommandCallback? onStateIdCommand;
  final AnalogButtonCommandCallback? onAnalogCommand;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  /// Pencil-badge tap — opens the properties sheet for this button. Unlike
  /// [onDelete] (selected-cell-only, matching today's behavior — deletion
  /// stays a deliberate two-step action), the pencil badge is always visible
  /// on every occupied cell while editing: it's non-destructive, so there's
  /// no accidental-tap risk in making it a one-tap affordance.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final button = Padding(
      padding: const EdgeInsets.all(4),
      child: ConfigurableButton(
        config: config,
        activeState: activeState,
        isDisabled: isDisabled,
        onCommand: onCommand,
        onStateIdCommand: onStateIdCommand,
        onAnalogCommand: onAnalogCommand,
      ),
    );

    if (!isEditing) return button;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        // Match Normal Mode's tight grid-cell constraints. Without expand,
        // StackFit.loose lets ConfigurableButton keep resolvedHeight while
        // the Positioned.fill selection frame grows around it during a live
        // resize, so the control itself appears to resize only after Done.
        fit: StackFit.expand,
        clipBehavior: Clip.none,
        children: [
          AbsorbPointer(absorbing: true, child: button),
          // Every occupied cell gets a faint edit-mode outline — not just the
          // selected one — so the whole grid reads as a layout of editable
          // tiles rather than a live control panel. The selected cell's
          // brighter border+glow below is layered on top of this.
          if (!isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.selectionViolet.withAlpha(70),
                      width: 1.2,
                    ),
                  ),
                ),
              ),
            ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.selectionViolet,
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.selectionGlow,
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (isSelected)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.eStopColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,

                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
            ),
          // Always visible (every occupied cell, not just the selected one)
          // — see [onEdit]'s doc comment for why this differs from the
          // delete badge's selected-cell-only gating.
          Positioned(
            top: -0,
            left: 1,
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: AppColors.selectionViolet,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_square,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VacantCell extends StatelessWidget {
  const _VacantCell();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.selectionViolet.withAlpha(60),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
