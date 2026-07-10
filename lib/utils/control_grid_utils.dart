import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

const String kCrossTravelSpanMessage =
    '5-Zone Cross Travel requires two adjacent cells. Clear or replace the neighboring control first.';

const String kWidgetPlacementMessage =
    'That widget cannot fit there without overlapping another control.';

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

class ControlGridItem {
  const ControlGridItem({
    required this.config,
    required this.pageIndex,
    required this.visualSlot,
    required this.gridX,
    required this.gridY,
    required this.colSpan,
    required this.rowSpan,
    required this.occupiedSlots,
  });

  final ButtonConfig config;
  final int pageIndex;
  final int visualSlot;
  final int gridX;
  final int gridY;
  final int colSpan;
  final int rowSpan;
  final List<int> occupiedSlots;
}

class ControlGridPage {
  ControlGridPage({
    required this.pageIndex,
    required this.items,
    required this.occupants,
  });

  final int pageIndex;
  final List<ControlGridItem> items;
  final List<ControlGridItem?> occupants;
}

int normalizeGridAnchorSlot(
  ButtonConfig config,
  int slotIndex, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
}) {
  final span = config.gridColumnSpan;
  if (span <= 1 || columns <= 0) return slotIndex.clamp(0, slotCount - 1);
  final maxStartColumn = columns - span;
  if (maxStartColumn < 0) return slotIndex.clamp(0, slotCount - 1);
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
  int rows = ButtonConfig.controlGridRows,
}) {
  if (columns <= 0 || rows <= 0) return null;
  final rawSlot =
      slotIndex ??
      config.slotIndex ??
      _slotFor(config.gridX, config.gridY, columns);
  if (rawSlot < 0 || rawSlot >= slotCount) return null;

  final anchor = normalizeGridAnchorSlot(
    config,
    rawSlot,
    slotCount: slotCount,
    columns: columns,
  );
  final colSpan = config.gridColumnSpan.clamp(1, columns);
  final rowSpan = config.gridRowSpan.clamp(1, rows);
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
  int rows = ButtonConfig.controlGridRows,
}) {
  final errors = <String>[];
  final occupied = <String, ButtonConfig>{};

  for (final rawButton in buttons.values) {
    final button = normalizeButtonPlacement(
      rawButton,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (!_isPageControl(button)) continue;
    if (isRedundantCrossTravelConfig(button, buttons)) continue;

    final name = button.label.isEmpty ? button.id : button.label;
    if (button.pageIndex < 0) {
      errors.add('$name page index must be zero or greater.');
      continue;
    }

    final slots = occupiedGridSlotsFor(
      button,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (slots == null) {
      errors.add(
        '$name requires ${button.gridColumnSpan} x ${button.gridRowSpan} grid cells and does not fit on page ${button.pageIndex + 1}.',
      );
      continue;
    }

    for (final slot in slots) {
      final key = '${button.pageIndex}:$slot';
      final existing = occupied[key];
      if (existing != null && existing.id != button.id) {
        final existingName = existing.label.isEmpty
            ? existing.id
            : existing.label;
        errors.add(
          '$name and $existingName both occupy page ${button.pageIndex + 1}, slot ${slot + 1}.',
        );
      } else {
        occupied[key] = button;
      }
    }
  }

  return errors;
}

List<ControlGridPage> buildControlGridPages({
  required ControlLayoutConfig layoutCfg,
  required List<ControlRole> roles,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final pagesByIndex = <int, List<ControlGridItem>>{};
  final renderedIds = <String>{};

  for (final role in roles) {
    final source = layoutCfg.buttonFor(role);
    if (source == null || !source.visible) continue;
    if (isRedundantCrossTravelConfig(source, layoutCfg.resolvedButtons)) {
      continue;
    }
    renderedIds.add(source.id);

    _addPageItem(
      source,
      pagesByIndex: pagesByIndex,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
  }

  for (final source in layoutCfg.resolvedButtons.values) {
    if (renderedIds.contains(source.id) || !_isPageControl(source)) continue;
    if (isRedundantCrossTravelConfig(source, layoutCfg.resolvedButtons)) {
      continue;
    }
    _addPageItem(
      source,
      pagesByIndex: pagesByIndex,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
  }

  final maxPage = pagesByIndex.keys.fold<int>(
    layoutCfg.controlPageCount - 1,
    (max, page) => page > max ? page : max,
  );
  return [
    for (var pageIndex = 0; pageIndex <= maxPage; pageIndex++)
      _buildPage(
        pageIndex: pageIndex,
        items: pagesByIndex[pageIndex] ?? const <ControlGridItem>[],
        slotCount: slotCount,
      ),
  ];
}

void _addPageItem(
  ButtonConfig source, {
  required Map<int, List<ControlGridItem>> pagesByIndex,
  required int slotCount,
  required int columns,
  required int rows,
}) {
  final normalized = normalizeButtonPlacement(
    source,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  final occupied = occupiedGridSlotsFor(
    normalized,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  if (occupied == null) return;

  final item = ControlGridItem(
    config: normalized,
    pageIndex: normalized.pageIndex,
    visualSlot: _slotFor(normalized.gridX, normalized.gridY, columns),
    gridX: normalized.gridX,
    gridY: normalized.gridY,
    colSpan: normalized.gridColumnSpan.clamp(1, columns),
    rowSpan: normalized.gridRowSpan.clamp(1, rows),
    occupiedSlots: occupied,
  );
  pagesByIndex.putIfAbsent(item.pageIndex, () => []).add(item);
}

ButtonConfig normalizeButtonPlacement(
  ButtonConfig config, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final pageIndex = config.pageIndex < 0 ? 0 : config.pageIndex;
  final colSpan = config.gridColumnSpan.clamp(1, columns);
  final rowSpan = config.gridRowSpan.clamp(1, rows);
  final maxX = (columns - colSpan).clamp(0, columns - 1);
  final maxY = (rows - rowSpan).clamp(0, rows - 1);
  final sourceSlot = config.slotIndex;
  final legacyX = sourceSlot == null ? config.gridX : sourceSlot % columns;
  final legacyY = sourceSlot == null ? config.gridY : sourceSlot ~/ columns;
  final x = legacyX.clamp(0, maxX);
  final y = legacyY.clamp(0, maxY);
  final slot = normalizeGridAnchorSlot(
    config,
    _slotFor(x, y, columns),
    slotCount: slotCount,
    columns: columns,
  );
  return config.copyWith(
    pageIndex: pageIndex,
    gridX: slot % columns,
    gridY: slot ~/ columns,
    gridColumns: colSpan,
    gridRows: rowSpan,
    slotIndex: slot,
  );
}

ControlLayoutConfig repairControlGridLayout(
  ControlLayoutConfig layout, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final buttons = layout.resolvedButtons;
  final next = <String, ButtonConfig>{...buttons};
  final occupied = <String, ButtonConfig>{};
  final placeable =
      buttons.values.where((button) {
        return _isPageControl(button) &&
            !isRedundantCrossTravelConfig(button, buttons);
      }).toList()..sort((a, b) {
        final pageCompare = a.pageIndex.compareTo(b.pageIndex);
        if (pageCompare != 0) return pageCompare;
        final rowCompare = a.gridY.compareTo(b.gridY);
        if (rowCompare != 0) return rowCompare;
        final colCompare = a.gridX.compareTo(b.gridX);
        if (colCompare != 0) return colCompare;
        return a.id.compareTo(b.id);
      });

  for (final button in placeable) {
    final normalized = normalizeButtonPlacement(
      button,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    final placed =
        _isPlacementFree(
          normalized,
          occupied,
          columns: columns,
          rows: rows,
          slotCount: slotCount,
        )
        ? normalized
        : _findFirstPlacement(
            normalized,
            occupied: occupied,
            columns: columns,
            rows: rows,
            slotCount: slotCount,
            startPage: normalized.pageIndex,
          );
    next[button.id] = placed;
    _markOccupied(
      occupied,
      placed,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    );
  }
  return layout.copyWith(buttons: next);
}

Map<String, ButtonConfig> autoArrangeButtons(
  Map<String, ButtonConfig> buttons, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final next = <String, ButtonConfig>{...buttons};
  final placeable =
      buttons.values.where((button) {
        return _isPageControl(button) &&
            !isRedundantCrossTravelConfig(button, buttons);
      }).toList()..sort((a, b) {
        final areaCompare = (b.gridColumnSpan * b.gridRowSpan).compareTo(
          a.gridColumnSpan * a.gridRowSpan,
        );
        if (areaCompare != 0) return areaCompare;
        return a.id.compareTo(b.id);
      });

  final occupied = <String, ButtonConfig>{};
  for (final button in placeable) {
    final placed = _findFirstPlacement(
      button,
      occupied: occupied,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
      startPage: 0,
    );
    next[button.id] = placed;
    _markOccupied(
      occupied,
      placed,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    );
  }
  return next;
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
  int? targetPageIndex,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final next = {...buttons};
  final pageIndex = targetPageIndex ?? target?.pageIndex ?? dragged.pageIndex;
  final normalizedSlot = normalizeGridAnchorSlot(
    dragged,
    targetSlot,
    slotCount: slotCount,
    columns: columns,
  );
  next[dragged.id] = dragged.copyWith(
    pageIndex: pageIndex,
    gridX: normalizedSlot % columns,
    gridY: normalizedSlot ~/ columns,
    slotIndex: normalizedSlot,
  );

  if (target != null && target.id != dragged.id) {
    final sourcePageIndex = dragged.pageIndex;
    final sourceNormalizedSlot = normalizeGridAnchorSlot(
      target,
      sourceSlot,
      slotCount: slotCount,
      columns: columns,
    );
    next[target.id] = target.copyWith(
      pageIndex: sourcePageIndex,
      gridX: sourceNormalizedSlot % columns,
      gridY: sourceNormalizedSlot ~/ columns,
      slotIndex: sourceNormalizedSlot,
    );
  }

  final errors = validateGridOccupancy(
    next,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  if (errors.isNotEmpty) {
    return GridMutationResult.invalid(_messageForErrors(errors, dragged));
  }
  return GridMutationResult.valid(next);
}

GridMutationResult buildButtonResize({
  required Map<String, ButtonConfig> buttons,
  required ButtonConfig selected,
  required int gridColumns,
  required int gridRows,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final minSize = ButtonConfig.defaultGridSizeFor(
    selected.type,
    customProperties: selected.customProperties,
  );
  final nextColumns = gridColumns.clamp(minSize.$1, columns);
  final nextRows = gridRows.clamp(minSize.$2, rows);
  final maxX = (columns - nextColumns).clamp(0, columns - 1);
  final maxY = (rows - nextRows).clamp(0, rows - 1);
  final nextX = selected.gridX.clamp(0, maxX);
  final nextY = selected.gridY.clamp(0, maxY);
  final resized = selected.copyWith(
    gridX: nextX,
    gridY: nextY,
    gridColumns: nextColumns,
    gridRows: nextRows,
    slotIndex: _slotFor(nextX, nextY, columns),
  );
  final next = {...buttons, selected.id: resized};
  final errors = validateGridOccupancy(
    next,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  if (errors.isNotEmpty) {
    return GridMutationResult.invalid(_messageForErrors(errors, resized));
  }
  return GridMutationResult.valid(next);
}

GridMutationResult buildButtonAdd({
  required Map<String, ButtonConfig> buttons,
  required ButtonConfig button,
  required int preferredPageIndex,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  if (buttons.containsKey(button.id)) {
    return const GridMutationResult.invalid('A button with that id exists.');
  }
  final occupied = _occupiedExcept(buttons, const {}, columns, rows, slotCount);
  final placed = _findFirstPlacement(
    button,
    occupied: occupied,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
    startPage: preferredPageIndex,
  );
  final next = {...buttons, placed.id: placed};
  final errors = validateGridOccupancy(
    next,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  if (errors.isNotEmpty) {
    return GridMutationResult.invalid(_messageForErrors(errors, placed));
  }
  return GridMutationResult.valid(next);
}

GridMutationResult buildButtonDelete({
  required Map<String, ButtonConfig> buttons,
  required ButtonConfig selected,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final role = selected.role;
  if (role != null && !role.isMotionControl) {
    return const GridMutationResult.invalid(
      'Safety controls cannot be deleted from the motion grid.',
    );
  }

  final next = {...buttons};
  next[selected.id] = selected.copyWith(visible: false, columnSpan: 1);
  final arranged = autoArrangeButtons(
    next,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  return GridMutationResult.valid(arranged);
}

LayoutMutationResult buildButtonTypeChange({
  required ControlLayoutConfig draft,
  required ControlRole role,
  required ButtonType type,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final current = draft.buttonFor(role);
  if (current == null) {
    return const LayoutMutationResult.invalid('Control is not available.');
  }

  final buttons = {...draft.resolvedButtons};
  final pairedRole = role.pairedRole;
  final paired = pairedRole == null ? null : buttons[pairedRole.name];
  final (defaultColumns, defaultRows) = ButtonConfig.defaultGridSizeFor(
    type,
    customProperties: current.customProperties,
  );

  if (type == ButtonType.crossTravel) {
    final candidate = current.copyWith(
      type: type,
      visible: true,
      gridColumns: defaultColumns,
      gridRows: defaultRows,
    );
    buttons[current.id] = _findFirstPlacement(
      candidate,
      occupied: _occupiedExcept(
        buttons,
        {current.id, paired?.id},
        columns,
        rows,
        slotCount,
      ),
      columns: columns,
      rows: rows,
      slotCount: slotCount,
      startPage: current.pageIndex,
    );
    if (role.axis == AxisKind.traverse && paired != null) {
      buttons[paired.id] = paired.copyWith(visible: false);
    }
  } else {
    final candidate = normalizeButtonPlacement(
      current.copyWith(
        type: type,
        visible: true,
        gridColumns: defaultColumns,
        gridRows: defaultRows,
      ),
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    final occupied = _occupiedExcept(
      buttons,
      {current.id},
      columns,
      rows,
      slotCount,
    );
    buttons[current.id] =
        _isPlacementFree(
          candidate,
          occupied,
          columns: columns,
          rows: rows,
          slotCount: slotCount,
        )
        ? candidate
        : _findFirstPlacement(
            candidate,
            occupied: occupied,
            columns: columns,
            rows: rows,
            slotCount: slotCount,
            startPage: current.pageIndex,
          );

    if (current.type == ButtonType.crossTravel &&
        type == ButtonType.crossTravelSlowOnly &&
        role.axis == AxisKind.traverse &&
        paired != null) {
      buttons[paired.id] = paired.copyWith(visible: false);
    } else if (current.type == ButtonType.crossTravel &&
        role.axis == AxisKind.traverse &&
        paired != null) {
      buttons[paired.id] = paired.copyWith(
        visible: true,
        type: paired.type == ButtonType.crossTravel ? type : paired.type,
        gridColumns: defaultColumns,
        gridRows: defaultRows,
      );
      final repaired = autoArrangeButtons(
        buttons,
        slotCount: slotCount,
        columns: columns,
        rows: rows,
      );
      buttons
        ..clear()
        ..addAll(repaired);
    }
  }

  final errors = validateGridOccupancy(
    buttons,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  if (errors.isNotEmpty) {
    return LayoutMutationResult.invalid(_messageForErrors(errors, current));
  }
  return LayoutMutationResult.valid(draft.copyWith(buttons: buttons));
}

ControlGridPage _buildPage({
  required int pageIndex,
  required List<ControlGridItem> items,
  required int slotCount,
}) {
  final occupants = List<ControlGridItem?>.filled(slotCount, null);
  for (final item in items) {
    for (final slot in item.occupiedSlots) {
      if (slot >= 0 && slot < occupants.length) occupants[slot] = item;
    }
  }
  return ControlGridPage(
    pageIndex: pageIndex,
    items: items,
    occupants: occupants,
  );
}

ButtonConfig _findFirstPlacement(
  ButtonConfig button, {
  required Map<String, ButtonConfig> occupied,
  required int columns,
  required int rows,
  required int slotCount,
  required int startPage,
}) {
  final normalized = normalizeButtonPlacement(
    button,
    slotCount: slotCount,
    columns: columns,
    rows: rows,
  );
  final colSpan = normalized.gridColumnSpan.clamp(1, columns);
  final rowSpan = normalized.gridRowSpan.clamp(1, rows);

  for (var page = startPage.clamp(0, 999); page < 1000; page++) {
    for (var y = 0; y <= rows - rowSpan; y++) {
      for (var x = 0; x <= columns - colSpan; x++) {
        final candidate = normalized.copyWith(
          pageIndex: page,
          gridX: x,
          gridY: y,
          gridColumns: colSpan,
          gridRows: rowSpan,
          slotIndex: _slotFor(x, y, columns),
        );
        if (_isPlacementFree(
          candidate,
          occupied,
          columns: columns,
          rows: rows,
          slotCount: slotCount,
        )) {
          return candidate;
        }
      }
    }
  }
  return normalized.copyWith(pageIndex: startPage + 1, gridX: 0, gridY: 0);
}

bool _isPlacementFree(
  ButtonConfig button,
  Map<String, ButtonConfig> occupied, {
  required int columns,
  required int rows,
  required int slotCount,
}) {
  final slots = occupiedGridSlotsFor(
    button,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );
  if (slots == null) return false;
  return slots.every(
    (slot) => !occupied.containsKey('${button.pageIndex}:$slot'),
  );
}

void _markOccupied(
  Map<String, ButtonConfig> occupied,
  ButtonConfig button, {
  required int columns,
  required int rows,
  required int slotCount,
}) {
  final slots = occupiedGridSlotsFor(
    button,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );
  if (slots == null) return;
  for (final slot in slots) {
    occupied['${button.pageIndex}:$slot'] = button;
  }
}

Map<String, ButtonConfig> _occupiedExcept(
  Map<String, ButtonConfig> buttons,
  Set<String?> excludedIds,
  int columns,
  int rows,
  int slotCount,
) {
  final occupied = <String, ButtonConfig>{};
  for (final button in buttons.values) {
    if (excludedIds.contains(button.id) ||
        !_isPageControl(button) ||
        isRedundantCrossTravelConfig(button, buttons)) {
      continue;
    }
    _markOccupied(
      occupied,
      button,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    );
  }
  return occupied;
}

int _slotFor(int x, int y, int columns) => y * columns + x;

bool _isPageControl(ButtonConfig button) {
  final role = button.role;
  return button.visible && (role == null || role.isMotionControl);
}

String _messageForErrors(List<String> errors, ButtonConfig changed) {
  if (changed.type == ButtonType.crossTravel ||
      changed.occupiesMultipleGridCells) {
    return kCrossTravelSpanMessage;
  }
  return errors.isEmpty ? kWidgetPlacementMessage : errors.first;
}
