import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_badge.dart';

typedef ButtonActiveStateResolver = ControlState Function(ButtonConfig config);
typedef ButtonDisabledResolver = bool Function(ButtonConfig config);
typedef ButtonCommandDispatcher =
    void Function(String buttonId, ControlState state);
typedef ButtonEditorLauncher = void Function(ButtonConfig config);
typedef ButtonSelectionHandler = void Function(ButtonConfig? config);
typedef ButtonResizeHandler =
    void Function(ButtonConfig config, int gridColumns, int gridRows);
typedef ButtonSlotDropHandler =
    void Function(
      ButtonConfig dragged,
      int sourceSlot,
      ButtonConfig? target,
      int targetSlot, {
      required int targetPageIndex,
    });

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
    this.selectedRole,
    this.selectedButtonId,
    this.onSelectButton,
    this.onSlotDrop,
    this.onResizeButton,
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
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;
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
    _pageController = PageController();
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
        _pageController.animateToPage(
          widget.activePageIndex,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = buildControlGridPages(
      layoutCfg: widget.layoutCfg,
      roles: widget.roles,
      slotCount: widget.slotCount,
    );
    if (_activePage >= pages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _activePage = pages.length - 1);
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
                  onEditButton: widget.onEditButton,
                  selectedRole: widget.selectedRole,
                  selectedButtonId: widget.selectedButtonId,
                  onSelectButton: widget.onSelectButton,
                  onSlotDrop: widget.onSlotDrop,
                  onResizeButton: widget.onResizeButton,
                ),
              ),
            ),
            if (pages.length > 1)
              SizedBox(
                height: dotHeight,
                child: _PageDots(
                  count: pages.length,
                  activeIndex: _activePage.clamp(0, pages.length - 1),
                  onTap: (index) {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                    );
                  },
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
    required this.onEditButton,
    required this.selectedRole,
    required this.selectedButtonId,
    required this.onSelectButton,
    required this.onSlotDrop,
    required this.onResizeButton,
  });

  final ControlGridPage page;
  final int rows;
  final int slotCount;
  final double spacing;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;

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

          return Stack(
            children: [
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
                        onEditButton: onEditButton,
                        selectedRole: selectedRole,
                        selectedButtonId: selectedButtonId,
                        onSelectButton: onSelectButton,
                        onSlotDrop: onSlotDrop,
                        onResizeButton: onResizeButton,
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
                    onEditButton: onEditButton,
                    selectedRole: selectedRole,
                    selectedButtonId: selectedButtonId,
                    onSelectButton: onSelectButton,
                    onSlotDrop: onSlotDrop,
                    onResizeButton: onResizeButton,
                  ),
                ),
            ],
          );
        },
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
    required this.onEditButton,
    required this.selectedRole,
    required this.selectedButtonId,
    required this.onSelectButton,
    required this.onSlotDrop,
    required this.onResizeButton,
  });

  final int pageIndex;
  final int slotIndex;
  final ControlGridItem? item;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final String? selectedButtonId;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final ButtonResizeHandler? onResizeButton;

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
            : _ButtonBody(
                config: widget.item!.config,
                activeState: widget.activeStateFor(widget.item!.config),
                isDisabled: widget.isDisabled(widget.item!.config),
                onCommand: widget.onCommand,
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
        return _SlotFrame(
          isEditing: true,
          isHighlighted: highlighted,
          isSelected: selected,
          child: widget.item == null
              ? _EmptySlot(slotIndex: widget.slotIndex)
              : _DraggableSlotContent(
                  item: widget.item!,
                  activeState: widget.activeStateFor(widget.item!.config),
                  isDisabled: widget.isDisabled(widget.item!.config),
                  onCommand: widget.onCommand,
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
  final bool isSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showEditFrame = isEditing && (isHighlighted || isSelected);

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
            ? Border.all(
                color: isSelected
                    ? AppColors.darkSuccess
                    : isHighlighted
                    ? AppColors.accent
                    : AppColors.darkBorder.withAlpha(170),
                width: isSelected || isHighlighted ? 2 : 1,
              )
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
    required this.onEditButton,
    required this.onResizeButton,
    required this.isSelected,
    required this.onSelectButton,
  });

  final ControlGridItem item;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ButtonResizeHandler? onResizeButton;
  final bool isSelected;
  final ButtonSelectionHandler? onSelectButton;

  @override
  Widget build(BuildContext context) {
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelectButton?.call(item.config),
      child: Stack(
        children: [
          Positioned.fill(
            child: AbsorbPointer(
              child: _ButtonBody(
                config: item.config,
                activeState: activeState,
                isDisabled: true,
                onCommand: onCommand,
              ),
            ),
          ),
          if (isSelected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.darkSuccess.withAlpha(230),
                      width: 2,
                    ),
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
          const Positioned(left: 8, top: 8, child: _DragHandle()),
          if (isSelected && onResizeButton != null)
            Positioned(
              right: 8,
              bottom: 8,
              child: _ResizeHandle(
                config: item.config,
                onResizeButton: onResizeButton!,
              ),
            ),
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
  });

  final ButtonConfig config;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandDispatcher onCommand;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ConfigurableButton(
          config: config,
          activeState: activeState,
          isDisabled: isDisabled,
          onCommand: onCommand,
          height: constraints.maxHeight,
        );
      },
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot({required this.slotIndex});

  final int slotIndex;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'SLOT ${slotIndex + 1}',
        style: const TextStyle(
          color: AppColors.darkTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Drag to move',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.panel.withAlpha(235),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.drag_indicator,
            size: 16,
            color: AppColors.darkText,
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.config, required this.onResizeButton});

  final ButtonConfig config;
  final ButtonResizeHandler onResizeButton;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset _drag = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Resize',
      child: GestureDetector(
        onPanUpdate: (details) => _drag += details.delta,
        onPanEnd: (_) {
          final growX = _drag.dx > 24;
          final shrinkX = _drag.dx < -24;
          final growY = _drag.dy > 24;
          final shrinkY = _drag.dy < -24;
          final nextColumns =
              widget.config.gridColumnSpan +
              (growX
                  ? 1
                  : shrinkX
                  ? -1
                  : 0);
          final nextRows =
              widget.config.gridRowSpan +
              (growY
                  ? 1
                  : shrinkY
                  ? -1
                  : 0);
          _drag = Offset.zero;
          widget.onResizeButton(widget.config, nextColumns, nextRows);
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.darkSuccess.withAlpha(235),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.darkText),
          ),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
              Icons.open_in_full_rounded,
              size: 14,
              color: AppColors.darkBg,
            ),
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.activeIndex,
    required this.onTap,
  });

  final int count;
  final int activeIndex;
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
            onTap: () => onTap(i),
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
