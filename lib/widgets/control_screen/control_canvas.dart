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
// editing) plus tap-to-select/delete chrome, and — for the selected,
// unlocked widget only — four edge drag-resize handles (see
// _ResizeHandleOverlay); vacant cells are inert — the Widget Catalog (via
// the customization toolbar) is the only way to ADD a widget, dragging one
// to reposition it is not yet supported.
// ─────────────────────────────────────────────────────────────────────────────

// Matches SettlingPreviewOverlay's own settle-animation timing, so a widget
// displaced by the live insertion preview and the newly-placed widget
// settling into its target cell read as one consistent motion. The resize
// handle overlay reuses the same constants so a resized/displaced widget,
// its neighbors, and its own handles all read as one consistent motion too.
const Duration _kRepositionDuration = Duration(milliseconds: 220);

// Resize handle geometry — see _ResizeHandleOverlay/_ResizeHandle. "Long"/
// "short" are relative to the handle's own axis (a top/bottom handle's pill
// is long horizontally and short vertically; left/right is the reverse).
// _kHandleBorderInset matches _OccupiedCell's selection frame's own
// `margin: EdgeInsets.all(4)` so a handle's visible pill centers exactly on
// the selection border, never far inside or outside it.
const double _kHandleBorderInset = 4;
const double _kHandleVisibleLong = 26;
const double _kHandleVisibleShort = 8;
const double _kHandleTouchLong = 44;
const double _kHandleTouchShort = 32;

/// (id, edge) — a resize-handle drag started on the selected widget's
/// [edge]. See LayoutEditController.beginResize.
typedef ButtonResizeStartCallback = void Function(String id, ResizeEdge edge);

/// (id, edge, deltaCols, deltaRows) — fired on every pointer-move frame of
/// an active resize drag, carrying the CUMULATIVE whole-grid-cell movement
/// since the drag started (never a per-frame increment — see
/// LayoutEditController.updateResize's doc comment for why).
typedef ButtonResizeUpdateCallback =
    void Function(String id, ResizeEdge edge, int deltaCols, int deltaRows);

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
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
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

  /// Drag-resize handle callbacks — see [_ResizeHandleOverlay]. Rendering
  /// AND gesture-handling for the four edge handles are both gated on
  /// [onResizeStart] being non-null (a null callback means "no resize
  /// handles at all," e.g. while a catalogue placement is in flight — see
  /// call sites in plc14_control_screen.dart/plc38_control_screen.dart),
  /// so there is no separate boolean to keep in sync with these.
  final ButtonResizeStartCallback? onResizeStart;
  final ButtonResizeUpdateCallback? onResizeUpdate;
  final ButtonResizeStartCallback? onResizeEnd;

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

            // Resize handles only ever target the selected widget, and only
            // when this build actually has a callback wired for them (see
            // [onResizeStart]'s doc comment) and that widget isn't locked
            // (locked freezes position/size editing on the canvas — see
            // ButtonConfig.locked).
            ControlGridItem? resizableSelection;
            if (widget.isEditing &&
                widget.onResizeStart != null &&
                widget.selectedButtonId != null) {
              for (final item in page?.items ?? const <ControlGridItem>[]) {
                if (item.config.id == widget.selectedButtonId) {
                  resizableSelection = item.config.locked ? null : item;
                  break;
                }
              }
            }

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
                // Rendered as the LAST Stack child (not nested inside the
                // selected _OccupiedCell's own Stack) so it always paints,
                // and is hit-tested, above every other cell — including one
                // whose AnimatedPositioned box happens to be later in
                // [page.items] and would otherwise sit on top of a handle
                // that overhangs the selection border into a neighboring
                // cell's area. See _ResizeHandleOverlay's doc comment.
                if (resizableSelection != null)
                  AnimatedPositioned(
                    key: ValueKey('resize_handles_${resizableSelection.config.id}'),
                    duration: _kRepositionDuration,
                    curve: Curves.easeOutCubic,
                    left: resizableSelection.gridX * cellWidth,
                    top: resizableSelection.gridY * cellHeight,
                    width: resizableSelection.colSpan * cellWidth,
                    height: resizableSelection.rowSpan * cellHeight,
                    child: _ResizeHandleOverlay(
                      buttonId: resizableSelection.config.id,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      onResizeStart: widget.onResizeStart,
                      onResizeUpdate: widget.onResizeUpdate,
                      onResizeEnd: widget.onResizeEnd,
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _ResizeHandleOverlay / _ResizeHandle
//
// The four edge drag-resize handles for the selected widget. Rendered by
// ControlCanvas as its OWN last Stack child — sharing the selected item's
// exact AnimatedPositioned box rather than living inside that item's own
// _OccupiedCell — so a handle that overhangs the selection border into a
// neighboring cell's painted area always wins hit-testing over that
// neighbor's own (opaque, tap-to-select) GestureDetector. Each handle
// resizes along exactly one axis (top/bottom -> rows, left/right ->
// columns), per the spec this implements.
// ─────────────────────────────────────────────────────────────────────────────

class _ResizeHandleOverlay extends StatelessWidget {
  const _ResizeHandleOverlay({
    required this.buttonId,
    required this.cellWidth,
    required this.cellHeight,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final String buttonId;
  final double cellWidth;
  final double cellHeight;
  final ButtonResizeStartCallback? onResizeStart;
  final ButtonResizeUpdateCallback? onResizeUpdate;
  final ButtonResizeStartCallback? onResizeEnd;

  @override
  Widget build(BuildContext context) {
    // Belt-and-suspenders: ControlCanvas already never mounts this overlay
    // when onResizeStart is null (see its call site), but IgnorePointer here
    // means a handle can never accidentally intercept a tap even if that
    // condition is ever loosened.
    return IgnorePointer(
      ignoring: onResizeStart == null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: _kHandleBorderInset - _kHandleTouchShort / 2,
            left: 0,
            right: 0,
            child: Center(child: _buildHandle(ResizeEdge.top, Axis.horizontal)),
          ),
          Positioned(
            bottom: _kHandleBorderInset - _kHandleTouchShort / 2,
            left: 0,
            right: 0,
            child: Center(
              child: _buildHandle(ResizeEdge.bottom, Axis.horizontal),
            ),
          ),
          Positioned(
            left: _kHandleBorderInset - _kHandleTouchShort / 2,
            top: 0,
            bottom: 0,
            child: Center(child: _buildHandle(ResizeEdge.left, Axis.vertical)),
          ),
          Positioned(
            right: _kHandleBorderInset - _kHandleTouchShort / 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildHandle(ResizeEdge.right, Axis.vertical),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle(ResizeEdge edge, Axis axis) {
    return _ResizeHandle(
      axis: axis,
      onDragStart: () => onResizeStart?.call(buttonId, edge),
      onDragUpdate: (dx, dy) => onResizeUpdate?.call(
        buttonId,
        edge,
        cellWidth <= 0 ? 0 : (dx / cellWidth).round(),
        cellHeight <= 0 ? 0 : (dy / cellHeight).round(),
      ),
      onDragEnd: () => onResizeEnd?.call(buttonId, edge),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Axis axis;
  final VoidCallback onDragStart;

  /// Cumulative pixel offset (global coordinates) from where this drag
  /// began — never a per-frame increment, so the caller can convert to
  /// whole-grid-cell deltas without compounding rounding error frame over
  /// frame.
  final void Function(double dx, double dy) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _dragOrigin;
  bool _dragging = false;

  void _handlePanStart(DragStartDetails details) {
    _dragOrigin = details.globalPosition;
    setState(() => _dragging = true);
    widget.onDragStart();
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final origin = _dragOrigin;
    if (origin == null) return;
    final delta = details.globalPosition - origin;
    widget.onDragUpdate(delta.dx, delta.dy);
  }

  void _endDrag() {
    if (_dragOrigin == null) return;
    _dragOrigin = null;
    if (mounted) setState(() => _dragging = false);
    widget.onDragEnd();
  }

  @override
  void dispose() {
    // A drag that's still active when this handle unmounts (e.g. the
    // selection changed mid-gesture) must still tell the controller to
    // close its history batch — otherwise every later edit would silently
    // keep coalescing into the abandoned resize's undo entry.
    if (_dragOrigin != null) widget.onDragEnd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHorizontal = widget.axis == Axis.horizontal;
    final touchWidth = isHorizontal ? _kHandleTouchLong : _kHandleTouchShort;
    final touchHeight = isHorizontal ? _kHandleTouchShort : _kHandleTouchLong;
    final visibleWidth = isHorizontal ? _kHandleVisibleLong : _kHandleVisibleShort;
    final visibleHeight = isHorizontal ? _kHandleVisibleShort : _kHandleVisibleLong;
    const growth = 4.0;

    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: _handlePanStart,
        onPanUpdate: _handlePanUpdate,
        onPanEnd: (_) => _endDrag(),
        onPanCancel: _endDrag,
        child: SizedBox(
          width: touchWidth,
          height: touchHeight,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              width: visibleWidth + (_dragging ? growth : 0),
              height: visibleHeight + (_dragging ? growth : 0),
              decoration: BoxDecoration(
                color: _dragging
                    ? AppColors.selectionVioletDeep
                    : AppColors.selectionViolet,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: Colors.white.withAlpha(_dragging ? 230 : 170),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.selectionGlow,
                    blurRadius: _dragging ? 14 : 6,
                    spreadRadius: _dragging ? 2 : 0,
                  ),
                ],
              ),
            ),
          ),
        ),
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
