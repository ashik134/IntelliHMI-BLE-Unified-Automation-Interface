import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_badge.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/dot_grid_background.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/drag_dots_indicator.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/selection_overlay.dart';
import 'package:rev_crane_control_ops/widgets/customization/selection_overlay/widget_transformer.dart';

typedef ButtonActiveStateResolver = ControlState Function(ButtonConfig config);
typedef ButtonDisabledResolver = bool Function(ButtonConfig config);
typedef ButtonCommandDispatcher =
    void Function(String buttonId, ControlState state);
typedef AnalogButtonCommandDispatcher =
    void Function(ButtonConfig config, double value);
typedef ButtonEditorLauncher = void Function(ButtonConfig config);
typedef ButtonSelectionHandler = void Function(ButtonConfig? config);
typedef ButtonResizeHandler =
    void Function(
      ButtonConfig config,
      int gridColumns,
      int gridRows, {
      int? anchorX,
      int? anchorY,
    });
typedef ButtonSlotDropHandler =
    void Function(
      ButtonConfig dragged,
      int sourceSlot,
      ButtonConfig? target,
      int targetSlot, {
      required int targetPageIndex,
    });
typedef VacantSlotHandler = void Function(int pageIndex, int slotIndex);

class ControlSlotGrid extends StatefulWidget {
  const ControlSlotGrid({
    super.key,
    required this.layoutCfg,
    required this.roles,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    required this.onEditButton,
    this.onAnalogCommand,
    this.selectedRole,
    this.selectedButtonId,
    this.onSelectButton,
    this.onSlotDrop,
    this.onResizeButton,
    this.onSelectVacantSlot,
    this.onPageChanged,
    this.activePageIndex = 0,
    this.slotCount = ButtonConfig.controlSlotCount,
    this.spacing = 10,
  });

  static const int columns = ButtonConfig.controlGridColumns;
  static const int rows = ButtonConfig.controlGridRows;

  final ControlLayoutConfig layoutCfg;
  final List<ControlRole> roles;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final AnalogButtonCommandDispatcher? onAnalogCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;
  final VacantSlotHandler? onSelectVacantSlot;
  final ValueChanged<int>? onPageChanged;
  final int activePageIndex;
  final int slotCount;
  final double spacing;

  @override
  State<ControlSlotGrid> createState() => _ControlSlotGridState();
}

class _ControlSlotGridState extends State<ControlSlotGrid> {
  late final PageController _pageController;
  int _activePage = 0;

  @override
  void initState() {
    super.initState();
    _activePage = math.max(0, widget.activePageIndex);
    _pageController = PageController(initialPage: _activePage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ControlSlotGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activePageIndex != oldWidget.activePageIndex &&
        widget.activePageIndex != _activePage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _goToPage(widget.activePageIndex);
      });
    }
  }

  void _goToPage(int index) {
    if (!_pageController.hasClients || index == _activePage) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = buildControlGridPages(
      layoutCfg: widget.layoutCfg,
      roles: widget.roles,
      slotCount: widget.slotCount,
    );
    if (_activePage >= pages.length) {
      final lastPage = pages.length - 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _activePage = lastPage);
        widget.onPageChanged?.call(lastPage);
        if (_pageController.hasClients) {
          _pageController.jumpToPage(lastPage);
        }
      });
    }

    final rows = (widget.slotCount / ControlSlotGrid.columns).ceil();
    final minGridWidth =
        ControlSlotGrid.columns * ButtonConfig.minButtonWidthPx +
        (ControlSlotGrid.columns - 1) * widget.spacing;
    final minGridHeight =
        rows * ButtonConfig.minButtonHeightPx + (rows - 1) * widget.spacing;
    final dotHeight = pages.length > 1 ? 44.0 : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.hasBoundedWidth
            ? math.max(constraints.maxWidth, minGridWidth)
            : minGridWidth;
        final availableHeight = constraints.hasBoundedHeight
            ? math.max(0.0, constraints.maxHeight - dotHeight)
            : minGridHeight;
        final gridHeight = math.max(availableHeight, minGridHeight);

        final pagedGrid = Column(
          mainAxisSize: constraints.hasBoundedHeight
              ? MainAxisSize.max
              : MainAxisSize.min,
          children: [
            SizedBox(
              width: gridWidth,
              height: gridHeight,
              child: PageView.builder(
                controller: _pageController,
                physics: widget.isEditing
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() => _activePage = index);
                  widget.onPageChanged?.call(index);
                },
                itemBuilder: (context, index) => _SlotGridBody(
                  page: pages[index],
                  rows: rows,
                  slotCount: widget.slotCount,
                  spacing: widget.spacing,
                  isEditing: widget.isEditing,
                  activeStateFor: widget.activeStateFor,
                  isDisabled: widget.isDisabled,
                  onCommand: widget.onCommand,
                  onAnalogCommand: widget.onAnalogCommand,
                  onEditButton: widget.onEditButton,
                  selectedRole: widget.selectedRole,
                  selectedButtonId: widget.selectedButtonId,
                  onSelectButton: widget.onSelectButton,
                  onSlotDrop: widget.onSlotDrop,
                  onResizeButton: widget.onResizeButton,
                  onSelectVacantSlot: widget.onSelectVacantSlot,
                ),
              ),
            ),
            if (pages.length > 1)
              SizedBox(
                height: dotHeight,
                child: _PageDots(
                  count: pages.length,
                  activeIndex: _activePage.clamp(0, pages.length - 1),
                  dotsAreTappable: widget.isEditing,
                  onTap: _goToPage,
                ),
              ),
          ],
        );

        final overflowsWidth =
            constraints.hasBoundedWidth && gridWidth > constraints.maxWidth;
        final overflowsHeight =
            constraints.hasBoundedHeight &&
            gridHeight + dotHeight > constraints.maxHeight;
        if (!overflowsWidth && !overflowsHeight) return pagedGrid;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: gridWidth, child: pagedGrid),
        );
      },
    );
  }
}

class _SlotGridBody extends StatelessWidget {
  const _SlotGridBody({
    required this.page,
    required this.rows,
    required this.slotCount,
    required this.spacing,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    required this.onAnalogCommand,
    required this.onEditButton,
    required this.selectedRole,
    required this.selectedButtonId,
    required this.onSelectButton,
    required this.onSlotDrop,
    required this.onResizeButton,
    required this.onSelectVacantSlot,
  });

  final ControlGridPage page;
  final int rows;
  final int slotCount;
  final double spacing;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final AnalogButtonCommandDispatcher? onAnalogCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;
  final VacantSlotHandler? onSelectVacantSlot;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isEditing ? 1 : 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth =
              (constraints.maxWidth - (ControlSlotGrid.columns - 1) * spacing) /
              ControlSlotGrid.columns;
          final cellHeight =
              (constraints.maxHeight - (rows - 1) * spacing) / rows;

          Rect rectFor(int slot, int colSpan, int rowSpan) {
            final row = slot ~/ ControlSlotGrid.columns;
            final col = slot % ControlSlotGrid.columns;
            return Rect.fromLTWH(
              col * (cellWidth + spacing),
              row * (cellHeight + spacing),
              colSpan * cellWidth + (colSpan - 1) * spacing,
              rowSpan * cellHeight + (rowSpan - 1) * spacing,
            );
          }

          final transformer = WidgetTransformer(
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            spacing: spacing,
            gridColumns: ControlSlotGrid.columns,
            gridRows: rows,
          );

          ControlGridItem? selectedItem;
          for (final item in page.items) {
            final matchesRole =
                item.config.role != null && item.config.role == selectedRole;
            final matchesId = item.config.id == selectedButtonId;
            if (matchesRole || matchesId) {
              selectedItem = item;
              break;
            }
          }

          return Stack(
            clipBehavior: Clip.none,
            children: [
              if (isEditing) const Positioned.fill(child: DotGridBackground()),
              if (isEditing)
                for (var slot = 0; slot < slotCount; slot++)
                  if (page.occupants[slot] == null)
                    Positioned.fromRect(
                      rect: rectFor(slot, 1, 1),
                      child: _SlotTarget(
                        key: ValueKey(
                          page.pageIndex == 0
                              ? 'control_slot_$slot'
                              : 'control_slot_${page.pageIndex}_$slot',
                        ),
                        pageIndex: page.pageIndex,
                        slotIndex: slot,
                        item: null,
                        isEditing: true,
                        activeStateFor: activeStateFor,
                        isDisabled: isDisabled,
                        onCommand: onCommand,
                        onAnalogCommand: onAnalogCommand,
                        onEditButton: onEditButton,
                        selectedRole: selectedRole,
                        selectedButtonId: selectedButtonId,
                        onSelectButton: onSelectButton,
                        onSlotDrop: onSlotDrop,
                        onResizeButton: onResizeButton,
                        onSelectVacantSlot: onSelectVacantSlot,
                      ),
                    ),
              for (final item in page.items)
                Positioned.fromRect(
                  rect: rectFor(item.visualSlot, item.colSpan, item.rowSpan),
                  child: _SlotTarget(
                    key: ValueKey(
                      page.pageIndex == 0
                          ? 'control_slot_${item.visualSlot}'
                          : 'control_slot_${page.pageIndex}_${item.visualSlot}',
                    ),
                    pageIndex: page.pageIndex,
                    slotIndex: item.visualSlot,
                    item: item,
                    isEditing: isEditing,
                    activeStateFor: activeStateFor,
                    isDisabled: isDisabled,
                    onCommand: onCommand,
                    onAnalogCommand: onAnalogCommand,
                    onEditButton: onEditButton,
                    selectedRole: selectedRole,
                    selectedButtonId: selectedButtonId,
                    onSelectButton: onSelectButton,
                    onSlotDrop: onSlotDrop,
                    onResizeButton: onResizeButton,
                    onSelectVacantSlot: onSelectVacantSlot,
                  ),
                ),
              if (isEditing && selectedItem != null && onResizeButton != null)
                _SelectedItemOverlay(
                  key: ValueKey('overlay_${selectedItem.config.id}'),
                  item: selectedItem,
                  transformer: transformer,
                  canvasSize: Size(constraints.maxWidth, constraints.maxHeight),
                  onResizeButton: onResizeButton!,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SelectedItemOverlay
//
// Bridges the generic, model-agnostic SelectionOverlay to this grid's
// ButtonConfig/slot-based mutation pipeline. Resize is *previewed* purely
// visually (a ghost frame + live "W x H" pill) while dragging, and only
// mutates the real draft — via the same buildButtonResize/onResizeButton
// path the old handle used — once the gesture ends. This keeps every
// intermediate pixel of drag from hitting undo/redo or PLC-adjacent
// validation, while still giving Figma-style live feedback.
// ─────────────────────────────────────────────────────────────────────────────

class _SelectedItemOverlay extends StatelessWidget {
  const _SelectedItemOverlay({
    super.key,
    required this.item,
    required this.transformer,
    required this.canvasSize,
    required this.onResizeButton,
  });

  final ControlGridItem item;
  final WidgetTransformer transformer;
  final Size canvasSize;
  final ButtonResizeHandler onResizeButton;

  @override
  Widget build(BuildContext context) {
    final minSize = ButtonConfig.defaultGridSizeFor(
      item.config.type,
      customProperties: item.config.customProperties,
    );
    return ControlSelectionOverlay(
      span: GridSpan(
        x: item.gridX,
        y: item.gridY,
        columns: item.colSpan,
        rows: item.rowSpan,
      ),
      transformer: transformer,
      canvasSize: canvasSize,
      minColumns: minSize.$1,
      minRows: minSize.$2,
      borderRadius: 8,
      onResizePreview: (_) {},
      onResizeCommit: (span) => onResizeButton(
        item.config,
        span.columns,
        span.rows,
        anchorX: span.x,
        anchorY: span.y,
      ),
    );
  }
}

class _DraggedSlot {
  const _DraggedSlot({
    required this.config,
    required this.sourceSlot,
    required this.sourcePageIndex,
  });

  final ButtonConfig config;
  final int sourceSlot;
  final int sourcePageIndex;
}

class _SlotTarget extends StatefulWidget {
  const _SlotTarget({
    super.key,
    required this.pageIndex,
    required this.slotIndex,
    required this.item,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    required this.onAnalogCommand,
    required this.onEditButton,
    required this.selectedRole,
    required this.selectedButtonId,
    required this.onSelectButton,
    required this.onSlotDrop,
    required this.onResizeButton,
    required this.onSelectVacantSlot,
  });

  final int pageIndex;
  final int slotIndex;
  final ControlGridItem? item;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final AnalogButtonCommandDispatcher? onAnalogCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;
  final VacantSlotHandler? onSelectVacantSlot;

  @override
  State<_SlotTarget> createState() => _SlotTargetState();
}

class _SlotTargetState extends State<_SlotTarget> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditing) {
      return _SlotFrame(
        isEditing: false,
        isHighlighted: false,
        isSelected: false,
        child: widget.item == null
            ? const SizedBox.shrink()
            : RepaintBoundary(
                child: _ButtonBody(
                  config: widget.item!.config,
                  activeState: widget.activeStateFor(widget.item!.config),
                  isDisabled: widget.isDisabled(widget.item!.config),
                  onCommand: widget.onCommand,
                  onAnalogCommand: widget.onAnalogCommand,
                ),
              ),
      );
    }

    return DragTarget<_DraggedSlot>(
      onWillAcceptWithDetails: (details) =>
          details.data.sourcePageIndex != widget.pageIndex ||
          details.data.sourceSlot != widget.slotIndex,
      onMove: (_) {
        if (!_hovered) setState(() => _hovered = true);
      },
      onLeave: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      onAcceptWithDetails: (details) {
        setState(() => _hovered = false);
        widget.onSlotDrop?.call(
          details.data.config,
          details.data.sourceSlot,
          widget.item?.config,
          widget.slotIndex,
          targetPageIndex: widget.pageIndex,
        );
      },
      builder: (context, candidates, rejects) {
        final highlighted = _hovered || candidates.isNotEmpty;
        final selected =
            widget.item?.config.role != null &&
                widget.item!.config.role == widget.selectedRole ||
            widget.item?.config.id == widget.selectedButtonId;
        final vacantSlotId = vacantSlotSelectionId(
          widget.pageIndex,
          widget.slotIndex,
        );
        final vacantSelected = widget.selectedButtonId == vacantSlotId;
        return _SlotFrame(
          isEditing: true,
          isHighlighted: highlighted,
          isSelected: selected || vacantSelected,
          child: widget.item == null
              ? _EmptySlot(
                  slotIndex: widget.slotIndex,
                  isSelected: vacantSelected,
                  onTap: widget.onSelectVacantSlot == null
                      ? null
                      : () => widget.onSelectVacantSlot!(
                          widget.pageIndex,
                          widget.slotIndex,
                        ),
                )
              : _DraggableSlotContent(
                  item: widget.item!,
                  activeState: widget.activeStateFor(widget.item!.config),
                  isDisabled: widget.isDisabled(widget.item!.config),
                  onCommand: widget.onCommand,
                  onAnalogCommand: widget.onAnalogCommand,
                  onEditButton: widget.onEditButton,
                  onResizeButton: widget.onResizeButton,
                  isSelected: selected,
                  onSelectButton: widget.onSelectButton,
                ),
        );
      },
    );
  }
}

class _SlotFrame extends StatelessWidget {
  const _SlotFrame({
    required this.isEditing,
    required this.isHighlighted,
    required this.isSelected,
    required this.child,
  });

  final bool isEditing;
  final bool isHighlighted;
  // Selection itself is drawn by _SelectedItemOverlay (a violet frame that
  // sits outside this clipped box); kept here only so callers don't need
  // to special-case selected slots when deciding whether to dim/clip.
  final bool isSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showEditFrame = isEditing && isHighlighted;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: showEditFrame
            ? AppColors.panel.withAlpha(120)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: showEditFrame
            ? Border.all(color: AppColors.accent, width: 2)
            : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(8), child: child),
    );
  }
}

class _DraggableSlotContent extends StatelessWidget {
  const _DraggableSlotContent({
    required this.item,
    required this.activeState,
    required this.isDisabled,
    required this.onCommand,
    required this.onAnalogCommand,
    required this.onEditButton,
    required this.onResizeButton,
    required this.isSelected,
    required this.onSelectButton,
  });

  final ControlGridItem item;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandDispatcher onCommand;
  final AnalogButtonCommandDispatcher? onAnalogCommand;
  final ButtonEditorLauncher onEditButton;
  final ButtonResizeHandler? onResizeButton;
  final bool isSelected;
  final ButtonSelectionHandler? onSelectButton;

  @override
  Widget build(BuildContext context) {
    // Selection itself is drawn by _SelectedItemOverlay, a sibling in the
    // parent Stack positioned *outside* this tile's clip — that's the only
    // way the frame can sit 2px proud of the widget edge without being cut
    // off by the ClipRRect in _SlotFrame. This tile only shows the
    // unselected drag-affordance and the customize badge.
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelectButton?.call(item.config),
      child: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              child: RepaintBoundary(
                child: _ButtonBody(
                  config: item.config,
                  activeState: activeState,
                  isDisabled: true,
                  onCommand: onCommand,
                  onAnalogCommand: onAnalogCommand,
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: CustomizationBadge(
              icon: Icons.edit_rounded,
              color: AppColors.darkBg,
              onTap: () => onEditButton(item.config),
              tooltip: 'Customize',
            ),
          ),
          if (!isSelected)
            const Positioned(left: 8, top: 8, child: DragDotsIndicator()),
        ],
      ),
    );

    return LongPressDraggable<_DraggedSlot>(
      key: ValueKey(item.config.id),
      data: _DraggedSlot(
        config: item.config,
        sourceSlot: item.visualSlot,
        sourcePageIndex: item.pageIndex,
      ),
      onDragStarted: () => onSelectButton?.call(item.config),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 168.0 * item.colSpan + 10.0 * (item.colSpan - 1),
          height: 136.0 * item.rowSpan + 10.0 * (item.rowSpan - 1),
          child: Opacity(opacity: 0.9, child: body),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.28, child: body),
      child: body,
    );
  }
}

class _ButtonBody extends StatelessWidget {
  const _ButtonBody({
    required this.config,
    required this.activeState,
    required this.isDisabled,
    required this.onCommand,
    required this.onAnalogCommand,
  });

  final ButtonConfig config;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandDispatcher onCommand;
  final AnalogButtonCommandDispatcher? onAnalogCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConfigurableButton(
          config: config,
          activeState: activeState,
          isDisabled: isDisabled,
          onCommand: onCommand,
          onAnalogCommand: onAnalogCommand,
          height: constraints.maxHeight,
        );
      },
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({
    required this.slotIndex,
    required this.isSelected,
    required this.onTap,
  });

  final int slotIndex;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // A vacant slot is safe-by-construction: tapping it only opens the
    // add/edit flow (see onSelectVacantSlot wiring in the control screens)
    // and never dispatches a PLC command, so it needs no isDisabled/
    // onCommand plumbing the way an occupied slot's ConfigurableButton does.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: DottedSlotBorder(
          color: isSelected ? AppColors.accent : AppColors.darkBorder,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                'SLOT ${slotIndex + 1}',
                style: TextStyle(
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.darkTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: CustomizationBadge(
                  icon: Icons.edit_rounded,
                  color: isSelected ? AppColors.accent : AppColors.darkBg,
                  onTap: onTap ?? () {},
                  tooltip: 'Add control',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DottedSlotBorder extends StatelessWidget {
  const DottedSlotBorder({super.key, required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color),
      child: Padding(padding: const EdgeInsets.all(2), child: child),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashWidth = 5.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + dashWidth, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.activeIndex,
    required this.dotsAreTappable,
    required this.onTap,
  });

  final int count;
  final int activeIndex;
  final bool dotsAreTappable;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_left_rounded, size: 18),
          color: activeIndex > 0
              ? AppColors.darkTextSub
              : AppColors.darkTextMuted.withAlpha(90),
          onPressed: activeIndex > 0 ? () => onTap(activeIndex - 1) : null,
        ),
        for (var i = 0; i < count; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dotsAreTappable ? () => onTap(i) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: i == activeIndex ? 9 : 7,
              height: i == activeIndex ? 9 : 7,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: AppColors.darkText.withAlpha(
                  i == activeIndex ? 235 : 95,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.chevron_right_rounded, size: 18),
          color: activeIndex < count - 1
              ? AppColors.darkTextSub
              : AppColors.darkTextMuted.withAlpha(90),
          onPressed: activeIndex < count - 1
              ? () => onTap(activeIndex + 1)
              : null,
        ),
      ],
    );
  }
}
