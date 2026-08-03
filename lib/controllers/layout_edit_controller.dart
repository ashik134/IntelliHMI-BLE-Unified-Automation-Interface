import 'package:flutter/foundation.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
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

  // ── Catalogue placement (long-press selection stage) ────────────────────
  CustomizationInteractionMode _interactionMode =
      CustomizationInteractionMode.editing;
  CatalogEntry? _pendingCatalogueEntry;

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

  bool get hasUnsavedChanges => _draft != _layoutSettings.configFor(_bucket);

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
    notifyListeners();
  }

  // ── Catalogue placement (long-press selection stage) ────────────────────
  //
  // browsingCatalogue -> liftingCatalogueWidget -> placingWidget, mirroring
  // the interaction sequence the Widgets catalogue drives. Every entry point
  // guards on the expected current mode so a stray/duplicate call (e.g. a
  // race between the lift animation's completion and a Cancel tap) is a
  // harmless no-op rather than corrupting the state machine.

  /// Called when the Widgets catalogue route is pushed. A no-op if Edit Mode
  /// somehow isn't the current mode (defensive — the catalogue is only ever
  /// reachable from the Edit Mode toolbar).
  void enterCatalogueBrowsing() {
    if (_interactionMode != CustomizationInteractionMode.editing) return;
    _interactionMode = CustomizationInteractionMode.browsingCatalogue;
    notifyListeners();
  }

  /// Called after the catalogue route's push Future resolves. Only resets to
  /// editing if nothing else already moved the mode on (i.e. the operator
  /// backed out normally rather than starting a placement) — starting a
  /// placement pops the same route, so this must not clobber that.
  void exitCatalogueBrowsingIfIdle() {
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

  /// Safe exit from any placement sub-state (Cancel tap, drag end/cancel,
  /// route interruption, ...): drops the pending entry and returns to plain
  /// Edit Mode. Idempotent — safe to call more than once for the same
  /// gesture (e.g. both onDragEnd and a Cancel tap racing).
  void cancelCataloguePlacement({bool returnToCatalogueBrowsing = false}) {
    if (_interactionMode == CustomizationInteractionMode.editing) return;
    _pendingCatalogueEntry = null;
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
    final result = buildButtonAdd(
      buttons: _draft.resolvedButtons,
      button: button,
      preferredPageIndex: 0,
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
    _applyDraft(_draft.withButton(id, update(current)));
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
  void applyTemplate(LayoutTemplate template) {
    _applyDraft(template.build(_bucket));
  }

  void _applyDraft(ControlLayoutConfig next) {
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
}
