import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

const String kCrossTravelSpanMessage =
    '5-Zone Cross Travel requires two adjacent cells. Clear or replace the neighboring control first.';

class GridMutationResult {
  const GridMutationResult.valid(this.buttons) : isValid = true, message = null;

  const GridMutationResult.invalid(this.message)
    : isValid = false,
      buttons = null;

  final bool isValid;
  final Map<String, ButtonConfig>? buttons;
  final String? message;
}

class LayoutMutationResult {
  const LayoutMutationResult.valid(this.layout)
    : isValid = true,
      message = null;

  const LayoutMutationResult.invalid(this.message)
    : isValid = false,
      layout = null;

  final bool isValid;
  final ControlLayoutConfig? layout;
  final String? message;
}

int normalizeGridAnchorSlot(
  ButtonConfig config,
  int slotIndex, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
}) {
  final span = config.gridColumnSpan;
  if (span <= 1 || columns <= 0) return slotIndex;
  final maxStartColumn = columns - span;
  if (maxStartColumn < 0) return slotIndex;
  final row = slotIndex ~/ columns;
  final col = slotIndex % columns;
  final startCol = col.clamp(0, maxStartColumn);
  final anchor = row * columns + startCol;
  return anchor.clamp(ButtonConfig.minSlotIndex, slotCount - 1);
}

List<int>? occupiedGridSlotsFor(
  ButtonConfig config, {
  int? slotIndex,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
}) {
  final rawSlot = slotIndex ?? config.slotIndex;
  if (rawSlot == null || rawSlot < 0 || rawSlot >= slotCount) return null;
  if (columns <= 0) return null;

  final anchor = normalizeGridAnchorSlot(
    config,
    rawSlot,
    slotCount: slotCount,
    columns: columns,
  );
  final colSpan = config.gridColumnSpan;
  final rowSpan = config.gridRowSpan;
  final rows = (slotCount / columns).ceil();
  final row = anchor ~/ columns;
  final col = anchor % columns;
  if (col + colSpan > columns || row + rowSpan > rows) return null;

  final slots = <int>[];
  for (var r = 0; r < rowSpan; r++) {
    for (var c = 0; c < colSpan; c++) {
      final slot = (row + r) * columns + col + c;
      if (slot < 0 || slot >= slotCount) return null;
      slots.add(slot);
    }
  }
  return slots;
}

List<String> validateGridOccupancy(
  Map<String, ButtonConfig> buttons, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
}) {
  final errors = <String>[];
  final occupied = <int, ButtonConfig>{};

  for (final button in buttons.values) {
    final role = button.role;
    if (role == null || !role.isMotionControl || !button.visible) continue;
    if (isRedundantCrossTravelConfig(button, buttons)) continue;

    final name = button.label.isEmpty ? button.id : button.label;
    final slots = occupiedGridSlotsFor(
      button,
      slotCount: slotCount,
      columns: columns,
    );
    if (slots == null) {
      errors.add(
        '$name requires ${button.gridColumnSpan} x ${button.gridRowSpan} grid cells and does not fit from its current slot.',
      );
      continue;
    }

    for (final slot in slots) {
      final existing = occupied[slot];
      if (existing != null && existing.id != button.id) {
        final existingName = existing.label.isEmpty
            ? existing.id
            : existing.label;
        errors.add('$name and $existingName both occupy slot ${slot + 1}.');
      } else {
        occupied[slot] = button;
      }
    }
  }

  return errors;
}

bool isRedundantCrossTravelConfig(
  ButtonConfig button,
  Map<String, ButtonConfig> buttons,
) {
  if (button.type != ButtonType.crossTravel ||
      button.role != ControlRole.traverseRight) {
    return false;
  }
  final left = buttons[ControlRole.traverseLeft.name];
  return left != null && left.visible && left.type == ButtonType.crossTravel;
}

GridMutationResult buildGridSlotDrop({
  required Map<String, ButtonConfig> buttons,
  required ButtonConfig dragged,
  required int sourceSlot,
  required ButtonConfig? target,
  required int targetSlot,
  int slotCount = ButtonConfig.controlSlotCount,
}) {
  final next = {...buttons};
  final nextDraggedSlot = normalizeGridAnchorSlot(
    dragged,
    targetSlot,
    slotCount: slotCount,
  );
  next[dragged.id] = dragged.copyWith(slotIndex: nextDraggedSlot);

  if (target != null && target.id != dragged.id) {
    final nextTargetSlot = normalizeGridAnchorSlot(
      target,
      sourceSlot,
      slotCount: slotCount,
    );
    next[target.id] = target.copyWith(slotIndex: nextTargetSlot);
  }

  final errors = validateGridOccupancy(next, slotCount: slotCount);
  if (errors.isNotEmpty) {
    return GridMutationResult.invalid(_messageForErrors(errors, dragged));
  }
  return GridMutationResult.valid(next);
}

LayoutMutationResult buildButtonTypeChange({
  required ControlLayoutConfig draft,
  required ControlRole role,
  required ButtonType type,
  int slotCount = ButtonConfig.controlSlotCount,
}) {
  final current = draft.buttonFor(role);
  if (current == null) {
    return const LayoutMutationResult.invalid('Control is not available.');
  }

  final buttons = {...draft.resolvedButtons};
  final pairedRole = role.pairedRole;
  final paired = pairedRole == null ? null : buttons[pairedRole.name];

  if (type == ButtonType.crossTravel) {
    final baseSlot =
        current.slotIndex ?? ButtonConfig.defaultSlotIndexFor(role) ?? 0;
    final candidate = current.copyWith(
      type: type,
      visible: true,
      slotIndex: normalizeGridAnchorSlot(
        current.copyWith(type: type),
        baseSlot,
        slotCount: slotCount,
      ),
    );
    final occupied = occupiedGridSlotsFor(
      candidate,
      slotCount: slotCount,
    )?.toSet();
    if (occupied == null) {
      return const LayoutMutationResult.invalid(kCrossTravelSpanMessage);
    }

    for (final other in buttons.values) {
      if (other.id == current.id || !other.visible) continue;
      final otherSlots = occupiedGridSlotsFor(other, slotCount: slotCount);
      final collides =
          otherSlots != null &&
          otherSlots.any((slot) => occupied.contains(slot));
      if (!collides) continue;

      final compatiblePair =
          role.axis == AxisKind.traverse && other.role == pairedRole;
      if (!compatiblePair) {
        return const LayoutMutationResult.invalid(kCrossTravelSpanMessage);
      }
    }

    buttons[current.id] = candidate;
    if (role.axis == AxisKind.traverse && paired != null) {
      buttons[paired.id] = paired.copyWith(visible: false);
    }
  } else {
    var nextCurrent = current.copyWith(type: type, visible: true);
    if (current.type == ButtonType.crossTravel &&
        role.axis == AxisKind.traverse) {
      final anchor = normalizeGridAnchorSlot(
        current,
        current.slotIndex ?? ButtonConfig.defaultSlotIndexFor(role) ?? 0,
        slotCount: slotCount,
      );
      final roleSlot = role == ControlRole.traverseRight ? anchor + 1 : anchor;
      nextCurrent = nextCurrent.copyWith(slotIndex: roleSlot);
      if (paired != null) {
        final pairedSlot = role == ControlRole.traverseRight
            ? anchor
            : anchor + 1;
        buttons[paired.id] = paired.copyWith(
          visible: true,
          slotIndex: pairedSlot,
        );
      }
    }
    buttons[current.id] = nextCurrent;
  }

  final errors = validateGridOccupancy(buttons, slotCount: slotCount);
  if (errors.isNotEmpty) {
    return LayoutMutationResult.invalid(_messageForErrors(errors, current));
  }
  return LayoutMutationResult.valid(draft.copyWith(buttons: buttons));
}

String _messageForErrors(List<String> errors, ButtonConfig changed) {
  if (changed.type == ButtonType.crossTravel ||
      changed.occupiesMultipleGridCells) {
    return kCrossTravelSpanMessage;
  }
  return errors.first;
}
