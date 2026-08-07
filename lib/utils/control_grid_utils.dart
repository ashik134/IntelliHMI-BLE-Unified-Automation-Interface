import 'package:flutter/painting.dart' show Rect, Offset;

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/button_type_strategy.dart';

const String kMultiZoneSpanMessage =
    'Multi-zone slider requires adjacent cells for safe travel. Clear a neighboring control or use a larger grid allocation.';

const String kWidgetPlacementMessage =
    'That widget cannot fit there without overlapping another control.';

/// Synthetic selection id for a vacant slot — never a real [ButtonConfig.id].
String vacantSlotSelectionId(int pageIndex, int slotIndex) =>
    '__vacant_${pageIndex}_$slotIndex';

// ─────────────────────────────────────────────────────────────────────────────
// ResolvedButtonCommand
//
// The single place a control screen's onCommand(buttonId, state) handler
// resolves the LOGICAL state id and its EXACT set of user-configured PLC
// output variants, for any id CraneController.setButtonState can be called
// with — a real ButtonConfig id, or a joystick virtual per-direction
// sub-button id. This is a pure lookup: it never adds a variant beyond what
// was explicitly configured for that exact (buttonId, stateId) pair. See
// CraneController.setButtonState's doc comment for the master invariant this
// preserves.
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
/// buttons and the joystick virtual sub-button table. Returns idle/`{}` for
/// any id this function cannot resolve (e.g. a stale id from a
/// just-deleted button) — never guesses.
ResolvedButtonCommand resolveButtonCommand({
  required String buttonId,
  required ControlState state,
  required ControlLayoutConfig layoutCfg,
}) {
  // Joystick virtual per-direction sub-buttons: table lives on the PARENT
  // ButtonConfig (joystickSubButtonMappings), keyed by this sub-button id.
  if (joystickDirectionFor(buttonId) != null) {
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
      config.type == ButtonType.alarmIndicator ||
      config.type == ButtonType.bidirectionalSlider5Step ||
      config.type == ButtonType.bidirectionalSlider3Step) {
    // Horn/alarmIndicator are PLC status-driven FEEDBACK widgets (see
    // HornButtonStrategy/AlarmIndicatorStrategy); the multi-zone sliders
    // dispatch exclusively via onStateIdCommand with their own raw zone id
    // (see multi_zone_slider_strategy.dart). None of these ever call
    // onCommand, so this branch only guards against a stray/legacy call
    // reaching here; always inert.
    return const ResolvedButtonCommand(stateId: 'idle', activeVariants: {});
  }

  final stateId = logicalStateIdFor(type: config.type, physicalState: state);
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

/// A validated, collision-free grid rectangle for a catalogue drop — the
/// result of [findDropPlacement]. Distinct from [ControlGridItem]: this is a
/// candidate slot for a widget that doesn't exist in [buttons] yet.
class DropPlacementTarget {
  const DropPlacementTarget({
    required this.pageIndex,
    required this.gridX,
    required this.gridY,
    required this.colSpan,
    required this.rowSpan,
  });

  final int pageIndex;
  final int gridX;
  final int gridY;
  final int colSpan;
  final int rowSpan;
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
      buttons.values.where(_isPageControl).toList()..sort((a, b) {
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
      buttons.values.where(_isPageControl).toList()..sort((a, b) {
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
  final minSize = ButtonConfig.defaultGridSizeFor(
    selected.type,
    customProperties: selected.customProperties,
    rotation: selected.rotation,
  );
  final nextColumns = gridColumns.clamp(minSize.$1, columns);
  final nextRows = gridRows.clamp(minSize.$2, rows);
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

const String kResizeLockedNeighborMessage =
    'Resizing here would move a locked widget. Unlock it first or resize the other way.';

// ─────────────────────────────────────────────────────────────────────────────
// Edge drag-handle resize
//
// Which edge of the selection frame is being dragged in Customization Mode
// — see resolveResizeHandleDelta/buildButtonResizeWithReflow below. Top/
// bottom only ever change row count; left/right only ever change column
// count, matching the spec that each handle resizes along a single axis.
// ─────────────────────────────────────────────────────────────────────────────
enum ResizeEdge { top, bottom, left, right }

/// Translates a resize-handle drag on [edge] into a requested
/// (columns, rows, anchorX, anchorY) for [original]'s NEW footprint, given
/// [deltaCols]/[deltaRows] whole grid cells of pointer movement since the
/// drag started (positive = right/down) — always measured from [original]'s
/// own pre-drag footprint, never a previous frame's, so backtracking the
/// pointer is exactly reversible (the same principle
/// LayoutEditController.updatePlacementPreview uses for catalogue drops).
///
/// Clamps columns/rows to [original]'s type-minimum (ButtonConfig
/// .defaultGridSizeFor) BEFORE deriving the left/top anchor shift, so the
/// edge opposite the one being dragged stays visually pinned even once the
/// requested delta overshoots the minimum size or the grid's own edge:
///
///  - right/bottom (anchor fixed): the new size is additionally capped by
///    how much room [original]'s own (unmoving) anchor leaves before the
///    grid's far edge — growth simply stops there instead of the final
///    anchor-clamp below silently dragging the fixed edge along with it.
///  - left/top (anchor moves): the new size is capped by [original]'s own
///    opposite edge (`gridX + columns` / `gridY + rows`) — the true
///    upper bound before the anchor would go negative — so shrinking past
///    the minimum, or growing past the grid's near edge, both stop the
///    dragged edge smoothly instead of overshooting.
(int columns, int rows, int anchorX, int anchorY) resolveResizeHandleDelta({
  required ButtonConfig original,
  required ResizeEdge edge,
  required int deltaCols,
  required int deltaRows,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final minSize = ButtonConfig.defaultGridSizeFor(
    original.type,
    customProperties: original.customProperties,
    rotation: original.rotation,
  );
  final originalCols = original.gridColumnSpan;
  final originalRows = original.gridRowSpan;
  var nextColumns = originalCols;
  var nextRows = originalRows;
  var anchorX = original.gridX;
  var anchorY = original.gridY;

  switch (edge) {
    case ResizeEdge.right:
      final maxColumns = _atLeast(columns - original.gridX, minSize.$1);
      nextColumns = (originalCols + deltaCols).clamp(minSize.$1, maxColumns);
    case ResizeEdge.left:
      final maxColumns = _atLeast(original.gridX + originalCols, minSize.$1);
      nextColumns = (originalCols - deltaCols).clamp(minSize.$1, maxColumns);
      anchorX = original.gridX + (originalCols - nextColumns);
    case ResizeEdge.bottom:
      final maxRows = _atLeast(rows - original.gridY, minSize.$2);
      nextRows = (originalRows + deltaRows).clamp(minSize.$2, maxRows);
    case ResizeEdge.top:
      final maxRows = _atLeast(original.gridY + originalRows, minSize.$2);
      nextRows = (originalRows - deltaRows).clamp(minSize.$2, maxRows);
      anchorY = original.gridY + (originalRows - nextRows);
  }

  return (
    nextColumns,
    nextRows,
    anchorX.clamp(0, (columns - nextColumns).clamp(0, columns)),
    anchorY.clamp(0, (rows - nextRows).clamp(0, rows)),
  );
}

/// [value] if it's already >= [minimum], else [minimum] — used to keep a
/// derived upper bound from ever falling below the lower bound a following
/// `.clamp(minimum, upperBound)` call requires (clamp throws if
/// `minimum > upperBound`), which a pathological/corrupt stored
/// [ButtonConfig] (already-out-of-bounds gridX/gridY) could otherwise cause.
int _atLeast(int value, int minimum) => value < minimum ? minimum : value;

/// Same contract as [buildButtonResize], but when the requested footprint
/// would overlap another page control, attempts to displace every UNLOCKED
/// overlapper to the nearest still-free cell on the same page (same-page
/// only — a resize never spills a neighbor onto a new page) instead of
/// immediately rejecting. A LOCKED overlapper is an immovable obstacle: its
/// mere presence in the requested footprint invalidates the resize outright
/// (see [kResizeLockedNeighborMessage]), matching "never move locked
/// widgets." When every overlapper relocates successfully the whole
/// arrangement is validated with [validateGridOccupancy] exactly like a
/// plain resize; any failure (locked obstacle, or no free cell for some
/// overlapper) returns [GridMutationResult.invalid] and leaves [buttons]
/// conceptually untouched — callers should simply keep the last-known-valid
/// draft rather than applying an invalid result, which is what gives a live
/// drag its "stop smoothly at the limit" feel.
GridMutationResult buildButtonResizeWithReflow({
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
  final minSize = ButtonConfig.defaultGridSizeFor(
    selected.type,
    customProperties: selected.customProperties,
    rotation: selected.rotation,
  );
  final nextColumns = gridColumns.clamp(minSize.$1, columns);
  final nextRows = gridRows.clamp(minSize.$2, rows);
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

  final targetSlots = _rectSlots(nextX, nextY, nextColumns, nextRows, columns);

  final overlapping = <ButtonConfig>[
    for (final button in buttons.values)
      if (button.id != selected.id &&
          _isPageControl(button) &&
          button.pageIndex == selected.pageIndex &&
          (occupiedGridSlotsFor(
                button,
                slotCount: slotCount,
                columns: columns,
                rows: rows,
              )?.any(targetSlots.contains) ??
              false))
        button,
  ];

  if (overlapping.isEmpty) {
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

  if (overlapping.any((b) => b.locked)) {
    return const GridMutationResult.invalid(kResizeLockedNeighborMessage);
  }

  // Seed occupancy with the resized widget's new footprint plus every OTHER
  // same-page button that isn't being displaced, then find each overlapper
  // the nearest free anchor to its own current position — reading-order so
  // the search is deterministic when several overlappers compete for the
  // same nearby cells.
  final occupied = <int>{...targetSlots};
  for (final button in buttons.values) {
    if (button.id == selected.id) continue;
    if (!_isPageControl(button)) continue;
    if (button.pageIndex != selected.pageIndex) continue;
    if (overlapping.any((b) => b.id == button.id)) continue;
    final slots = occupiedGridSlotsFor(
      button,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (slots != null) occupied.addAll(slots);
  }

  final displaced = overlapping.toList()
    ..sort(
      (a, b) => _slotFor(
        a.gridX,
        a.gridY,
        columns,
      ).compareTo(_slotFor(b.gridX, b.gridY, columns)),
    );

  final moved = <String, ButtonConfig>{};
  for (final button in displaced) {
    final colSpan = button.gridColumnSpan.clamp(1, columns);
    final rowSpan = button.gridRowSpan.clamp(1, rows);
    final anchor = _nearestFreeAnchorIn(
      occupied: occupied,
      seedCol: button.gridX,
      seedRow: button.gridY,
      colSpan: colSpan,
      rowSpan: rowSpan,
      columns: columns,
      rows: rows,
    );
    if (anchor == null) {
      return const GridMutationResult.invalid(kWidgetPlacementMessage);
    }
    occupied.addAll(_rectSlots(anchor.$1, anchor.$2, colSpan, rowSpan, columns));
    moved[button.id] = button.copyWith(
      gridX: anchor.$1,
      gridY: anchor.$2,
      slotIndex: _slotFor(anchor.$1, anchor.$2, columns),
    );
  }

  final next = {...buttons, selected.id: resized, ...moved};
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
  if (role != null) {
    return const GridMutationResult.invalid(
      'Safety controls cannot be deleted from the grid.',
    );
  }

  final deletedIds = <String>{selected.id};
  final next = <String, ButtonConfig>{};
  for (final entry in buttons.entries) {
    if (deletedIds.contains(entry.key) || deletedIds.contains(entry.value.id)) {
      continue;
    }
    next[entry.key] = _withoutButtonReferences(entry.value, deletedIds);
  }
  return GridMutationResult.valid(next);
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
    if (excludedIds.contains(button.id) || !_isPageControl(button)) {
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

// Every button with a fixed role (estop/resetEstop) is a safety control that
// lives outside the page grid; every roleless button is a generic,
// grid-placeable control.
bool _isPageControl(ButtonConfig button) => button.visible && button.role == null;

String _messageForErrors(List<String> errors, ButtonConfig changed) {
  if (changed.type == ButtonType.bidirectionalSlider5Step ||
      changed.occupiesMultipleGridCells) {
    return kMultiZoneSpanMessage;
  }
  return errors.isEmpty ? kWidgetPlacementMessage : errors.first;
}

// ─────────────────────────────────────────────────────────────────────────────
// Catalogue-drop placement search
//
// Finds where a freshly-dropped (not-yet-created) catalogue widget should
// land: nearest free rectangle to the release point on the page it was
// dropped on, then the first free rectangle on each subsequent existing
// page in order, then a guaranteed-empty page right after the last one.
// Deterministic and collision-free by construction — never overlaps an
// existing button, and never returns a rectangle that doesn't fully fit the
// requested span.
// ─────────────────────────────────────────────────────────────────────────────

/// Finds the best free grid rectangle for a catalogue drop of a widget
/// spanning [colSpan] x [rowSpan] cells, given [dropCenter] (global/overlay
/// coordinates) over a canvas occupying [canvasRect] in that same coordinate
/// space. Prefers the nearest free anchor to [dropCenter] on
/// [currentPageIndex]; falls back to the first free anchor (top-left first)
/// on each subsequent page up to the highest page any button already
/// occupies; and finally an empty page right after that, which always fits
/// since [colSpan]/[rowSpan] never exceed the grid's own dimensions for any
/// real catalogue entry. Returns null only when the requested span itself
/// cannot fit the grid at all.
DropPlacementTarget? findDropPlacement({
  required Map<String, ButtonConfig> buttons,
  required int colSpan,
  required int rowSpan,
  required int currentPageIndex,
  required int existingPageCount,
  required Rect canvasRect,
  required Offset dropCenter,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
  int slotCount = ButtonConfig.controlSlotCount,
}) {
  final effectiveColSpan = colSpan.clamp(1, columns);
  final effectiveRowSpan = rowSpan.clamp(1, rows);
  final maxCol = columns - effectiveColSpan;
  final maxRow = rows - effectiveRowSpan;
  if (maxCol < 0 || maxRow < 0) return null;

  final cellWidth = canvasRect.width / columns;
  final cellHeight = canvasRect.height / rows;
  final rawCol = cellWidth <= 0
      ? 0.0
      : (dropCenter.dx - canvasRect.left) / cellWidth;
  final rawRow = cellHeight <= 0
      ? 0.0
      : (dropCenter.dy - canvasRect.top) / cellHeight;
  final anchorCol = rawCol.floor().clamp(0, maxCol);
  final anchorRow = rawRow.floor().clamp(0, maxRow);

  final existingMaxPage = buttons.values.fold<int>(
    existingPageCount - 1,
    (max, button) => button.pageIndex > max ? button.pageIndex : max,
  );

  final onCurrentPage = _nearestFreeAnchor(
    buttons: buttons,
    pageIndex: currentPageIndex,
    anchorCol: anchorCol,
    anchorRow: anchorRow,
    colSpan: effectiveColSpan,
    rowSpan: effectiveRowSpan,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );
  if (onCurrentPage != null) {
    return DropPlacementTarget(
      pageIndex: currentPageIndex,
      gridX: onCurrentPage.$1,
      gridY: onCurrentPage.$2,
      colSpan: effectiveColSpan,
      rowSpan: effectiveRowSpan,
    );
  }

  for (var page = currentPageIndex + 1; page <= existingMaxPage; page++) {
    final found = _firstFreeAnchor(
      buttons: buttons,
      pageIndex: page,
      colSpan: effectiveColSpan,
      rowSpan: effectiveRowSpan,
      columns: columns,
      rows: rows,
      slotCount: slotCount,
    );
    if (found != null) {
      return DropPlacementTarget(
        pageIndex: page,
        gridX: found.$1,
        gridY: found.$2,
        colSpan: effectiveColSpan,
        rowSpan: effectiveRowSpan,
      );
    }
  }

  // A fresh page past every existing one is always completely empty, so
  // (0, 0) always fits — this is the "create a new page" fallback.
  return DropPlacementTarget(
    pageIndex: existingMaxPage + 1,
    gridX: 0,
    gridY: 0,
    colSpan: effectiveColSpan,
    rowSpan: effectiveRowSpan,
  );
}

Set<int> _occupiedSlotsOnPage(
  Map<String, ButtonConfig> buttons,
  int pageIndex, {
  required int columns,
  required int rows,
  required int slotCount,
}) {
  final occupied = <int>{};
  for (final rawButton in buttons.values) {
    if (!_isPageControl(rawButton)) continue;
    final normalized = normalizeButtonPlacement(
      rawButton,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (normalized.pageIndex != pageIndex) continue;
    final slots = occupiedGridSlotsFor(
      normalized,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    if (slots != null) occupied.addAll(slots);
  }
  return occupied;
}

bool _anchorFits(
  Set<int> occupied,
  int col,
  int row,
  int colSpan,
  int rowSpan,
  int columns,
) {
  for (var r = 0; r < rowSpan; r++) {
    for (var c = 0; c < colSpan; c++) {
      if (occupied.contains((row + r) * columns + (col + c))) return false;
    }
  }
  return true;
}

(int, int)? _nearestFreeAnchor({
  required Map<String, ButtonConfig> buttons,
  required int pageIndex,
  required int anchorCol,
  required int anchorRow,
  required int colSpan,
  required int rowSpan,
  required int columns,
  required int rows,
  required int slotCount,
}) {
  final occupied = _occupiedSlotsOnPage(
    buttons,
    pageIndex,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );
  return _nearestFreeAnchorIn(
    occupied: occupied,
    seedCol: anchorCol,
    seedRow: anchorRow,
    colSpan: colSpan,
    rowSpan: rowSpan,
    columns: columns,
    rows: rows,
  );
}

(int, int)? _firstFreeAnchor({
  required Map<String, ButtonConfig> buttons,
  required int pageIndex,
  required int colSpan,
  required int rowSpan,
  required int columns,
  required int rows,
  required int slotCount,
}) {
  final occupied = _occupiedSlotsOnPage(
    buttons,
    pageIndex,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );
  return _firstFreeAnchorIn(
    occupied: occupied,
    colSpan: colSpan,
    rowSpan: rowSpan,
    columns: columns,
    rows: rows,
  );
}

// Anchor-search primitives operating directly on a caller-supplied occupied
// set, rather than deriving one from a buttons map — shared by the
// catalogue-drop search above (via _nearestFreeAnchor/_firstFreeAnchor) and
// by the live insertion-preview candidate generators below, which must
// mutate a running occupancy snapshot across several evictions/placements
// within a single predictInsertionLayout call.

(int, int)? _nearestFreeAnchorIn({
  required Set<int> occupied,
  required int seedCol,
  required int seedRow,
  required int colSpan,
  required int rowSpan,
  required int columns,
  required int rows,
}) {
  final maxCol = columns - colSpan;
  final maxRow = rows - rowSpan;
  if (maxCol < 0 || maxRow < 0) return null;

  (int, int)? best;
  var bestDistance = 0;
  var bestSlot = 0;
  for (var row = 0; row <= maxRow; row++) {
    for (var col = 0; col <= maxCol; col++) {
      if (!_anchorFits(occupied, col, row, colSpan, rowSpan, columns)) {
        continue;
      }
      final dx = col - seedCol;
      final dy = row - seedRow;
      final distance = dx * dx + dy * dy;
      final slot = row * columns + col;
      if (best == null || distance < bestDistance || (distance == bestDistance && slot < bestSlot)) {
        best = (col, row);
        bestDistance = distance;
        bestSlot = slot;
      }
    }
  }
  return best;
}

(int, int)? _firstFreeAnchorIn({
  required Set<int> occupied,
  required int colSpan,
  required int rowSpan,
  required int columns,
  required int rows,
}) {
  final maxCol = columns - colSpan;
  final maxRow = rows - rowSpan;
  if (maxCol < 0 || maxRow < 0) return null;
  for (var row = 0; row <= maxRow; row++) {
    for (var col = 0; col <= maxCol; col++) {
      if (_anchorFits(occupied, col, row, colSpan, rowSpan, columns)) {
        return (col, row);
      }
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Live insertion preview — intelligent layout optimization
//
// Unlike findDropPlacement above (which only ever finds an already-free
// rectangle), predictInsertionLayout answers a different question: "what is
// the least-disruptive valid arrangement of the ENTIRE layout that honors
// the user's exact intended drop position?" It is a layout optimizer, not a
// collision resolver — it is explicitly free to relocate buttons that don't
// even overlap the target rectangle, if doing so scores better overall than
// only moving direct overlappers (e.g. rippling a couple of untouched
// buttons forward so an evicted one can stay on the current page instead of
// spilling to a new one).
//
// Implemented as a small, extensible pipeline: [_candidateGenerators] is a
// fixed list of deterministic strategies, each proposing a full
// rearrangement of every OTHER button (never the dragged one, whose target
// cell is a hard constraint computed once up front — see below). Every
// candidate is validated, run through a bounded local-improvement pass, and
// scored with the same disruption score; the lowest-scoring valid candidate
// wins. Adding a new strategy later is purely additive: implement one more
// function matching [_InsertionCandidateGenerator] and append it to the
// list — scoring, validation, the hill-climb pass, and every controller/UI
// call site are strategy-agnostic and need no changes.
// ─────────────────────────────────────────────────────────────────────────────

/// An existing button's proposed new page/grid position. Any button whose
/// id is absent from [InsertionPreview.movedButtons] keeps its current
/// position untouched.
class GridPlacement {
  const GridPlacement({
    required this.pageIndex,
    required this.gridX,
    required this.gridY,
  });

  final int pageIndex;
  final int gridX;
  final int gridY;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridPlacement &&
          other.pageIndex == pageIndex &&
          other.gridX == gridX &&
          other.gridY == gridY;

  @override
  int get hashCode => Object.hash(pageIndex, gridX, gridY);
}

/// Which candidate generator produced the winning arrangement — carried
/// purely for tests/debugging; no UI or controller logic branches on this.
enum InsertionStrategy { directDisplacement, rowMajorReflow }

/// The winning arrangement from [predictInsertionLayout].
class InsertionPreview {
  const InsertionPreview({
    required this.movedButtons,
    required this.target,
    required this.strategy,
    required this.disruptionScore,
  });

  final Map<String, GridPlacement> movedButtons;
  final DropPlacementTarget target;
  final InsertionStrategy strategy;
  final int disruptionScore;
}

// Disruption score weights. Higher-priority spec concerns get larger
// weights so they dominate the sum regardless of how the lower-priority
// terms land:
//   - page changes matter most (the spec calls this out both as the FIRST
//     priority — "rearrange on the current page" — and the LAST — "avoid
//     unnecessary page changes" — so it's weighted above everything else).
//   - creating a brand-new page is worse than reusing one that already
//     exists, hence the extra bonus on top of the plain page-change weight.
//   - moving fewer widgets beats moving widgets shorter distances.
//   - reading-order preservation is the lowest-priority, pure tie-break
//     term.
const int _kMovedWidgetWeight = 100;
const int _kPageChangeWeight = 1000;
const int _kNewPageBonus = 500;
const int _kDistanceWeight = 10;
const int _kReadingOrderWeight = 1;

class _InsertionCandidate {
  _InsertionCandidate({
    required this.movedButtons,
    required this.strategy,
    required this.createsNewPage,
  });

  final Map<String, GridPlacement> movedButtons;
  final InsertionStrategy strategy;
  final bool createsNewPage;
}

/// Immutable snapshot every candidate generator reads from — adding a new
/// generator never requires plumbing new parameters through
/// [predictInsertionLayout]'s own signature, only reading more of this.
class _InsertionContext {
  _InsertionContext({
    required this.buttons,
    required this.normalizedById,
    required this.target,
    required this.currentPageIndex,
    required this.existingMaxPage,
    required this.columns,
    required this.rows,
    required this.slotCount,
  });

  final Map<String, ButtonConfig> buttons;
  final Map<String, ButtonConfig> normalizedById;
  final DropPlacementTarget target;
  final int currentPageIndex;
  final int existingMaxPage;
  final int columns;
  final int rows;
  final int slotCount;
}

typedef _InsertionCandidateGenerator = _InsertionCandidate? Function(
  _InsertionContext ctx,
);

// Additional deterministic strategies can be appended here later (e.g. a
// column-major reflow, or a "pack toward the dragged widget" strategy)
// without touching scoring, validation, the hill-climb pass, or any call
// site — every generator produces the same _InsertionCandidate shape and is
// scored/validated identically by predictInsertionLayout below.
const List<_InsertionCandidateGenerator> _candidateGenerators = [
  _directDisplacementCandidate,
  _rowMajorReflowCandidate,
];

/// The grid anchor (col, row) [dropCenter] resolves to over [canvasRect] for
/// a widget spanning [colSpan] x [rowSpan] — floor + clamp to the span's
/// valid range, identical to the math [findDropPlacement] and
/// [predictInsertionLayout] both need. Shared so a caller (see
/// LayoutEditController.updatePlacementPreview) can cheaply detect "the
/// pointer hasn't crossed into a new cell yet" without duplicating this math
/// or paying for a full [predictInsertionLayout] call just to check.
///
/// Callers must only pass a [colSpan]/[rowSpan] that already fits
/// [columns]/[rows] (i.e. after the same guard [findDropPlacement] and
/// [predictInsertionLayout] both perform) — this function assumes that and
/// does not re-validate it.
(int, int) gridAnchorForDropCenter({
  required Rect canvasRect,
  required Offset dropCenter,
  required int colSpan,
  required int rowSpan,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
}) {
  final maxCol = columns - colSpan;
  final maxRow = rows - rowSpan;
  final cellWidth = canvasRect.width / columns;
  final cellHeight = canvasRect.height / rows;
  final rawCol = cellWidth <= 0
      ? 0.0
      : (dropCenter.dx - canvasRect.left) / cellWidth;
  final rawRow = cellHeight <= 0
      ? 0.0
      : (dropCenter.dy - canvasRect.top) / cellHeight;
  return (rawCol.floor().clamp(0, maxCol), rawRow.floor().clamp(0, maxRow));
}

/// Predicts the least-disruptive full-layout arrangement that lands a
/// widget spanning [colSpan] x [rowSpan] exactly at the grid cell under
/// [dropCenter] on [currentPageIndex] (same math as [findDropPlacement]'s
/// own anchor computation) — see this section's doc comment for the overall
/// design. Returns null only when the requested span itself cannot fit the
/// grid at all (mirroring [findDropPlacement]'s own contract).
InsertionPreview? predictInsertionLayout({
  required Map<String, ButtonConfig> buttons,
  required int colSpan,
  required int rowSpan,
  required int currentPageIndex,
  required int existingPageCount,
  required Rect canvasRect,
  required Offset dropCenter,
  int columns = ButtonConfig.controlGridColumns,
  int rows = ButtonConfig.controlGridRows,
  int slotCount = ButtonConfig.controlSlotCount,
}) {
  final effectiveColSpan = colSpan.clamp(1, columns);
  final effectiveRowSpan = rowSpan.clamp(1, rows);
  final maxCol = columns - effectiveColSpan;
  final maxRow = rows - effectiveRowSpan;
  if (maxCol < 0 || maxRow < 0) return null;

  final anchor = gridAnchorForDropCenter(
    canvasRect: canvasRect,
    dropCenter: dropCenter,
    colSpan: effectiveColSpan,
    rowSpan: effectiveRowSpan,
    columns: columns,
    rows: rows,
  );

  final target = DropPlacementTarget(
    pageIndex: currentPageIndex,
    gridX: anchor.$1,
    gridY: anchor.$2,
    colSpan: effectiveColSpan,
    rowSpan: effectiveRowSpan,
  );

  final normalizedById = <String, ButtonConfig>{
    for (final entry in buttons.entries)
      if (_isPageControl(entry.value))
        entry.key: normalizeButtonPlacement(
          entry.value,
          slotCount: slotCount,
          columns: columns,
          rows: rows,
        ),
  };

  final existingMaxPage = normalizedById.values.fold<int>(
    existingPageCount - 1,
    (max, button) => button.pageIndex > max ? button.pageIndex : max,
  );

  final targetSlots = _rectSlots(
    anchor.$1,
    anchor.$2,
    effectiveColSpan,
    effectiveRowSpan,
    columns,
  );
  final hasOverlap = normalizedById.values.any((b) {
    if (b.pageIndex != currentPageIndex) return false;
    final slots = occupiedGridSlotsFor(
      b,
      slotCount: slotCount,
      columns: columns,
      rows: rows,
    );
    return slots != null && slots.any(targetSlots.contains);
  });
  if (!hasOverlap) {
    // Zero-cost fast path: nothing needs to move, so there is nothing to
    // generate/score.
    return InsertionPreview(
      movedButtons: const {},
      target: target,
      strategy: InsertionStrategy.directDisplacement,
      disruptionScore: 0,
    );
  }

  final ctx = _InsertionContext(
    buttons: buttons,
    normalizedById: normalizedById,
    target: target,
    currentPageIndex: currentPageIndex,
    existingMaxPage: existingMaxPage,
    columns: columns,
    rows: rows,
    slotCount: slotCount,
  );

  _InsertionCandidate? best;
  var bestScore = 0;
  for (final generate in _candidateGenerators) {
    final raw = generate(ctx);
    if (raw == null || !_isCandidateValid(ctx, raw)) continue;
    final improved = _localImprovement(ctx, raw);
    final score = _score(ctx, improved);
    final isBetter =
        best == null ||
        score < bestScore ||
        (score == bestScore &&
            improved.movedButtons.length < best.movedButtons.length);
    if (isBetter) {
      best = improved;
      bestScore = score;
    }
  }

  // Every real catalogue entry's span fits an empty page, and both shipped
  // generators always fall back to one when nothing else fits, so `best`
  // should never actually be null here — this guard only protects against a
  // future generator that returns non-null but somehow invalid results for
  // every strategy.
  if (best == null) return null;
  return InsertionPreview(
    movedButtons: best.movedButtons,
    target: target,
    strategy: best.strategy,
    disruptionScore: bestScore,
  );
}

Set<int> _rectSlots(int col, int row, int colSpan, int rowSpan, int columns) {
  final slots = <int>{};
  for (var r = 0; r < rowSpan; r++) {
    for (var c = 0; c < colSpan; c++) {
      slots.add((row + r) * columns + (col + c));
    }
  }
  return slots;
}

int _flatRank(ButtonConfig button, _InsertionContext ctx) =>
    button.pageIndex * ctx.slotCount + _slotFor(button.gridX, button.gridY, ctx.columns);

Map<int, Set<int>> _seedOccupancy(_InsertionContext ctx) {
  final map = <int, Set<int>>{};
  for (final button in ctx.normalizedById.values) {
    final slots =
        occupiedGridSlotsFor(
          button,
          slotCount: ctx.slotCount,
          columns: ctx.columns,
          rows: ctx.rows,
        ) ??
        const [];
    map.putIfAbsent(button.pageIndex, () => {}).addAll(slots);
  }
  return map;
}

/// Candidate 1: only widgets whose cells actually overlap the target
/// rectangle are evicted; each searches for the nearest free anchor to its
/// own original position (current page first, then each subsequent existing
/// page, then a brand-new page as the final fallback). Typically moves the
/// fewest widgets and keeps each one closest to home, but can be forced onto
/// another page even when a broader reshuffle of non-overlapping widgets
/// could have kept everything on the current page — that's exactly the case
/// [_rowMajorReflowCandidate] is meant to win in the scorer.
_InsertionCandidate _directDisplacementCandidate(_InsertionContext ctx) {
  final occupiedByPage = _seedOccupancy(ctx);
  final targetSlots = _rectSlots(
    ctx.target.gridX,
    ctx.target.gridY,
    ctx.target.colSpan,
    ctx.target.rowSpan,
    ctx.columns,
  );

  final overlapping = <ButtonConfig>[
    for (final button in ctx.normalizedById.values)
      if (button.pageIndex == ctx.currentPageIndex &&
          (occupiedGridSlotsFor(
                button,
                slotCount: ctx.slotCount,
                columns: ctx.columns,
                rows: ctx.rows,
              )?.any(targetSlots.contains) ??
              false))
        button,
  ]..sort((a, b) => _flatRank(a, ctx).compareTo(_flatRank(b, ctx)));

  for (final button in overlapping) {
    final slots =
        occupiedGridSlotsFor(
          button,
          slotCount: ctx.slotCount,
          columns: ctx.columns,
          rows: ctx.rows,
        ) ??
        const [];
    occupiedByPage[button.pageIndex]?.removeAll(slots);
  }
  occupiedByPage.putIfAbsent(ctx.currentPageIndex, () => {}).addAll(targetSlots);

  var maxPageUsed = ctx.existingMaxPage;
  final moved = <String, GridPlacement>{};
  for (final button in overlapping) {
    final colSpan = button.gridColumnSpan;
    final rowSpan = button.gridRowSpan;

    final onCurrentPage = _nearestFreeAnchorIn(
      occupied: occupiedByPage[ctx.currentPageIndex] ?? {},
      seedCol: button.gridX,
      seedRow: button.gridY,
      colSpan: colSpan,
      rowSpan: rowSpan,
      columns: ctx.columns,
      rows: ctx.rows,
    );

    GridPlacement placement;
    if (onCurrentPage != null) {
      placement = GridPlacement(
        pageIndex: ctx.currentPageIndex,
        gridX: onCurrentPage.$1,
        gridY: onCurrentPage.$2,
      );
    } else {
      GridPlacement? found;
      for (var page = ctx.currentPageIndex + 1; page <= maxPageUsed; page++) {
        final anchor = _firstFreeAnchorIn(
          occupied: occupiedByPage[page] ?? {},
          colSpan: colSpan,
          rowSpan: rowSpan,
          columns: ctx.columns,
          rows: ctx.rows,
        );
        if (anchor != null) {
          found = GridPlacement(pageIndex: page, gridX: anchor.$1, gridY: anchor.$2);
          break;
        }
      }
      if (found == null) {
        maxPageUsed += 1;
        found = GridPlacement(pageIndex: maxPageUsed, gridX: 0, gridY: 0);
      }
      placement = found;
    }

    moved[button.id] = placement;
    occupiedByPage
        .putIfAbsent(placement.pageIndex, () => {})
        .addAll(_rectSlots(placement.gridX, placement.gridY, colSpan, rowSpan, ctx.columns));
  }

  return _InsertionCandidate(
    movedButtons: moved,
    strategy: InsertionStrategy.directDisplacement,
    createsNewPage: maxPageUsed > ctx.existingMaxPage,
  );
}

/// Candidate 2: flattens every button into one reading-order sequence (page
/// ascending, then anchor slot ascending), finds the rank the target would
/// occupy in that sequence, and greedily repacks only the sequence from that
/// rank onward (CSS-grid-style auto-placement — first free row-major rect on
/// the current packing page, spilling to the next page when full).
/// Everything before the insertion rank is left untouched. Unlike
/// [_directDisplacementCandidate], this can ripple widgets that don't
/// overlap the target at all, which is exactly what "free to move any
/// existing widget if it produces a better overall layout" requires — the
/// scorer decides whether that ripple actually paid off versus Candidate 1.
_InsertionCandidate _rowMajorReflowCandidate(_InsertionContext ctx) {
  final all = ctx.normalizedById.values.toList()
    ..sort((a, b) => _flatRank(a, ctx).compareTo(_flatRank(b, ctx)));

  final targetRank =
      ctx.currentPageIndex * ctx.slotCount +
      _slotFor(ctx.target.gridX, ctx.target.gridY, ctx.columns);

  final before = <ButtonConfig>[];
  final toRepack = <ButtonConfig>[];
  for (final button in all) {
    if (_flatRank(button, ctx) < targetRank) {
      before.add(button);
    } else {
      toRepack.add(button);
    }
  }

  final occupiedByPage = <int, Set<int>>{};
  for (final button in before) {
    final slots =
        occupiedGridSlotsFor(
          button,
          slotCount: ctx.slotCount,
          columns: ctx.columns,
          rows: ctx.rows,
        ) ??
        const [];
    occupiedByPage.putIfAbsent(button.pageIndex, () => {}).addAll(slots);
  }
  occupiedByPage
      .putIfAbsent(ctx.currentPageIndex, () => {})
      .addAll(
        _rectSlots(
          ctx.target.gridX,
          ctx.target.gridY,
          ctx.target.colSpan,
          ctx.target.rowSpan,
          ctx.columns,
        ),
      );

  var packingPage = ctx.currentPageIndex;
  var maxPageUsed = ctx.existingMaxPage;
  final moved = <String, GridPlacement>{};

  for (final button in toRepack) {
    final colSpan = button.gridColumnSpan;
    final rowSpan = button.gridRowSpan;
    var page = packingPage;
    GridPlacement? placement;
    while (placement == null) {
      final occupied = occupiedByPage.putIfAbsent(page, () => {});
      final anchor = _firstFreeAnchorIn(
        occupied: occupied,
        colSpan: colSpan,
        rowSpan: rowSpan,
        columns: ctx.columns,
        rows: ctx.rows,
      );
      if (anchor != null) {
        placement = GridPlacement(pageIndex: page, gridX: anchor.$1, gridY: anchor.$2);
      } else {
        page += 1;
        if (page > maxPageUsed) maxPageUsed = page;
      }
    }
    packingPage = placement.pageIndex;
    occupiedByPage
        .putIfAbsent(placement.pageIndex, () => {})
        .addAll(_rectSlots(placement.gridX, placement.gridY, colSpan, rowSpan, ctx.columns));

    if (placement.pageIndex != button.pageIndex ||
        placement.gridX != button.gridX ||
        placement.gridY != button.gridY) {
      moved[button.id] = placement;
    }
  }

  return _InsertionCandidate(
    movedButtons: moved,
    strategy: InsertionStrategy.rowMajorReflow,
    createsNewPage: maxPageUsed > ctx.existingMaxPage,
  );
}

bool _fitsOwnSpan(_InsertionContext ctx, String id, GridPlacement placement) {
  final config = ctx.normalizedById[id];
  if (config == null) return false;
  return placement.gridX + config.gridColumnSpan <= ctx.columns &&
      placement.gridY + config.gridRowSpan <= ctx.rows;
}

/// Bounded local-improvement pass (a cheap hill-climb, not a general
/// solver): tries pairwise slot swaps between two moved widgets, keeping any
/// swap that lowers the candidate's own disruption score, until no improving
/// swap is found or a small iteration cap is hit. Appropriate for a
/// 2x3-per-page grid where a candidate's moved set is always small.
_InsertionCandidate _localImprovement(
  _InsertionContext ctx,
  _InsertionCandidate candidate,
) {
  if (candidate.movedButtons.length < 2) return candidate;

  var moved = Map<String, GridPlacement>.from(candidate.movedButtons);
  var bestScore = _score(
    ctx,
    _InsertionCandidate(
      movedButtons: moved,
      strategy: candidate.strategy,
      createsNewPage: candidate.createsNewPage,
    ),
  );
  final ids = moved.keys.toList();
  const iterationCap = 20;
  var iterations = 0;
  var improved = true;
  while (improved && iterations < iterationCap) {
    improved = false;
    for (var i = 0; i < ids.length && iterations < iterationCap; i++) {
      for (var j = i + 1; j < ids.length && iterations < iterationCap; j++) {
        iterations++;
        final idA = ids[i];
        final idB = ids[j];
        final placementA = moved[idA]!;
        final placementB = moved[idB]!;
        if (!_fitsOwnSpan(ctx, idA, placementB) ||
            !_fitsOwnSpan(ctx, idB, placementA)) {
          continue;
        }
        final swapped = Map<String, GridPlacement>.from(moved)
          ..[idA] = placementB
          ..[idB] = placementA;
        final swappedCandidate = _InsertionCandidate(
          movedButtons: swapped,
          strategy: candidate.strategy,
          createsNewPage: candidate.createsNewPage,
        );
        if (!_isCandidateValid(ctx, swappedCandidate)) continue;
        final swappedScore = _score(ctx, swappedCandidate);
        if (swappedScore < bestScore) {
          moved = swapped;
          bestScore = swappedScore;
          improved = true;
        }
      }
    }
  }

  return _InsertionCandidate(
    movedButtons: moved,
    strategy: candidate.strategy,
    createsNewPage: candidate.createsNewPage,
  );
}

bool _isCandidateValid(_InsertionContext ctx, _InsertionCandidate candidate) {
  final merged = <String, ButtonConfig>{...ctx.buttons};
  for (final entry in candidate.movedButtons.entries) {
    final original = ctx.normalizedById[entry.key];
    if (original == null) continue;
    final placement = entry.value;
    merged[entry.key] = original.copyWith(
      pageIndex: placement.pageIndex,
      gridX: placement.gridX,
      gridY: placement.gridY,
      slotIndex: _slotFor(placement.gridX, placement.gridY, ctx.columns),
    );
  }
  // A synthetic placeholder for the not-yet-real dragged widget, so an
  // evicted button that (incorrectly) resolved back onto the target rect is
  // caught by validation exactly like any other collision.
  merged['__predicted_target__'] = ButtonConfig(
    id: '__predicted_target__',
    type: ButtonType.pushButton,
    plcMapping: PlcOutputVariant.df2,
    pageIndex: ctx.target.pageIndex,
    gridX: ctx.target.gridX,
    gridY: ctx.target.gridY,
    gridColumns: ctx.target.colSpan,
    gridRows: ctx.target.rowSpan,
  );
  final errors = validateGridOccupancy(
    merged,
    slotCount: ctx.slotCount,
    columns: ctx.columns,
    rows: ctx.rows,
  );
  return errors.isEmpty;
}

int _score(_InsertionContext ctx, _InsertionCandidate candidate) {
  var score = _kMovedWidgetWeight * candidate.movedButtons.length;
  if (candidate.createsNewPage) score += _kNewPageBonus;

  for (final entry in candidate.movedButtons.entries) {
    final original = ctx.normalizedById[entry.key];
    if (original == null) continue;
    final placement = entry.value;

    if (placement.pageIndex != original.pageIndex) {
      score += _kPageChangeWeight;
    } else {
      final distance =
          (placement.gridX - original.gridX).abs() +
          (placement.gridY - original.gridY).abs();
      score += _kDistanceWeight * distance;
    }

    final oldRank = _flatRank(original, ctx);
    final newRank =
        placement.pageIndex * ctx.slotCount +
        _slotFor(placement.gridX, placement.gridY, ctx.columns);
    score += _kReadingOrderWeight * (newRank - oldRank).abs();
  }

  return score;
}
