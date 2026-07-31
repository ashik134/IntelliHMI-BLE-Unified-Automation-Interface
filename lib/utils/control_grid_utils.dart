import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/multi_zone_slider_strategy.dart';

const String kCrossTravelSpanMessage =
    '5-Zone slider requires two adjacent cells. Clear or replace the neighboring control first.';

const String kWidgetPlacementMessage =
    'That widget cannot fit there without overlapping another control.';

/// Synthetic selection id for a vacant slot — never a real [ButtonConfig.id],
/// so `CustomizationModeController.selectedButton` correctly resolves to
/// null for it (there's no button yet) while `selectedSlotId` still lets
/// the grid draw the same highlight styling used for a selected occupied
/// slot.
String vacantSlotSelectionId(int pageIndex, int slotIndex) =>
    '__vacant_${pageIndex}_$slotIndex';

// ─────────────────────────────────────────────────────────────────────────────
// ResolvedButtonCommand
//
// The single place a control screen's onCommand(buttonId, state) handler
// resolves the LOGICAL state id and its EXACT set of user-configured PLC
// output variants, for any id CraneController.setButtonCommand can be
// called with — a real ButtonConfig id, a traverse fast-assist virtual key,
// or a joystick virtual per-direction sub-button id. This is a pure lookup:
// it never adds a variant beyond what was explicitly configured for that
// exact (buttonId, stateId) pair. See CraneController.setButtonCommand's
// doc comment for the master invariant this preserves.
// ─────────────────────────────────────────────────────────────────────────────

class ResolvedButtonCommand {
  const ResolvedButtonCommand({
    required this.stateId,
    required this.activeVariants,
  });

  final String stateId;
  final Set<PlcOutputVariant> activeVariants;
}

/// Resolves [buttonId]'s logical stateId + exact active PLC output variants
/// for the given physical gesture [state], consulting [layoutCfg] for real
/// buttons and the fixed virtual-id tables for traverse fast-assist keys /
/// joystick sub-buttons. Returns idle/`{}` for any id this function cannot
/// resolve (e.g. a stale id from a just-deleted button) — never guesses.
ResolvedButtonCommand resolveButtonCommand({
  required String buttonId,
  required ControlState state,
  required ControlLayoutConfig layoutCfg,
}) {
  // Traverse fast-assist virtual keys: fixed 2-state (idle/active) table,
  // migrated once, never re-derived.
  final virtualStates = kVirtualFastKeyStateMappings[buttonId];
  if (virtualStates != null) {
    final stateId = state == ControlState.idle
        ? 'idle'
        : kVirtualFastKeyActiveState;
    return ResolvedButtonCommand(
      stateId: stateId,
      activeVariants: virtualStates[stateId]?.activeVariants ?? const {},
    );
  }

  // Joystick virtual per-direction sub-buttons: table lives on the PARENT
  // ButtonConfig (joystickSubButtonMappings), keyed by this sub-button id.
  if (joystickVirtualFieldFor(buttonId) != null) {
    final parts = buttonId.split(':');
    final sourceButtonId = parts.length == 3 ? parts[1] : null;
    final parent = sourceButtonId == null
        ? null
        : layoutCfg.resolvedButtons[sourceButtonId];
    final subStates = parent?.joystickSubButtonMappings[buttonId];
    final stateId = logicalStateIdFor(
      type: ButtonType.joystick,
      physicalState: state,
    );
    // Compatibility for layouts edited while the UI incorrectly wrote
    // joystick output rows to the parent ButtonConfig.stateMappings. As soon
    // as any per-direction joystickSubButtonMappings exist, the exact virtual
    // direction table wins and this fallback is ignored.
    final hasOnlyParentMappings =
        parent?.joystickSubButtonMappings.isEmpty ?? false;
    final fallbackStates = hasOnlyParentMappings ? parent?.stateMappings : null;
    final states = subStates ?? fallbackStates;
    return ResolvedButtonCommand(
      stateId: stateId,
      activeVariants: states?[stateId]?.activeVariants ?? const {},
    );
  }

  // Real ButtonConfig.
  final config = layoutCfg.resolvedButtons[buttonId];
  if (config == null) {
    return const ResolvedButtonCommand(stateId: 'idle', activeVariants: {});
  }
  if (config.type == ButtonType.potentiometer ||
      config.type == ButtonType.analogJoystick1D ||
      config.type == ButtonType.analogJoystick2D ||
      config.type == ButtonType.analogSliderOT ||
      config.type == ButtonType.analogSliderTOT) {
    return const ResolvedButtonCommand(stateId: 'analog', activeVariants: {});
  }
  if (config.type == ButtonType.horn ||
      config.type == ButtonType.alarmIndicator) {
    // Both are PLC status-driven FEEDBACK widgets (see HornButtonStrategy/
    // AlarmIndicatorStrategy) — neither ever calls onCommand, so this branch
    // only guards against a stray/legacy call reaching here; always inert.
    return const ResolvedButtonCommand(stateId: 'idle', activeVariants: {});
  }

  final String stateId;
  if (config.type == ButtonType.bidirectionalSlider5Step ||
      config.type == ButtonType.bidirectionalSlider3Step) {
    final endpoints = config.type == ButtonType.bidirectionalSlider5Step
        ? const Bidirectional5StepStrategy().traverseEndpointsFor(config)
        : const Bidirectional3StepStrategy().traverseEndpointsFor(config);
    final isLeftButton = buttonId == endpoints.leftId;
    stateId = crossTravelZoneId(
      isLeftButton: isLeftButton,
      state: state,
      fiveZone: config.type == ButtonType.bidirectionalSlider5Step,
    );
  } else {
    stateId = logicalStateIdFor(type: config.type, physicalState: state);
  }

  return ResolvedButtonCommand(
    stateId: stateId,
    activeVariants: config.stateMappings[stateId]?.activeVariants ?? const {},
  );
}

/// The PLC output variants a user may select in the OUTPUT MAPPING editor
/// for a layout belonging to [bucket]. PLC38 exposes the full DF2..DF10 range
/// (DF1/E-STOP is excluded at the call site, never included here). PLC14/
/// PLC21 only ever emit the first four digital fields (DF1..DF4), so
/// restricting selection here means a user can never configure a variant
/// that would be silently dropped at wire-serialization time, on top of the
/// wire-level truncation that already makes such a config harmless even if
/// one existed (e.g. from a hand-edited/imported layout — see
/// plc14_variant_clamping_test.dart).
List<PlcOutputVariant> selectableVariantsFor(LayoutBucket bucket) {
  final all = PlcOutputVariant.values.where((m) => m.isUserConfigurable);
  if (bucket == LayoutBucket.plc38) return all.toList();
  return all
      .where(
        (m) =>
            m == PlcOutputVariant.df2 ||
            m == PlcOutputVariant.df3 ||
            m == PlcOutputVariant.df4,
      )
      .toList();
}

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
    if (source.role != null) continue;
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

/// Drops control pages that hold no visible page-control button, shifting
/// later pages down so page indices stay contiguous. Page 0 is always kept
/// (it's the base grid every screen renders), even if empty. Returns the
/// same [layout] instance if nothing changed.
///
/// Called after drag-off and resize mutations that can empty a page, so a
/// Customization Mode session never leaves a blank page behind for the
/// operator to page into. Delete intentionally does not use this helper,
/// because deleting a control leaves its slot/page position vacant.
ControlLayoutConfig compactControlPages(
  ControlLayoutConfig layout, {
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final buttons = layout.resolvedButtons;
  final occupiedPages = <int>{};
  for (final rawButton in buttons.values) {
    if (!_isPageControl(rawButton)) continue;
    if (isRedundantCrossTravelConfig(rawButton, buttons)) continue;
    final normalized = normalizeButtonPlacement(
      rawButton,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    occupiedPages.add(normalized.pageIndex);
  }

  final highestOccupied = occupiedPages.fold<int>(
    0,
    (max, page) => page > max ? page : max,
  );
  final keptPages = [
    0,
    for (var page = 1; page <= highestOccupied; page++)
      if (occupiedPages.contains(page)) page,
  ];
  final nextPageCount = keptPages.length;
  if (nextPageCount == layout.controlPageCount &&
      keptPages.every((page) => keptPages.indexOf(page) == page)) {
    return layout;
  }

  final remap = <int, int>{
    for (var i = 0; i < keptPages.length; i++) keptPages[i]: i,
  };
  final nextButtons = <String, ButtonConfig>{};
  var changed = false;
  for (final entry in buttons.entries) {
    final button = entry.value;
    final mappedPage = remap[button.pageIndex];
    if (mappedPage == null || mappedPage == button.pageIndex) {
      nextButtons[entry.key] = button;
      continue;
    }
    nextButtons[entry.key] = button.copyWith(pageIndex: mappedPage);
    changed = true;
  }

  if (!changed && nextPageCount == layout.controlPageCount) return layout;
  return layout.copyWith(buttons: nextButtons, controlPageCount: nextPageCount);
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
  if (button.type != ButtonType.bidirectionalSlider5Step ||
      button.role != ControlRole.traverseRight) {
    return false;
  }
  final left = buttons[ControlRole.traverseLeft.name];
  return left != null &&
      left.visible &&
      left.type == ButtonType.bidirectionalSlider5Step;
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
  int? anchorX,
  int? anchorY,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  int nextColumns;
  int nextRows;
  if (selected.type == ButtonType.bidirectionalSlider5Step) {
    // The 5-zone slider only ever occupies exactly two cells, in one of two
    // fixed shapes — 2x1 (horizontal) or 1x2 (vertical) — never 1x1 (too
    // small to show 5 zones) and never a larger span. Orientation is chosen
    // from the requested shape's own aspect (taller-than-wide -> vertical),
    // matching how a user drags the resize handle.
    final wantsVertical = gridRows > gridColumns;
    nextColumns = wantsVertical ? 1 : 2;
    nextRows = wantsVertical ? 2 : 1;
  } else {
    final minSize = ButtonConfig.defaultGridSizeFor(
      selected.type,
      customProperties: selected.customProperties,
    );
    nextColumns = gridColumns.clamp(minSize.$1, columns);
    nextRows = gridRows.clamp(minSize.$2, rows);
  }
  final maxX = (columns - nextColumns).clamp(0, columns - 1);
  final maxY = (rows - nextRows).clamp(0, rows - 1);
  final nextX = (anchorX ?? selected.gridX).clamp(0, maxX);
  final nextY = (anchorY ?? selected.gridY).clamp(0, maxY);
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
  int? preferredSlot,
  int slotCount = ButtonConfig.controlSlotCount,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  if (buttons.containsKey(button.id)) {
    return const GridMutationResult.invalid('A button with that id exists.');
  }
  final occupied = _occupiedExcept(buttons, const {}, columns, rows, slotCount);

  ButtonConfig? placed;
  if (preferredSlot != null) {
    final anchor = normalizeGridAnchorSlot(
      button,
      preferredSlot,
      slotCount: slotCount,
      columns: columns,
    );
    final candidate = normalizeButtonPlacement(
      button.copyWith(
        pageIndex: preferredPageIndex,
        gridX: anchor % columns,
        gridY: anchor ~/ columns,
        slotIndex: anchor,
      ),
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (_isPlacementFree(
      candidate,
      occupied,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    )) {
      placed = candidate;
    }
  }
  placed ??= _findFirstPlacement(
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

  final deletedIds = _buttonIdsForDelete(selected, buttons);
  final next = <String, ButtonConfig>{};
  for (final entry in buttons.entries) {
    if (deletedIds.contains(entry.key) || deletedIds.contains(entry.value.id)) {
      continue;
    }
    next[entry.key] = _withoutButtonReferences(entry.value, deletedIds);
  }
  return GridMutationResult.valid(next);
}

Set<String> _buttonIdsForDelete(
  ButtonConfig selected,
  Map<String, ButtonConfig> buttons,
) {
  final ids = <String>{selected.id};
  final role = selected.role;
  final pairedRole = role?.pairedRole;
  final paired = pairedRole == null ? null : buttons[pairedRole.name];
  if (selected.type == ButtonType.bidirectionalSlider5Step &&
      role?.axis == AxisKind.traverse &&
      paired?.type == ButtonType.bidirectionalSlider5Step) {
    ids.add(paired!.id);
  }
  return ids;
}

ButtonConfig _withoutButtonReferences(
  ButtonConfig button,
  Set<String> deletedIds,
) {
  final mutualExclusion = button.mutualExclusion;
  final excluded = mutualExclusion.excludedButtonIds.difference(deletedIds);
  final included = mutualExclusion.inclusiveButtonIds.difference(deletedIds);
  if (excluded.length == mutualExclusion.excludedButtonIds.length &&
      included.length == mutualExclusion.inclusiveButtonIds.length) {
    return button;
  }
  return button.copyWith(
    mutualExclusion: mutualExclusion.copyWith(
      excludedButtonIds: excluded,
      inclusiveButtonIds: included,
    ),
  );
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

  if (type == ButtonType.bidirectionalSlider5Step) {
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
      {current.id, paired?.id},
      columns,
      rows,
      slotCount,
    );
    if (!_isPlacementFree(
      candidate,
      occupied,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    )) {
      return const LayoutMutationResult.invalid(kCrossTravelSpanMessage);
    }
    buttons[current.id] = candidate;
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

    if (current.type == ButtonType.bidirectionalSlider5Step &&
        type == ButtonType.bidirectionalSlider3Step &&
        role.axis == AxisKind.traverse &&
        paired != null) {
      buttons[paired.id] = paired.copyWith(visible: false);
    } else if (current.type == ButtonType.bidirectionalSlider5Step &&
        role.axis == AxisKind.traverse &&
        paired != null) {
      buttons[paired.id] = paired.copyWith(
        visible: true,
        type: paired.type == ButtonType.bidirectionalSlider5Step
            ? type
            : paired.type,
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
  if (changed.type == ButtonType.bidirectionalSlider5Step ||
      changed.occupiesMultipleGridCells) {
    return kCrossTravelSpanMessage;
  }
  return errors.isEmpty ? kWidgetPlacementMessage : errors.first;
}
