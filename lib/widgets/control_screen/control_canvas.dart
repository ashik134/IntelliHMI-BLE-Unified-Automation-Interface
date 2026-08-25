import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalog_preview_stage.dart';

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
// the customization toolbar) is the only way to ADD a widget. An unlocked
// occupied cell also supports long-press-drag-to-move (see
// _MoveDraggableCell): the SAME widget instance detaches and follows the
// finger, exactly mirroring the catalogue's own long-press carry (see
// _DraggableCatalogCard in widget_catalog_screen.dart) — LayoutEditController
// .beginMove/updateMovePreview/handleMoveDrop/commitMovedPlacement is that
// flow's controller-side counterpart to
// beginCatalogueLift/updatePlacementPreview/handleCatalogueDrop/
// commitSettledPlacement. Rendering/gesture-handling for this are both
// gated on [onMoveStart] being non-null, same convention as the resize
// handles' own [onResizeStart] gate.
// ─────────────────────────────────────────────────────────────────────────────

// Matches SettlingPreviewOverlay's own settle-animation timing, so a widget
// displaced by the live insertion preview and the newly-placed widget
// settling into its target cell read as one consistent motion. The resize
// handle overlay reuses the same constants so a resized/displaced widget,
// its neighbors, and its own handles all read as one consistent motion too.
const Duration _kRepositionDuration = Duration(milliseconds: 220);

// Long-press-drag-to-move geometry/timing — see _MoveDraggableCell. Matches
// _DraggableCatalogCard's own _kLongPressDelay (widget_catalog_screen.dart)
// so an existing widget's carry feels identical to a catalogue widget's.
const Duration _kMoveLongPressDelay = Duration(milliseconds: 400);
// Matches _OccupiedCell's own Padding(EdgeInsets.all(4)) around the real
// button, so the floating avatar is pixel-identical to the cell it detaches
// from — see handleCatalogueDrop/handleMoveDrop's identical cellInset math.
const double _kMoveCellInset = 4.0;

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

/// Long-press recognized on [id]'s occupied cell: it detaches and begins
/// following the finger. See LayoutEditController.beginMove.
typedef ButtonMoveStartCallback = void Function(String id);

/// Fired on every pointer-move frame of an active move drag, carrying the
/// floating avatar's own current top-left ([globalOffset], global/overlay
/// coordinates — already grab-offset-adjusted, never the raw pointer
/// position) and its constant on-screen size ([previewSize]). See
/// LayoutEditController.updateMovePreview.
typedef ButtonMoveUpdateCallback =
    void Function(String id, Offset globalOffset, Size previewSize);

/// Fired once when a move drag ends, from wherever the finger actually was.
/// [wasAccepted] mirrors DraggableDetails.wasAccepted — true only when
/// PlacementCancelBar accepted the drop, which already canceled the move
/// itself; see LayoutEditController.handleMoveDrop.
typedef ButtonMoveDropCallback =
    void Function(
      String id,
      bool wasAccepted,
      Offset globalOffset,
      Size previewSize,
    );

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
    this.onMoveStart,
    this.onMoveUpdate,
    this.onMoveDrop,
    this.pageTransitionStyle = CanvasPageTransitionStyle.slide,
    this.pageController,
  });

  /// Space reserved below the paged grid for arrows and page dots. Placement
  /// surfaces subtract this from their outer canvas rectangle so catalogue
  /// drops and resize math continue to use the exact visible grid bounds.
  static const double paginationExtent = 32.0;

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

  /// Long-press-drag-to-move callbacks — see [_MoveDraggableCell]. Rendering
  /// AND gesture-handling for an occupied cell's move-draggable wrapper are
  /// both gated on [onMoveStart] being non-null (same convention as
  /// [onResizeStart]), so a null callback means "no drag-to-move at all,"
  /// e.g. while a catalogue placement or a different widget's move is
  /// already in flight — see call sites in
  /// plc14_control_screen.dart/plc38_control_screen.dart.
  final ButtonMoveStartCallback? onMoveStart;
  final ButtonMoveUpdateCallback? onMoveUpdate;
  final ButtonMoveDropCallback? onMoveDrop;

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
  int _currentPage = 0;

  PageController get _pageController =>
      widget.pageController ?? (_ownedPageController ??= PageController());

  @override
  void initState() {
    super.initState();
    _currentPage = widget.pageController?.initialPage ?? 0;
  }

  @override
  void didUpdateWidget(ControlCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageController == widget.pageController) return;

    if (oldWidget.pageController == null) {
      _ownedPageController?.dispose();
      _ownedPageController = null;
    }

    final controller = widget.pageController;
    _currentPage = controller == null
        ? 0
        : controller.hasClients
        ? (controller.page?.round() ?? controller.initialPage)
        : controller.initialPage;
  }

  // True from the moment a resize handle's pointer goes down until it goes
  // up/cancels (see _ResizeHandle's Listener) — NOT the same window as
  // LayoutEditController.isResizing, which only flips once onPanStart has
  // already won the gesture arena. By then it's too late: the PageView's own
  // horizontal-drag recognizer is a SIBLING recognizer competing for the same
  // pointer (the handle lives inside this PageView's itemBuilder), so it can
  // win that arena and swipe the page instead of resizing. Locking on raw
  // pointer-down, before either recognizer has had a chance to accept,
  // removes the PageView's recognizer from the arena entirely for the
  // duration of the gesture — matching LayoutEditController's own rule that
  // a resize never leaves the widget's current page (see its
  // beginResize/updateResize/endResize doc comments).
  bool _resizeScrollLocked = false;

  void _setResizeScrollLocked(bool locked) {
    if (_resizeScrollLocked == locked) return;
    setState(() => _resizeScrollLocked = locked);
  }

  void _handlePageChanged(int pageIndex) {
    if (_currentPage == pageIndex) return;
    setState(() => _currentPage = pageIndex);
  }

  void _navigateToPage(int pageIndex, int pageCount) {
    if (pageIndex < 0 || pageIndex >= pageCount) return;
    final controller = _pageController;
    if (!controller.hasClients) return;
    controller.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildPageTransition({
    required int pageIndex,
    required Widget child,
  }) {
    final style = widget.pageTransitionStyle;
    if (style == CanvasPageTransitionStyle.slide) return child;

    return AnimatedBuilder(
      key: ValueKey('control_canvas_page_effect_${style.name}_$pageIndex'),
      animation: _pageController,
      child: child,
      builder: (context, transitionChild) {
        var currentPage = pageIndex.toDouble();
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          currentPage = _pageController.page ?? currentPage;
        }

        // Negative means this page is to the left of the viewport's current
        // position; positive means it is to the right. Limiting the value to
        // one page keeps off-screen pre-built pages from receiving extreme
        // transforms.
        final offset = (pageIndex - currentPage).clamp(-1.0, 1.0);
        final distance = offset.abs();
        final content = transitionChild!;

        return switch (style) {
          CanvasPageTransitionStyle.slide => content,
          CanvasPageTransitionStyle.fade => Opacity(
            opacity: 1 - distance,
            child: content,
          ),
          CanvasPageTransitionStyle.zoomFade => Opacity(
            opacity: 1 - distance,
            child: Transform.scale(
              scale: 0.92 + (0.08 * (1 - distance)),
              child: content,
            ),
          ),
          // Only the page being covered moves. It holds its place (the
          // FractionalTranslation cancels PageView's own slide) while
          // shrinking and dimming; the incoming page keeps its full slide,
          // so it reads as arriving OVER the old one rather than the two
          // trading places.
          CanvasPageTransitionStyle.depth => offset > 0
              ? content
              : Opacity(
                  opacity: 1 - (0.55 * distance),
                  child: FractionalTranslation(
                    translation: Offset(-offset, 0),
                    child: Transform.scale(
                      scale: 1 - (0.14 * distance),
                      child: content,
                    ),
                  ),
                ),
          CanvasPageTransitionStyle.cube => Opacity(
            opacity: 1 - (0.28 * distance),
            child: Transform(
              alignment: offset < 0
                  ? Alignment.centerRight
                  : offset > 0
                  ? Alignment.centerLeft
                  : Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(-offset * math.pi / 3),
              child: content,
            ),
          ),
        };
      },
    );
  }

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
    final pageCount = pages.isEmpty ? 1 : pages.length;
    final currentPage = _currentPage.clamp(0, pageCount - 1).toInt();

    final pageView = PageView.builder(
      key: const ValueKey('control_canvas_page_view'),
      controller: _pageController,
      physics: widget.isEditing && !_resizeScrollLocked
          ? const PageScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: pageCount,
      onPageChanged: _handlePageChanged,
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
                    child: _buildOccupiedCell(item, cellWidth, cellHeight),
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
                      onScrollLockChanged: _setResizeScrollLocked,
                    ),
                  ),
              ],
            );
          },
        );

        return _buildPageTransition(
          pageIndex: pageIndex,
          child: content,
        );
      },
    );

    return Column(
      children: [
        Expanded(child: pageView),
        SizedBox(
          height: ControlCanvas.paginationExtent,
          child: _CanvasPagination(
            currentPage: currentPage,
            pageCount: pageCount,
            onPrevious: currentPage > 0
                ? () => _navigateToPage(currentPage - 1, pageCount)
                : null,
            onNext: currentPage < pageCount - 1
                ? () => _navigateToPage(currentPage + 1, pageCount)
                : null,
          ),
        ),
      ],
    );
  }

  /// Builds [item]'s occupied cell, wrapping it in [_MoveDraggableCell] when
  /// long-press-drag-to-move applies: editing, unlocked, and every move
  /// callback provided (see [ControlCanvas.onMoveStart]'s doc comment for
  /// the null-means-off convention). [cellWidth]/[cellHeight] come from the
  /// enclosing LayoutBuilder so the draggable can compute the SAME on-screen
  /// pixel size the AnimatedPositioned box around it already uses — the
  /// floating avatar and the cell it detaches from must be pixel-identical,
  /// never a visible resize.
  Widget _buildOccupiedCell(
    ControlGridItem item,
    double cellWidth,
    double cellHeight,
  ) {
    final cell = _OccupiedCell(
      config: item.config,
      isEditing: widget.isEditing,
      isSelected: widget.isEditing && item.config.id == widget.selectedButtonId,
      activeState: widget.activeStateFor(item.config),
      isDisabled: widget.isDisabled(item.config),
      onCommand: widget.onCommand,
      onStateIdCommand: widget.onStateIdCommand,
      onAnalogCommand: widget.onAnalogCommand,
      onTap: () => widget.onSelectButton?.call(item.config.id),
      onDelete: () => widget.onDeleteButton?.call(item.config.id),
      onEdit: () {
        widget.onSelectButton?.call(item.config.id);
        widget.onEditButton?.call(item.config.id);
      },
    );

    final onMoveStart = widget.onMoveStart;
    final onMoveUpdate = widget.onMoveUpdate;
    final onMoveDrop = widget.onMoveDrop;
    if (!widget.isEditing ||
        item.config.locked ||
        onMoveStart == null ||
        onMoveUpdate == null ||
        onMoveDrop == null) {
      return cell;
    }
    return _MoveDraggableCell(
      buttonId: item.config.id,
      config: item.config,
      cellSize: Size(item.colSpan * cellWidth, item.rowSpan * cellHeight),
      onMoveStart: onMoveStart,
      onMoveUpdate: onMoveUpdate,
      onMoveDrop: onMoveDrop,
      child: cell,
    );
  }
}

class _CanvasPagination extends StatelessWidget {
  const _CanvasPagination({
    required this.currentPage,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
      child: Row(
        children: [
          if (onPrevious != null)
            _CanvasPageArrow(
              key: const ValueKey('control_canvas_previous_page'),
              icon: Icons.chevron_left_rounded,
              tooltip: 'Previous control page',
              onPressed: onPrevious!,
            )
          else
            const SizedBox.square(dimension: 28),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Semantics(
                  key: const ValueKey('control_canvas_page_status'),
                  label: 'Control page ${currentPage + 1} of $pageCount',
                  liveRegion: true,
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < pageCount; index++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: AnimatedContainer(
                              key: ValueKey('control_canvas_page_dot_$index'),
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOutCubic,
                              width: index == currentPage ? 12 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: index == currentPage
                                    ? AppColors.selectionViolet
                                    : AppColors.darkTextSub.withAlpha(60),
                                borderRadius: BorderRadius.circular(99),
                                boxShadow: index == currentPage
                                    ? const [
                                        BoxShadow(
                                          color: AppColors.selectionGlow,
                                          blurRadius: 5,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onNext != null)
            _CanvasPageArrow(
              key: const ValueKey('control_canvas_next_page'),
              icon: Icons.chevron_right_rounded,
              tooltip: 'Next control page',
              onPressed: onNext!,
            )
          else
            const SizedBox.square(dimension: 28),
        ],
      ),
    );
  }
}

class _CanvasPageArrow extends StatelessWidget {
  const _CanvasPageArrow({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 28,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: AppColors.darkTextSub,
          backgroundColor: AppColors.panelAlt.withAlpha(210),
          side: const BorderSide(color: AppColors.panelStroke),
          shape: const CircleBorder(),
          minimumSize: const Size.square(28),
          maximumSize: const Size.square(28),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
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
    required this.onScrollLockChanged,
  });

  final String buttonId;
  final double cellWidth;
  final double cellHeight;
  final ButtonResizeStartCallback? onResizeStart;
  final ButtonResizeUpdateCallback? onResizeUpdate;
  final ButtonResizeStartCallback? onResizeEnd;

  /// Fired straight from each handle's raw pointer-down (true) and
  /// pointer-up/cancel/dispose (false) — see _ResizeHandle's Listener and
  /// _ControlCanvasState._setResizeScrollLocked's doc comment for why this
  /// can't wait for onResizeStart/onResizeEnd instead.
  final ValueChanged<bool> onScrollLockChanged;

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
      onScrollLockChanged: onScrollLockChanged,
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({
    required this.axis,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onScrollLockChanged,
  });

  final Axis axis;
  final VoidCallback onDragStart;

  /// Cumulative pixel offset (global coordinates) from where this drag
  /// began — never a per-frame increment, so the caller can convert to
  /// whole-grid-cell deltas without compounding rounding error frame over
  /// frame.
  final void Function(double dx, double dy) onDragUpdate;
  final VoidCallback onDragEnd;

  /// See _ResizeHandleOverlay.onScrollLockChanged's doc comment.
  final ValueChanged<bool> onScrollLockChanged;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _dragOrigin;
  bool _dragging = false;

  // Tracks the raw pointer, independent of _dragOrigin (which only exists
  // once onPanStart has WON the gesture arena — already too late to head off
  // the PageView's competing recognizer). Locking here, on pointer-down, is
  // what actually keeps the resize handle from losing a drag to the page
  // swipe — see _ControlCanvasState._resizeScrollLocked's doc comment.
  bool _pointerDown = false;

  void _handlePointerDown(PointerDownEvent event) {
    _pointerDown = true;
    widget.onScrollLockChanged(true);
  }

  void _unlockScroll() {
    if (!_pointerDown) return;
    _pointerDown = false;
    widget.onScrollLockChanged(false);
  }

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
    _unlockScroll();
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
    // keep coalescing into the abandoned resize's undo entry. Same reasoning
    // applies to the scroll lock: an unmount mid-drag must not leave the
    // PageView permanently unswipeable.
    _unlockScroll();
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

    // Drag axis is the OPPOSITE of the handle's own pill orientation
    // (widget.axis/isHorizontal above): a top/bottom handle's pill is a
    // horizontal bar but the resize itself moves the pointer vertically
    // (rows), and a left/right handle's pill is a vertical bar but the
    // resize moves horizontally (columns) — see ResizeEdge callers in
    // _ResizeHandleOverlay._buildHandle. Using the matching axis-locked
    // recognizer (instead of a generic pan) means a top/bottom handle never
    // even enters the arena for a horizontal drag in the first place, which
    // is exactly the drag direction the PageView cares about.
    return MouseRegion(
      cursor: isHorizontal
          ? SystemMouseCursors.resizeUpDown
          : SystemMouseCursors.resizeLeftRight,
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerUp: (_) => _unlockScroll(),
        onPointerCancel: (_) => _unlockScroll(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: isHorizontal ? null : _handlePanStart,
          onHorizontalDragUpdate: isHorizontal ? null : _handlePanUpdate,
          onHorizontalDragEnd: isHorizontal ? null : (_) => _endDrag(),
          onHorizontalDragCancel: isHorizontal ? null : _endDrag,
          onVerticalDragStart: isHorizontal ? _handlePanStart : null,
          onVerticalDragUpdate: isHorizontal ? _handlePanUpdate : null,
          onVerticalDragEnd: isHorizontal ? (_) => _endDrag() : null,
          onVerticalDragCancel: isHorizontal ? _endDrag : null,
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

// ─────────────────────────────────────────────────────────────────────────────
// _MoveDraggableCell
//
// Wraps an occupied cell with long-press-to-move, reusing LongPressDraggable
// exactly like _DraggableCatalogCard does for the catalogue (see that
// widget's doc comment in widget_catalog_screen.dart for why
// LongPressDraggable specifically — its DelayedMultiDragGestureRecognizer
// arbitrates correctly against tap-to-select/the badges' own GestureDetectors
// below it in the tree).
//
// Deliberately STAYS MOUNTED at the same grid position for the ENTIRE live
// drag: LayoutEditController.previewLayoutCfg keeps this cell's button in
// its returned map throughout CustomizationInteractionMode.movingWidget
// (only removing it once the drag has fully ended and settlingMovedWidget's
// non-cancelable animation begins — see that getter's own doc comment), so
// this widget's own Element is never a candidate for removal from
// ControlCanvas's Stack children while its LongPressDraggable's gesture is
// still live. The origin cell instead reads as vacant via [childWhenDragging]
// — Flutter's own built-in, zero-risk mechanism for exactly this ("look
// empty while carrying"), swapped in by Draggable's own internal dragging
// state without ever touching this Element. This mirrors why
// CatalogueOverlayHost keeps the catalogue's source card mounted (just
// slid off-screen) for the whole placingWidget drag too, rather than
// leaning on Draggable's "survives removal mid-drag" guarantee — that
// guarantee is real, but both flows deliberately avoid depending on it for
// the live portion of the gesture, only unmounting after the drag ends.
// ─────────────────────────────────────────────────────────────────────────────

class _MoveDraggableCell extends StatefulWidget {
  const _MoveDraggableCell({
    required this.buttonId,
    required this.config,
    required this.cellSize,
    required this.onMoveStart,
    required this.onMoveUpdate,
    required this.onMoveDrop,
    required this.child,
  });

  final String buttonId;
  final ButtonConfig config;

  /// The cell's current outer grid-cell pixel size (colSpan*cellWidth x
  /// rowSpan*cellHeight) — never the inner padded size; see [_previewSize].
  final Size cellSize;

  final ButtonMoveStartCallback onMoveStart;
  final ButtonMoveUpdateCallback onMoveUpdate;
  final ButtonMoveDropCallback onMoveDrop;
  final Widget child;

  @override
  State<_MoveDraggableCell> createState() => _MoveDraggableCellState();
}

class _MoveDraggableCellState extends State<_MoveDraggableCell> {
  Offset? _dragAnchor;
  bool _dragFinishHandled = false;

  /// The floating avatar's size — [cellSize] deflated by the same inset
  /// _OccupiedCell's own Padding applies, so the avatar is pixel-identical
  /// to the real button it detaches from (never a visible resize pop).
  Size get _previewSize => Size(
    (widget.cellSize.width - _kMoveCellInset * 2).clamp(0, double.infinity),
    (widget.cellSize.height - _kMoveCellInset * 2).clamp(0, double.infinity),
  );

  /// Maps the touched point into the (inner, padded) preview's coordinate
  /// space — mirrors _DraggableCatalogCardState._grabAnchor exactly (see its
  /// doc comment), just against this cell's own outer bounds instead of a
  /// catalogue card's.
  Offset _grabAnchor(
    Draggable<Object> draggable,
    BuildContext context,
    Offset position,
  ) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      final fallback = _previewSize.center(Offset.zero);
      _dragAnchor = fallback;
      return fallback;
    }
    final local = renderBox.globalToLocal(position);
    final anchor = local - const Offset(_kMoveCellInset, _kMoveCellInset);
    _dragAnchor = anchor;
    return anchor;
  }

  void _handleDragStarted() {
    _dragFinishHandled = false;
    HapticFeedback.selectionClick();
    widget.onMoveStart(widget.buttonId);
  }

  /// See _DraggableCatalogCardState._handleDragUpdate's doc comment —
  /// identical math, converting the pointer's own global position into the
  /// avatar's top-left via the anchor [_grabAnchor] recorded.
  void _handleDragUpdate(DragUpdateDetails details) {
    final anchor = _dragAnchor ?? _previewSize.center(Offset.zero);
    widget.onMoveUpdate(
      widget.buttonId,
      details.globalPosition - anchor,
      _previewSize,
    );
  }

  void _handleDragEnd(bool wasAccepted, Offset offset) {
    if (_dragFinishHandled) return;
    _dragFinishHandled = true;
    widget.onMoveDrop(widget.buttonId, wasAccepted, offset, _previewSize);
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<String>(
      data: widget.buttonId,
      delay: _kMoveLongPressDelay,
      hapticFeedbackOnStart: false,
      dragAnchorStrategy: _grabAnchor,
      feedback: _LiftedMovePreview(
        config: widget.config,
        size: _previewSize,
        dragAnchor: () => _dragAnchor,
      ),
      // Reuses the exact same vacant-cell visual a truly empty slot would
      // show — see this class's doc comment for why the origin cell stays
      // mounted (never removed from the tree) throughout the live drag.
      childWhenDragging: const _VacantCell(),
      onDragStarted: _handleDragStarted,
      onDragUpdate: _handleDragUpdate,
      onDragEnd: (details) =>
          _handleDragEnd(details.wasAccepted, details.offset),
      onDraggableCanceled: (_, offset) => _handleDragEnd(false, offset),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiftedMovePreview
//
// The floating avatar for a canvas move — CatalogPreviewStage rendering the
// SAME real ButtonConfig the origin cell showed (never a lookalike), at
// exactly the size it rendered at there, plus a one-shot lift animation
// (scale + soft shadow) mirroring _LiftingCataloguePreview in
// widget_catalog_screen.dart exactly (see that widget's doc comment) — the
// "Widget lifts" step of the required interaction. Unlike the catalogue
// preview, there is no onLiftComplete/mode-advance here: beginMove already
// flips interactionMode straight to movingWidget on drag start, since a
// canvas move has no catalogue-overlay reveal to sequence around.
//
// Watches LayoutEditController.interactionMode so a Cancel elsewhere (the
// Cancel bar, tapped or dropped onto with a second finger) can make this
// preview vanish immediately, even though the underlying drag gesture may
// still be silently active until the finger actually lifts — same reasoning
// as _LiftingCataloguePreview's own doc comment.
// ─────────────────────────────────────────────────────────────────────────────

class _LiftedMovePreview extends StatefulWidget {
  const _LiftedMovePreview({
    required this.config,
    required this.size,
    required this.dragAnchor,
  });

  final ButtonConfig config;
  final Size size;
  final Offset? Function() dragAnchor;

  @override
  State<_LiftedMovePreview> createState() => _LiftedMovePreviewState();
}

class _LiftedMovePreviewState extends State<_LiftedMovePreview>
    with SingleTickerProviderStateMixin {
  static const _liftDuration = Duration(milliseconds: 160);

  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<int> _shadowAlpha;
  late final Animation<double> _shadowBlur;
  late final Animation<double> _shadowDy;
  late final Alignment _scaleAlignment;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _liftDuration);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _scale = Tween<double>(begin: 1.0, end: 1.03).animate(curved);
    _shadowAlpha = IntTween(begin: 0, end: 56).animate(curved);
    _shadowBlur = Tween<double>(begin: 0, end: 10).animate(curved);
    _shadowDy = Tween<double>(begin: 0, end: 3).animate(curved);
    _scaleAlignment = _scaleAlignmentFor(widget.dragAnchor());
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Alignment _scaleAlignmentFor(Offset? anchor) {
    final effectiveAnchor = anchor ?? widget.size.center(Offset.zero);
    final x = widget.size.width <= 0
        ? 0.0
        : (effectiveAnchor.dx / widget.size.width) * 2 - 1;
    final y = widget.size.height <= 0
        ? 0.0
        : (effectiveAnchor.dy / widget.size.height) * 2 - 1;
    return Alignment(x, y);
  }

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<LayoutEditController>().interactionMode;
    final isLive = mode == CustomizationInteractionMode.movingWidget;

    final stage = SizedBox(
      width: widget.size.width,
      height: widget.size.height,
      child: CatalogPreviewStage(config: widget.config, previewSize: widget.size),
    );

    return Material(
      type: MaterialType.transparency,
      child: !isLive
          ? const SizedBox.shrink()
          : AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.scale(
                alignment: _scaleAlignment,
                scale: _scale.value,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(_shadowAlpha.value),
                        blurRadius: _shadowBlur.value,
                        spreadRadius: -1,
                        offset: Offset(0, _shadowDy.value),
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
              child: stage,
            ),
    );
  }
}
