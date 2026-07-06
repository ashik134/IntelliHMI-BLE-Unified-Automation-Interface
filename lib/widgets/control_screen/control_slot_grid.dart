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
typedef ButtonSlotDropHandler =
    void Function(
      ButtonConfig dragged,
      int sourceSlot,
      ButtonConfig? target,
      int targetSlot,
    );

class ControlSlotGrid extends StatelessWidget {
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
    this.onSelectButton,
    this.onSlotDrop,
    this.slotCount = ButtonConfig.controlSlotCount,
    this.spacing = 10,
  });

  static const int columns = ButtonConfig.controlGridColumns;

  final ControlLayoutConfig layoutCfg;
  final List<ControlRole> roles;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;
  final int slotCount;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final layout = _resolveLayout();
    final rows = (slotCount / columns).ceil();
    final minGridWidth =
        columns * ButtonConfig.minButtonWidthPx + (columns - 1) * spacing;
    final minGridHeight =
        rows * ButtonConfig.minButtonHeightPx + (rows - 1) * spacing;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = constraints.hasBoundedWidth
            ? math.max(constraints.maxWidth, minGridWidth)
            : minGridWidth;
        final gridHeight = constraints.hasBoundedHeight
            ? math.max(constraints.maxHeight, minGridHeight)
            : minGridHeight;
        final grid = SizedBox(
          width: gridWidth,
          height: gridHeight,
          child: _SlotGridBody(
            layout: layout,
            rows: rows,
            slotCount: slotCount,
            spacing: spacing,
            isEditing: isEditing,
            activeStateFor: activeStateFor,
            isDisabled: isDisabled,
            onCommand: onCommand,
            onEditButton: onEditButton,
            selectedRole: selectedRole,
            onSelectButton: onSelectButton,
            onSlotDrop: onSlotDrop,
          ),
        );

        final overflowsWidth =
            constraints.hasBoundedWidth && gridWidth > constraints.maxWidth;
        final overflowsHeight =
            constraints.hasBoundedHeight && gridHeight > constraints.maxHeight;
        if (!overflowsWidth && !overflowsHeight) return grid;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: gridWidth,
            child: SingleChildScrollView(child: grid),
          ),
        );
      },
    );
  }

  _GridLayout _resolveLayout() {
    final occupants = List<_SlotItem?>.filled(slotCount, null);
    final items = <_SlotItem>[];
    final overflow = <ButtonConfig>[];

    for (final role in roles) {
      final config = layoutCfg.buttonFor(role);
      if (config == null || !config.visible) continue;
      if (isRedundantCrossTravelConfig(config, layoutCfg.resolvedButtons)) {
        continue;
      }

      final preferred =
          config.slotIndex ?? ButtonConfig.defaultSlotIndexFor(role);
      final normalized = preferred == null
          ? null
          : normalizeGridAnchorSlot(
              config,
              preferred,
              slotCount: slotCount,
              columns: columns,
            );
      final occupied = normalized == null
          ? null
          : occupiedGridSlotsFor(
              config,
              slotIndex: normalized,
              slotCount: slotCount,
              columns: columns,
            );
      if (preferred != null &&
          normalized != null &&
          occupied != null &&
          occupied.every((slot) => occupants[slot] == null)) {
        final item = _SlotItem(
          config: config,
          visualSlot: normalized,
          colSpan: config.gridColumnSpan,
          rowSpan: config.gridRowSpan,
          occupiedSlots: occupied,
        );
        items.add(item);
        for (final slot in occupied) {
          occupants[slot] = item;
        }
      } else {
        overflow.add(config);
      }
    }

    for (final config in overflow) {
      for (var slot = 0; slot < slotCount; slot++) {
        final normalized = normalizeGridAnchorSlot(
          config,
          slot,
          slotCount: slotCount,
          columns: columns,
        );
        final occupied = occupiedGridSlotsFor(
          config,
          slotIndex: normalized,
          slotCount: slotCount,
          columns: columns,
        );
        if (occupied == null ||
            !occupied.every((cell) => occupants[cell] == null)) {
          continue;
        }
        final item = _SlotItem(
          config: config,
          visualSlot: normalized,
          colSpan: config.gridColumnSpan,
          rowSpan: config.gridRowSpan,
          occupiedSlots: occupied,
        );
        items.add(item);
        for (final cell in occupied) {
          occupants[cell] = item;
        }
        break;
      }
    }

    return _GridLayout(items: items, occupants: occupants);
  }
}

class _SlotGridBody extends StatelessWidget {
  const _SlotGridBody({
    required this.layout,
    required this.rows,
    required this.slotCount,
    required this.spacing,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    required this.onEditButton,
    required this.selectedRole,
    required this.onSelectButton,
    required this.onSlotDrop,
  });

  final _GridLayout layout;
  final int rows;
  final int slotCount;
  final double spacing;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
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
                if (layout.occupants[slot] == null)
                  Positioned.fromRect(
                    rect: rectFor(slot, 1, 1),
                    child: _SlotTarget(
                      key: ValueKey('control_slot_$slot'),
                      slotIndex: slot,
                      item: null,
                      isEditing: true,
                      activeStateFor: activeStateFor,
                      isDisabled: isDisabled,
                      onCommand: onCommand,
                      onEditButton: onEditButton,
                      selectedRole: selectedRole,
                      onSelectButton: onSelectButton,
                      onSlotDrop: onSlotDrop,
                    ),
                  ),
            for (final item in layout.items)
              Positioned.fromRect(
                rect: rectFor(item.visualSlot, item.colSpan, item.rowSpan),
                child: _SlotTarget(
                  key: ValueKey('control_slot_${item.visualSlot}'),
                  slotIndex: item.visualSlot,
                  item: item,
                  isEditing: isEditing,
                  activeStateFor: activeStateFor,
                  isDisabled: isDisabled,
                  onCommand: onCommand,
                  onEditButton: onEditButton,
                  selectedRole: selectedRole,
                  onSelectButton: onSelectButton,
                  onSlotDrop: onSlotDrop,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GridLayout {
  const _GridLayout({required this.items, required this.occupants});

  final List<_SlotItem> items;
  final List<_SlotItem?> occupants;
}

class _SlotItem {
  const _SlotItem({
    required this.config,
    required this.visualSlot,
    required this.colSpan,
    required this.rowSpan,
    required this.occupiedSlots,
  });

  final ButtonConfig config;
  final int visualSlot;
  final int colSpan;
  final int rowSpan;
  final List<int> occupiedSlots;
}

class _DraggedSlot {
  const _DraggedSlot({required this.config, required this.sourceSlot});

  final ButtonConfig config;
  final int sourceSlot;
}

class _SlotTarget extends StatefulWidget {
  const _SlotTarget({
    super.key,
    required this.slotIndex,
    required this.item,
    required this.isEditing,
    required this.activeStateFor,
    required this.isDisabled,
    required this.onCommand,
    required this.onEditButton,
    required this.selectedRole,
    required this.onSelectButton,
    required this.onSlotDrop,
  });

  final int slotIndex;
  final _SlotItem? item;
  final bool isEditing;
  final ButtonActiveStateResolver activeStateFor;
  final ButtonDisabledResolver isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
  final ControlRole? selectedRole;
  final ButtonSelectionHandler? onSelectButton;
  final ButtonSlotDropHandler? onSlotDrop;

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
        );
      },
      builder: (context, candidates, rejects) {
        final highlighted = _hovered || candidates.isNotEmpty;
        final selected =
            widget.item?.config.role != null &&
            widget.item!.config.role == widget.selectedRole;
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      padding: EdgeInsets.all(isEditing ? 5 : 0),
      decoration: BoxDecoration(
        color: isEditing ? AppColors.panel.withAlpha(120) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isEditing
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
    required this.isSelected,
    required this.onSelectButton,
  });

  final _SlotItem item;
  final ControlState activeState;
  final bool isDisabled;
  final ButtonCommandDispatcher onCommand;
  final ButtonEditorLauncher onEditButton;
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
              color: AppColors.accent,
              onTap: () => onEditButton(item.config),
              tooltip: 'Customize',
            ),
          ),
          const Positioned(left: 8, top: 8, child: _DragHandle()),
        ],
      ),
    );

    return LongPressDraggable<_DraggedSlot>(
      key: ValueKey(item.config.id),
      data: _DraggedSlot(config: item.config, sourceSlot: item.visualSlot),
      onDragStarted: () => onSelectButton?.call(item.config),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 168.0 * item.colSpan + 10.0 * (item.colSpan - 1),
          height: 136,
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
      message: 'Drag to swap slots',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.panel.withAlpha(235),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.drag_indicator_rounded,
            size: 16,
            color: AppColors.darkText,
          ),
        ),
      ),
    );
  }
}
