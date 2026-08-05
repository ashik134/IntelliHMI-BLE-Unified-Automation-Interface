import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Offset, Rect, Size;

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutEditController
//
// Holds the transient "Edit Mode" session: a draft ControlLayoutConfig that
// is freely mutated (add/delete a button, apply a template, edit labels/
// arrangement/sizing) without ever touching SharedPreferences. Nothing this
// controller does is visible to LayoutSettingsController — and therefore
// never persisted — until save()/exit() explicitly commits the draft via
// LayoutSettingsController.replaceConfig, which validates before writing.
//
// Kept deliberately separate from LayoutSettingsController so that
// controller stays a pure persisted-config store with no transient UI state.
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// PlacementSurface
//
// The geometry a mounted control screen exposes to LayoutEditController so
// a catalogue drop (handled from LayoutEditController, which has no
// BuildContext of its own — see handleCatalogueDrop's doc comment) can be
// converted into a grid position: the on-screen rectangle of the control
// grid itself (global/overlay coordinates, matching Draggable's own
// DraggableDetails.offset space), which page is currently displayed, and how
// to animate the PageView to a different one. Registered once by whichever
// control screen (PLC14/PLC38) is currently mounted; only one is ever
// mounted at a time in this app.
// ─────────────────────────────────────────────────────────────────────────────

class PlacementSurface {
  const PlacementSurface({
    required this.canvasRect,
    required this.currentPageIndex,
    required this.navigateToPage,
  });

  final Rect Function() canvasRect;
  final int Function() currentPageIndex;
  final void Function(int pageIndex) navigateToPage;
}

class LayoutEditController extends ChangeNotifier {
  LayoutEditController({
    required LayoutSettingsController layoutSettings,
    required CraneController craneController,
    LayoutValidationService? validationService,
  }) : _layoutSettings = layoutSettings,
       _craneController = craneController,
       _validator = validationService ?? const LayoutValidationService();

  final LayoutSettingsController _layoutSettings;
  final CraneController _craneController;
  final LayoutValidationService _validator;

  bool _isEditing = false;
  LayoutBucket _bucket = LayoutBucket.plc14;
  ControlLayoutConfig _draft = const ControlLayoutConfig();
  String? _selectedButtonId;
  ValidationResult _lastValidation = const ValidationResult.valid();

  // ── Undo / redo history ──────────────────────────────────────────────────
  //
  // Every completed draft mutation (add/delete/duplicate a widget, a
  // catalogue drop's placement + reflow, a property edit, a template/grid
  // swap, an arrangement/label/size change) is eligible for exactly one
  // undo entry, captured as the whole prior [ControlLayoutConfig] rather
  // than a diff — simplest possible correctness given how varied the
  // mutations are, and cheap enough at this scale (a handful of buttons per
  // layout, capped history depth).
  //
  // Some UI surfaces (the Widget Properties sheet's sliders/text fields, the
  // Layout Settings sheet's E-Stop size sliders) call into the draft once
  // per drag frame / keystroke rather than once per logical edit. Wrapping
  // such a surface's whole visit in [beginHistoryBatch]/[endHistoryBatch]
  // (see showWidgetPropertiesSheet / showLayoutSettingsSheet) coalesces
  // every mutation in between into the single entry the operator actually
  // perceives as "one change" — the draft as it stood right before the
  // batch's first mutation. Discrete, single-call mutations made outside a
  // batch (delete-from-canvas, duplicate, apply template, apply grid
  // layout, catalogue placement) are unaffected and each get their own
  // entry immediately.
  static const int _kMaxHistoryEntries = 50;
  final List<ControlLayoutConfig> _undoStack = [];
  final List<ControlLayoutConfig> _redoStack = [];
  int _historyBatchDepth = 0;
  ControlLayoutConfig? _historyBatchCheckpoint;

  /// True once there is a prior draft state to restore. Also false while a
  /// catalogue placement is in flight ([_interactionMode] isn't
  /// [CustomizationInteractionMode.editing]) so Undo/Redo can never rewrite
  /// the draft out from under an in-progress drag/settle animation.
  bool get canUndo =>
      _undoStack.isNotEmpty &&
      _interactionMode == CustomizationInteractionMode.editing;

  /// True once a prior [undo] has something to reapply. See [canUndo] for
  /// why this is also gated on [_interactionMode].
  bool get canRedo =>
      _redoStack.isNotEmpty &&
      _interactionMode == CustomizationInteractionMode.editing;

  /// Snapshots the draft as it stood immediately before [next] takes effect
  /// so [undo] can restore it later. A no-op when [next] is identical to the
  /// current draft (nothing to undo). While a history batch is open, only
  /// the first mutation of the batch captures a checkpoint — see the
  /// class-level doc comment above.
  void _recordHistory(ControlLayoutConfig next) {
    if (next == _draft) return;
    if (_historyBatchDepth > 0) {
      _historyBatchCheckpoint ??= _draft;
      return;
    }
    _pushUndoSnapshot(_draft);
  }

  void _pushUndoSnapshot(ControlLayoutConfig snapshot) {
    _undoStack.add(snapshot);
    if (_undoStack.length > _kMaxHistoryEntries) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  /// Opens a history batch: every draft mutation until the matching
  /// [endHistoryBatch] collapses into at most one undo entry instead of one
  /// per call. Reentrant (nested calls just increment a depth counter) so a
  /// stray double-open can never close the batch early. See the
  /// class-level doc comment for why this exists and who calls it.
  void beginHistoryBatch() {
    _historyBatchDepth++;
  }

  /// Closes a history batch opened by [beginHistoryBatch], pushing the one
  /// coalesced entry (if the draft actually changed during the batch) and
  /// clearing the redo stack. A no-op if nothing was open.
  void endHistoryBatch() {
    if (_historyBatchDepth == 0) return;
    _historyBatchDepth--;
    if (_historyBatchDepth > 0) return;
    final checkpoint = _historyBatchCheckpoint;
    _historyBatchCheckpoint = null;
    if (checkpoint == null) return;
    _pushUndoSnapshot(checkpoint);
    notifyListeners();
  }

  /// Restores the most recent prior draft state, pushing the current one
  /// onto the redo stack. Updates the canvas immediately (via
  /// notifyListeners) without leaving Edit Mode. A no-op if [canUndo] is
  /// false.
  void undo() {
    if (!canUndo) return;
    _redoStack.add(_draft);
    _draft = _undoStack.removeLast();
    _lastValidation = _validator.validateFullConfig(_draft);
    if (_selectedButtonId != null &&
        !_draft.resolvedButtons.containsKey(_selectedButtonId)) {
      _selectedButtonId = null;
    }
    notifyListeners();
  }

  /// Reapplies the most recently undone draft state, pushing the current
  /// one back onto the undo stack. A no-op if [canRedo] is false.
  void redo() {
    if (!canRedo) return;
    _undoStack.add(_draft);
    _draft = _redoStack.removeLast();
    _lastValidation = _validator.validateFullConfig(_draft);
    if (_selectedButtonId != null &&
        !_draft.resolvedButtons.containsKey(_selectedButtonId)) {
      _selectedButtonId = null;
    }
    notifyListeners();
  }

  // ── Catalogue placement (long-press selection stage) ────────────────────
  CustomizationInteractionMode _interactionMode =
      CustomizationInteractionMode.editing;
  CatalogEntry? _pendingCatalogueEntry;

  // ── Catalogue placement (drop / settle stage) ────────────────────────────
  PlacementSurface? _surface;
  Object? _surfaceOwner;
  Rect? _settlingStartRect;
  Rect? _settlingEndRect;
  DropPlacementTarget? _settlingTarget;

  /// Existing buttons the live insertion preview says must relocate to make
  /// room at [_settlingTarget]/[_previewTarget] — see [predictInsertionLayout].
  /// [_previewMoves] is live during [CustomizationInteractionMode.placingWidget]
  /// (recomputed by [updatePlacementPreview] on every pointer move that
  /// crosses into a new grid cell); [_settlingMoves] is the frozen copy
  /// carried into [CustomizationInteractionMode.settlingWidget] and applied
  /// to the draft by [commitSettledPlacement].
  Map<String, GridPlacement> _previewMoves = const {};
  DropPlacementTarget? _previewTarget;
  Map<String, GridPlacement>? _settlingMoves;

  /// (page, col, row) the last [updatePlacementPreview] call actually
  /// recomputed a prediction for — lets subsequent calls skip re-running
  /// [predictInsertionLayout] (and the notifyListeners it would trigger)
  /// while the pointer is still hovering the same grid cell.
  (int, int, int)? _lastPreviewAnchor;

  static const double _kEdgeTurnZonePx = 32;
  static const Duration _kEdgeTurnDelay = Duration(milliseconds: 550);

  Timer? _edgeTurnTimer;
  int? _edgeTurnDirection;

  /// True while the floating preview hovers the canvas's right edge zone —
  /// see [_handleEdgeHover]. Read by [previewLayoutCfg] to keep one extra
  /// blank page reachable even before any prediction has targeted it, so
  /// [PlacementSurface.navigateToPage] always has somewhere valid to animate
  /// the PageView to once the edge-turn timer fires.
  bool _rightEdgeHover = false;

  /// One-shot failure message for the mounted control screen to surface as a
  /// SnackBar (see [clearPlacementError]) — set only when [handleCatalogueDrop]
  /// cannot find any valid rectangle anywhere, which never happens for any
  /// real catalogue entry against this app's grid (max span 2x2 inside a 2x3
  /// grid always fits an empty page) but is handled defensively regardless.
  String? _placementError;

  /// Last known Widgets catalogue scroll offset (pixels). Persisted here —
  /// outside WidgetCatalogScreen's own State — so it survives the screen
  /// being popped mid-placement and is restored the next time the catalogue
  /// opens, per the "preserve scroll position" requirement. Never drives
  /// notifyListeners(): nothing needs to react to it live, it is only read
  /// back when the catalogue is (re)built.
  double _catalogueScrollOffset = 0;

  /// Session-only UI preference for how ControlCanvas animates between grid
  /// pages while editing — see CanvasPageTransitionStyle's doc comment. Never
  /// part of the draft/persisted layout; reset on every [enter].
  CanvasPageTransitionStyle _pageTransitionStyle =
      CanvasPageTransitionStyle.slide;

  bool get isEditing => _isEditing;
  LayoutBucket get activeBucket => _bucket;
  ControlLayoutConfig get draft => _draft;
  String? get selectedButtonId => _selectedButtonId;
  ValidationResult get lastValidation => _lastValidation;
  CanvasPageTransitionStyle get pageTransitionStyle => _pageTransitionStyle;

  CustomizationInteractionMode get interactionMode => _interactionMode;
  CatalogEntry? get pendingCatalogueEntry => _pendingCatalogueEntry;
  double get catalogueScrollOffset => _catalogueScrollOffset;

  /// The floating preview's rectangle (global/overlay coordinates) at the
  /// moment the finger released, and the validated grid rectangle it is
  /// animating into — both non-null only during
  /// [CustomizationInteractionMode.settlingWidget]. See
  /// SettlingPreviewOverlay, which tweens between them.
  Rect? get settlingStartRect => _settlingStartRect;
  Rect? get settlingEndRect => _settlingEndRect;

  String? get placementError => _placementError;

  bool get hasUnsavedChanges => _draft != _layoutSettings.configFor(_bucket);

  /// The draft with the live insertion preview's moved buttons applied — see
  /// [updatePlacementPreview]/[predictInsertionLayout]. Identical to [draft]
  /// whenever there is nothing to preview (not currently placing a widget,
  /// or the target cell was free so nothing needed to move), which is what
  /// makes Cancel "free": ControlCanvas is simply handed [draft] again and
  /// the same generic AnimatedPositioned machinery slides everything back.
  /// Callers (the control screens) should feed this — not [draft] — to
  /// ControlCanvas while [interactionMode] is `placingWidget` or
  /// `settlingWidget`.
  ControlLayoutConfig get previewLayoutCfg {
    if (_previewMoves.isEmpty && _previewTarget == null && !_rightEdgeHover) {
      return _draft;
    }
    final buttons = {..._draft.resolvedButtons};
    var maxPage = _draft.controlPageCount - 1;
    for (final entry in _previewMoves.entries) {
      final current = buttons[entry.key];
      if (current == null) continue;
      final placement = entry.value;
      buttons[entry.key] = current.copyWith(
        pageIndex: placement.pageIndex,
        gridX: placement.gridX,
        gridY: placement.gridY,
        slotIndex:
            placement.gridY * _draft.gridLayout.columns + placement.gridX,
      );
      if (placement.pageIndex > maxPage) maxPage = placement.pageIndex;
    }
    final target = _previewTarget;
    if (target != null && target.pageIndex > maxPage) {
      maxPage = target.pageIndex;
    }
    // Keep one extra blank page reachable while the preview is hovering the
    // canvas's right edge, even before a prediction has actually targeted
    // that page — see _handleEdgeHover/navigateToPage.
    if (_rightEdgeHover) maxPage += 1;
    return _draft.copyWith(buttons: buttons, controlPageCount: maxPage + 1);
  }

  /// Enters Edit Mode for the currently-connected PLC's layout bucket,
  /// seeding the draft from the committed config. Force-latches E-STOP as a
  /// safety measure so no motion control can be actuated while the operator
  /// is looking at the editing canvas instead of the machine.
  Future<void> enter() async {
    if (_isEditing) return;
    await _craneController.triggerEStop();
    _bucket = LayoutBucket.forPlcType(_craneController.connectedPlcType);
    _draft = _layoutSettings.configFor(_bucket);
    _selectedButtonId = null;
    _lastValidation = const ValidationResult.valid();
    _pageTransitionStyle = CanvasPageTransitionStyle.slide;
    _isEditing = true;
    _interactionMode = CustomizationInteractionMode.editing;
    _pendingCatalogueEntry = null;
    _undoStack.clear();
    _redoStack.clear();
    _historyBatchDepth = 0;
    _historyBatchCheckpoint = null;
    notifyListeners();
  }

  // ── Catalogue placement (long-press selection stage) ────────────────────
  //
  // browsingCatalogue -> liftingCatalogueWidget -> placingWidget, mirroring
  // the interaction sequence the Widgets catalogue drives. Every entry point
  // guards on the expected current mode so a stray/duplicate call (e.g. a
  // race between the lift animation's completion and a Cancel tap) is a
  // harmless no-op rather than corrupting the state machine.

  /// Called when the Widgets catalogue overlay opens (see
  /// CatalogueOverlayHost — a sliding Stack layer within the control screen,
  /// deliberately never a pushed Navigator route; see
  /// _DraggableCatalogCard's doc comment in widget_catalog_screen.dart for
  /// why a route would break mid-placement dragging). A no-op if Edit Mode
  /// somehow isn't the current mode (defensive — the catalogue is only ever
  /// reachable from the Edit Mode toolbar).
  void enterCatalogueBrowsing() {
    if (_interactionMode != CustomizationInteractionMode.editing) return;
    _interactionMode = CustomizationInteractionMode.browsingCatalogue;
    notifyListeners();
  }

  /// Called from the catalogue overlay's own Back button, or from a system
  /// back gesture while merely browsing (see the control screens' PopScope
  /// handling). A no-op once a lift/placement is already underway (i.e. the
  /// operator backed out normally rather than starting a placement), so a
  /// stray call can never clobber those later stages.
  void closeCatalogueBrowsing() {
    if (_interactionMode != CustomizationInteractionMode.browsingCatalogue) {
      return;
    }
    _interactionMode = CustomizationInteractionMode.editing;
    notifyListeners();
  }

  /// Long-press recognized on [entry]'s catalogue card: the preview begins
  /// lifting off the card, still over the catalogue.
  void beginCatalogueLift(CatalogEntry entry) {
    if (_interactionMode != CustomizationInteractionMode.browsingCatalogue) {
      return;
    }
    _pendingCatalogueEntry = entry;
    _interactionMode = CustomizationInteractionMode.liftingCatalogueWidget;
    notifyListeners();
  }

  /// The lifted preview is now attached to the finger over the (revealed)
  /// control screen. This stage never finalizes a grid position — it only
  /// means the preview is floating and following the pointer.
  void confirmPlacementStarted() {
    if (_interactionMode !=
        CustomizationInteractionMode.liftingCatalogueWidget) {
      return;
    }
    _interactionMode = CustomizationInteractionMode.placingWidget;
    notifyListeners();
  }

  /// Registers the geometry of the currently-mounted control screen's grid
  /// — called once from that screen's initState (see PlacementSurface's doc
  /// comment). [owner] is that screen's own State object, used purely as an
  /// identity token so a screen that's being disposed can never clobber a
  /// different screen's still-active registration (see
  /// [unregisterPlacementSurface]).
  void registerPlacementSurface(Object owner, PlacementSurface surface) {
    _surfaceOwner = owner;
    _surface = surface;
  }

  /// Clears the registration made by [owner] — a no-op if some other,
  /// still-mounted screen has since registered itself (see [owner]'s doc
  /// comment on [registerPlacementSurface]).
  void unregisterPlacementSurface(Object owner) {
    if (_surfaceOwner != owner) return;
    _surfaceOwner = null;
    _surface = null;
  }

  /// Called once the finger releases over the control screen without being
  /// accepted by the Cancel drop target (see PlacementCancelBar) — i.e. an
  /// attempt to actually place the widget. This — not the Draggable's own
  /// `onDragEnd` closure — is the single place that decides where the
  /// widget lands, because it is the only place with both the draft layout
  /// AND the mounted control screen's grid geometry (via [_surface]); the
  /// catalogue card that owns the Draggable is very likely already
  /// unmounted by this point (its route was popped as soon as the lift
  /// completed), which is exactly why this method lives on the
  /// long-lived controller instead of that screen's own State.
  ///
  /// [globalDropOffset] is the feedback's top-left in the same
  /// global/overlay coordinate space as [PlacementSurface.canvasRect] (see
  /// Flutter's `DraggableDetails.offset`); [previewSize] is the floating
  /// preview's constant on-screen size throughout the drag.
  ///
  /// Called on every pointer move while [CustomizationInteractionMode.placingWidget]
  /// is active (see the `onDragUpdate` wiring in `_DraggableCatalogCard`):
  /// continuously re-predicts the least-disruptive arrangement for landing
  /// the pending entry exactly under [globalOffset] (the floating preview's
  /// current top-left, in the same coordinate space as
  /// [PlacementSurface.canvasRect]/[handleCatalogueDrop]'s own offset), and
  /// runs the edge-hover auto-page-turn check.
  ///
  /// Always recomputed from [_draft] — never from a previous prediction —
  /// so backtracking the pointer (or cancelling) is exactly reversible for
  /// free: nothing here ever compounds. Short-circuits the (comparatively
  /// expensive) [predictInsertionLayout] call/[notifyListeners] when the
  /// pointer hasn't crossed into a new grid cell since the last call.
  void updatePlacementPreview({
    required Offset globalOffset,
    required Size previewSize,
  }) {
    if (_interactionMode != CustomizationInteractionMode.placingWidget) {
      return;
    }
    final entry = _pendingCatalogueEntry;
    final surface = _surface;
    if (entry == null || surface == null) return;

    final dropCenter =
        globalOffset + Offset(previewSize.width / 2, previewSize.height / 2);
    final canvasRect = surface.canvasRect();
    final currentPageIndex = surface.currentPageIndex();

    final edgeChanged = _handleEdgeHover(
      dropCenter: dropCenter,
      canvasRect: canvasRect,
      currentPageIndex: currentPageIndex,
    );

    final grid = _draft.gridLayout;
    final (colSpan, rowSpan) = entry.gridSize;
    final effectiveColSpan = colSpan.clamp(1, grid.columns);
    final effectiveRowSpan = rowSpan.clamp(1, grid.rows);
    final anchor = gridAnchorForDropCenter(
      canvasRect: canvasRect,
      dropCenter: dropCenter,
      colSpan: effectiveColSpan,
      rowSpan: effectiveRowSpan,
      columns: grid.columns,
      rows: grid.rows,
    );
    final anchorKey = (currentPageIndex, anchor.$1, anchor.$2);
    if (anchorKey == _lastPreviewAnchor) {
      if (edgeChanged) notifyListeners();
      return;
    }
    _lastPreviewAnchor = anchorKey;

    final preview = predictInsertionLayout(
      buttons: _draft.resolvedButtons,
      colSpan: colSpan,
      rowSpan: rowSpan,
      currentPageIndex: currentPageIndex,
      existingPageCount: _draft.controlPageCount,
      canvasRect: canvasRect,
      dropCenter: dropCenter,
      columns: grid.columns,
      rows: grid.rows,
      slotCount: grid.slotCount,
    );
    if (preview == null) {
      if (edgeChanged) notifyListeners();
      return;
    }
    _previewMoves = preview.movedButtons;
    _previewTarget = preview.target;
    notifyListeners();
  }

  /// Edge-hover auto-page-turn: while [dropCenter] sits within
  /// [_kEdgeTurnZonePx] of the canvas's left/right edge, starts a
  /// [_kEdgeTurnDelay] timer that flips [PlacementSurface.navigateToPage] to
  /// the adjacent page — restarting itself on each subsequent call so
  /// holding at the edge keeps flipping — so multi-page reflow stays visible
  /// live during a single-finger drag instead of only after release. Left
  /// edge requires an existing previous page; right edge always allows
  /// advancing one page past the highest existing one (see
  /// [_rightEdgeHover]/[previewLayoutCfg], which keeps that page reachable).
  /// Returns whether [_rightEdgeHover] changed, so the caller knows whether
  /// a rebuild is needed even when the grid prediction itself didn't change.
  bool _handleEdgeHover({
    required Offset dropCenter,
    required Rect canvasRect,
    required int currentPageIndex,
  }) {
    final inRightZone =
        canvasRect.width > 0 &&
        dropCenter.dx >= canvasRect.right - _kEdgeTurnZonePx;
    final changed = inRightZone != _rightEdgeHover;
    _rightEdgeHover = inRightZone;

    int? direction;
    if (canvasRect.width > 0) {
      if (dropCenter.dx <= canvasRect.left + _kEdgeTurnZonePx &&
          currentPageIndex > 0) {
        direction = -1;
      } else if (inRightZone) {
        direction = 1;
      }
    }

    if (direction == null) {
      _cancelEdgeTurn();
      return changed;
    }
    if (_edgeTurnDirection == direction && _edgeTurnTimer != null) {
      return changed;
    }
    _edgeTurnTimer?.cancel();
    _edgeTurnDirection = direction;
    final dir = direction;
    _edgeTurnTimer = Timer(_kEdgeTurnDelay, () {
      final surface = _surface;
      _edgeTurnDirection = null;
      _edgeTurnTimer = null;
      if (surface == null) return;
      final nextPage = currentPageIndex + dir;
      if (nextPage < 0) return;
      surface.navigateToPage(nextPage);
    });
    return changed;
  }

  void _cancelEdgeTurn() {
    _edgeTurnTimer?.cancel();
    _edgeTurnTimer = null;
    _edgeTurnDirection = null;
  }

  /// Never adds the widget directly — only finds and validates a target
  /// rectangle, then moves into [CustomizationInteractionMode.settlingWidget]
  /// so the (still-visible) preview can animate into it. See
  /// [commitSettledPlacement] for the actual draft mutation.
  void handleCatalogueDrop({
    required Offset globalDropOffset,
    required Size previewSize,
  }) {
    if (_interactionMode != CustomizationInteractionMode.placingWidget) {
      return;
    }
    final entry = _pendingCatalogueEntry;
    final surface = _surface;
    if (entry == null || surface == null) {
      cancelCataloguePlacement();
      return;
    }

    // Guarantees _previewTarget/_previewMoves reflect the exact release
    // position even if updatePlacementPreview never fired for it (e.g. an
    // instant tap-release with no intervening pointer move).
    updatePlacementPreview(
      globalOffset: globalDropOffset,
      previewSize: previewSize,
    );
    _cancelEdgeTurn();
    _rightEdgeHover = false;

    final target = _previewTarget;
    if (target == null) {
      _placementError = 'No available space for this widget.';
      cancelCataloguePlacement();
      return;
    }

    final canvasRect = surface.canvasRect();
    final cellWidth = canvasRect.width / _draft.gridLayout.columns;
    final cellHeight = canvasRect.height / _draft.gridLayout.rows;
    _settlingStartRect = Rect.fromLTWH(
      globalDropOffset.dx,
      globalDropOffset.dy,
      previewSize.width,
      previewSize.height,
    );
    // Deflated by the same 4px on every side that _OccupiedCell's own
    // Padding(EdgeInsets.all(4)) applies around the real button, so the
    // settle animation's last frame is pixel-identical to the real grid
    // cell it hands off to — no visible size "pop" at commit.
    const cellInset = 4.0;
    _settlingEndRect = Rect.fromLTWH(
      canvasRect.left + target.gridX * cellWidth + cellInset,
      canvasRect.top + target.gridY * cellHeight + cellInset,
      target.colSpan * cellWidth - cellInset * 2,
      target.rowSpan * cellHeight - cellInset * 2,
    );
    _settlingTarget = target;
    _settlingMoves = _previewMoves;
    _interactionMode = CustomizationInteractionMode.settlingWidget;
    if (target.pageIndex != surface.currentPageIndex()) {
      surface.navigateToPage(target.pageIndex);
    }
    notifyListeners();
  }

  /// Called by SettlingPreviewOverlay once its settle animation completes:
  /// turns the validated [_settlingTarget] into a real ButtonConfig, applies
  /// [_settlingMoves] (any existing buttons the insertion preview decided
  /// must relocate to make room), adds both to the draft, selects the new
  /// button, and returns to plain Edit Mode. This is the only place a
  /// catalogue placement actually mutates the draft layout.
  void commitSettledPlacement() {
    if (_interactionMode != CustomizationInteractionMode.settlingWidget) {
      return;
    }
    final entry = _pendingCatalogueEntry;
    final target = _settlingTarget;
    if (entry == null || target == null) {
      cancelCataloguePlacement();
      return;
    }

    final button = entry.buildPreviewConfig().copyWith(
      id: 'placed_${DateTime.now().microsecondsSinceEpoch}',
      catalogEntryId: entry.id,
      pageIndex: target.pageIndex,
      gridX: target.gridX,
      gridY: target.gridY,
      gridColumns: target.colSpan,
      gridRows: target.rowSpan,
      clearSlotIndex: true,
    );

    final buttons = {..._draft.resolvedButtons};
    var maxPage = target.pageIndex;
    for (final moved in (_settlingMoves ?? const {}).entries) {
      final current = buttons[moved.key];
      if (current == null) continue;
      final placement = moved.value;
      buttons[moved.key] = current.copyWith(
        pageIndex: placement.pageIndex,
        gridX: placement.gridX,
        gridY: placement.gridY,
        slotIndex:
            placement.gridY * _draft.gridLayout.columns + placement.gridX,
      );
      if (placement.pageIndex > maxPage) maxPage = placement.pageIndex;
    }
    buttons[button.id] = button;

    final nextPageCount = (maxPage + 1) > _draft.controlPageCount
        ? maxPage + 1
        : _draft.controlPageCount;
    final nextDraft = _draft.copyWith(
      buttons: buttons,
      controlPageCount: nextPageCount,
    );
    _recordHistory(nextDraft);
    _draft = nextDraft;
    _lastValidation = _validator.validateFullConfig(_draft);
    _selectedButtonId = button.id;
    _pendingCatalogueEntry = null;
    _settlingStartRect = null;
    _settlingEndRect = null;
    _settlingTarget = null;
    _settlingMoves = null;
    _previewMoves = const {};
    _previewTarget = null;
    _lastPreviewAnchor = null;
    _interactionMode = CustomizationInteractionMode.editing;
    notifyListeners();
  }

  /// Consumes [placementError] so the same message is never shown twice.
  void clearPlacementError() {
    _placementError = null;
  }

  /// Safe exit from any placement sub-state (Cancel tap, drag end/cancel,
  /// route interruption, ...): drops the pending entry and returns to plain
  /// Edit Mode. Idempotent — safe to call more than once for the same
  /// gesture (e.g. both onDragEnd and a Cancel tap racing). Also aborts an
  /// in-flight settle animation without committing anything — safest
  /// default for the lifecycle/interruption cases this is called from (see
  /// call sites in the control screens), since a widget must never be added
  /// to the draft from anywhere other than a clean [commitSettledPlacement].
  /// Clearing [_previewMoves]/[_previewTarget] here (without touching
  /// [_draft]) is what makes cancelling restore the original layout exactly
  /// — [previewLayoutCfg] falls back to [_draft] as soon as both are empty.
  void cancelCataloguePlacement({bool returnToCatalogueBrowsing = false}) {
    if (_interactionMode == CustomizationInteractionMode.editing) return;
    _pendingCatalogueEntry = null;
    _settlingStartRect = null;
    _settlingEndRect = null;
    _settlingTarget = null;
    _settlingMoves = null;
    _previewMoves = const {};
    _previewTarget = null;
    _lastPreviewAnchor = null;
    _rightEdgeHover = false;
    _cancelEdgeTurn();
    _interactionMode =
        returnToCatalogueBrowsing &&
            _interactionMode ==
                CustomizationInteractionMode.liftingCatalogueWidget
        ? CustomizationInteractionMode.browsingCatalogue
        : CustomizationInteractionMode.editing;
    notifyListeners();
  }

  /// Persists the catalogue's current scroll offset for next time. Never
  /// notifies listeners — see [catalogueScrollOffset]'s doc comment.
  void updateCatalogueScrollOffset(double offset) {
    _catalogueScrollOffset = offset;
  }

  void selectButton(String? id) {
    if (_selectedButtonId == id) return;
    _selectedButtonId = id;
    notifyListeners();
  }

  void setPageTransitionStyle(CanvasPageTransitionStyle style) {
    if (_pageTransitionStyle == style) return;
    _pageTransitionStyle = style;
    notifyListeners();
  }

  /// Places [button] at the next open grid slot in the draft. Returns the
  /// [GridMutationResult] so the caller (Widget Catalog) can show an error
  /// and stay on the catalog page rather than popping on failure.
  GridMutationResult addButton(ButtonConfig button) {
    final grid = _draft.gridLayout;
    final result = buildButtonAdd(
      buttons: _draft.resolvedButtons,
      button: button,
      preferredPageIndex: 0,
      slotCount: grid.slotCount,
      columns: grid.columns,
      rows: grid.rows,
    );
    if (result.isValid) {
      final placed = result.buttons![button.id]!;
      final nextPageCount = (placed.pageIndex + 1) > _draft.controlPageCount
          ? placed.pageIndex + 1
          : _draft.controlPageCount;
      _applyDraft(
        _draft.copyWith(
          buttons: result.buttons,
          controlPageCount: nextPageCount,
        ),
      );
      _selectedButtonId = button.id;
      notifyListeners();
    }
    return result;
  }

  GridMutationResult deleteButton(String id) {
    final button = _draft.resolvedButtons[id];
    if (button == null) {
      return const GridMutationResult.invalid('Button not found.');
    }
    final result = buildButtonDelete(
      buttons: _draft.resolvedButtons,
      selected: button,
    );
    if (result.isValid) {
      if (_selectedButtonId == id) _selectedButtonId = null;
      _applyDraft(_draft.copyWith(buttons: result.buttons));
    }
    return result;
  }

  /// Clones [id]'s ButtonConfig onto the next open grid slot and selects the
  /// copy. Refuses safety controls (role != null), mirroring
  /// [deleteButton]'s guard — those live outside the grid entirely and are
  /// never reachable via canvas selection in practice, but the guard keeps
  /// this method's own contract self-evident.
  GridMutationResult duplicateButton(String id) {
    final source = _draft.resolvedButtons[id];
    if (source == null) {
      return const GridMutationResult.invalid('Button not found.');
    }
    if (source.role != null) {
      return const GridMutationResult.invalid(
        'Safety controls cannot be duplicated.',
      );
    }
    final clone = source.copyWith(
      id: 'copy_${DateTime.now().microsecondsSinceEpoch}',
      clearSlotIndex: true,
    );
    return addButton(clone);
  }

  /// Applies [update] to [id]'s ButtonConfig in the draft — the mutation
  /// entry point for the Properties sheet (label/enabled edits). A no-op if
  /// [id] no longer exists (e.g. deleted from another surface while a
  /// Properties sheet referencing it was still open).
  void updateButton(String id, ButtonConfig Function(ButtonConfig) update) {
    final current = _draft.resolvedButtons[id];
    if (current == null) return;
    var updated = update(current);
    final isMultiZoneSlider =
        current.type == ButtonType.bidirectionalSlider3Step ||
        current.type == ButtonType.bidirectionalSlider5Step;
    final changesFootprintAxis =
        current.rotation.quarterTurns.isOdd !=
        updated.rotation.quarterTurns.isOdd;

    if (!isMultiZoneSlider || !changesFootprintAxis) {
      _applyDraft(_draft.withButton(id, updated));
      return;
    }

    // A quarter-turn changes the physical operational contract from W×H to
    // H×W. Swap the existing allocation at the same time, then let the grid
    // repairer relocate any collision instead of leaving an invalid draft.
    updated = updated.copyWith(
      gridColumns: current.gridRowSpan,
      gridRows: current.gridColumnSpan,
    );
    final grid = _draft.gridLayout;
    final repaired = compactControlPages(
      repairControlGridLayout(
        _draft.withButton(id, updated),
        slotCount: grid.slotCount,
        columns: grid.columns,
        rows: grid.rows,
      ),
      slotCount: grid.slotCount,
      columns: grid.columns,
      rows: grid.rows,
    );
    _applyDraft(repaired);
  }

  /// Resets [id]'s appearance/behavior/customProperties/label/icon/rotation
  /// to a known default — the Properties sheet's "Reset to default" action.
  /// Never touches [ButtonConfig.stateMappings]/[ButtonConfig
  /// .joystickSubButtonMappings]/[ButtonConfig.mutualExclusion]: an
  /// appearance reset must never silently change what a widget sends to the
  /// PLC.
  ///
  /// If [id] was placed from a known catalogue entry (see
  /// [ButtonConfig.catalogEntryId]), restores that exact entry's
  /// style/behavior/customProperties/label — this is the only way to know
  /// which of several same-[ButtonType] catalogue variants (e.g. the two
  /// push-button entries) it actually was. Otherwise (pre-existing button
  /// from before [ButtonConfig.catalogEntryId] existed, or any non-catalogue
  /// -sourced button) resets appearance only, never guessing at
  /// behavior/customProperties without a known source.
  void resetButtonToDefault(String id) {
    final current = _draft.resolvedButtons[id];
    if (current == null) return;

    CatalogEntry? source;
    final catalogEntryId = current.catalogEntryId;
    if (catalogEntryId != null) {
      for (final entry in kWidgetCatalog) {
        if (entry.id == catalogEntryId) {
          source = entry;
          break;
        }
      }
    }

    if (source != null) {
      final resolvedSource = source;
      updateButton(
        id,
        (b) => b.copyWith(
          label: resolvedSource.name,
          style: const ButtonStyleConfig(),
          behavior: resolvedSource.behavior,
          customProperties: resolvedSource.customProperties,
          rotation: ButtonRotation.none,
          clearIcon: true,
          clearIconKey: true,
        ),
      );
      return;
    }

    updateButton(id, (b) => b.copyWith(style: const ButtonStyleConfig()));
  }

  void toggleArrangement(ArrangementToggle which) {
    _applyDraft(
      _draft.copyWith(arrangementConfig: which.apply(_draft.arrangementConfig)),
    );
  }

  void updateDraftLabelConfig(ControlLabelConfig next) {
    _applyDraft(_draft.copyWith(labelConfig: next));
  }

  void updateDraftSizeConfig(ControlWidgetSizeConfig next) {
    _applyDraft(_draft.copyWith(sizeConfig: next));
  }

  void updateDraftArrangementConfig(ControlArrangementConfig next) {
    _applyDraft(_draft.copyWith(arrangementConfig: next));
  }

  /// Replaces the entire draft with [template]'s layout — a full overwrite,
  /// not a merge. Callers (Load Template sheet) are responsible for warning
  /// the operator first when [hasUnsavedChanges] is true.
  ///
  /// Preserves the draft's current [ControlLayoutConfig.gridLayout] across
  /// the swap — templates are about button composition/styling, not grid
  /// geometry, so applying one must never silently reset an operator's
  /// chosen grid shape back to default. Repairs+compacts the template's
  /// (fixed, legacy 2-column-shaped) buttons against that preserved shape
  /// since it may now be narrower than what the template assumes (e.g. the
  /// active grid is 2x2 while a template places up to 6 buttons).
  void applyTemplate(LayoutTemplate template) {
    final grid = _draft.gridLayout;
    final merged = template.build(_bucket).copyWith(gridLayout: grid);
    final repaired = compactControlPages(
      repairControlGridLayout(
        merged,
        slotCount: grid.slotCount,
        columns: grid.columns,
        rows: grid.rows,
      ),
      slotCount: grid.slotCount,
      columns: grid.columns,
      rows: grid.rows,
    );
    _applyDraft(repaired);
  }

  /// Switches the draft to a new grid shape — the Customization Toolbar's
  /// Layout tool's Apply action (see GridLayoutToolbar). Reflows any buttons
  /// that no longer fit [option]'s (possibly smaller) footprint via
  /// [repairControlGridLayout] — built for exactly this: re-places placeable
  /// buttons into the first still-free slot honoring the new dimensions,
  /// spilling to a new page if needed — then [compactControlPages] drops any
  /// now-empty trailing page. A no-op if [option] is already active.
  void applyGridLayout(GridLayoutOption option) {
    if (_draft.gridLayout == option) return;
    final repaired = compactControlPages(
      repairControlGridLayout(
        _draft.copyWith(gridLayout: option),
        slotCount: option.slotCount,
        columns: option.columns,
        rows: option.rows,
      ),
      slotCount: option.slotCount,
      columns: option.columns,
      rows: option.rows,
    );
    _applyDraft(repaired);
  }

  void _applyDraft(ControlLayoutConfig next) {
    _recordHistory(next);
    _draft = next;
    _lastValidation = _validator.validateFullConfig(_draft);
    notifyListeners();
  }

  /// Validates and persists the draft via LayoutSettingsController, without
  /// leaving Edit Mode. Stays the draft's baseline at the repaired, persisted
  /// config on success.
  Future<ValidationResult> save() async {
    final result = await _layoutSettings.replaceConfig(_bucket, _draft);
    _lastValidation = result;
    if (result.isValid) {
      _draft = _layoutSettings.configFor(_bucket);
    }
    notifyListeners();
    return result;
  }

  /// Validates, saves, and — only on success — leaves Edit Mode. On failure
  /// the session stays active so the operator can fix the reported errors
  /// and press Done again.
  Future<ValidationResult> exit() async {
    final result = await save();
    if (result.isValid) {
      _isEditing = false;
      _selectedButtonId = null;
      _interactionMode = CustomizationInteractionMode.editing;
      _pendingCatalogueEntry = null;
      notifyListeners();
    }
    return result;
  }

  @override
  void dispose() {
    _cancelEdgeTurn();
    super.dispose();
  }
}
