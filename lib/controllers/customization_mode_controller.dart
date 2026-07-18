import 'package:flutter/foundation.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationModeController
//
// Owns the DRAFT layout config while Customization Mode is active. This is
// the safety boundary between "editing" and "operating": normal screens read
// LayoutSettingsController.configFor(bucket) (committed); while isActive,
// screens read `draft` instead. Nothing reaches SharedPreferences — and
// therefore nothing can affect the live control screen once Customization
// Mode exits — until commit() is called and passes validation.
//
// Single app-wide instance (constructed once at the provider root, before any
// PLC is connected), so it cannot be told which LayoutBucket it's editing at
// construction time. Instead, [enter] reads CraneController.connectedPlcType
// at the moment editing starts and pins that bucket for the whole session —
// commit()/discard() write back to/read from that same pinned bucket, never
// whatever's currently connected (which could theoretically change mid-edit
// on a disconnect/reconnect).
// ─────────────────────────────────────────────────────────────────────────────

class CustomizationModeController extends ChangeNotifier {
  CustomizationModeController({
    required LayoutSettingsController layoutSettings,
    required CraneController craneController,
    LayoutValidationService? validationService,
  }) : _layoutSettings = layoutSettings,
       _craneController = craneController,
       _validator = validationService ?? const LayoutValidationService();

  final LayoutSettingsController _layoutSettings;
  final CraneController _craneController;
  final LayoutValidationService _validator;

  static const int _maxHistoryDepth = 50;

  bool _isActive = false;
  LayoutBucket _bucket = LayoutBucket.plc14;
  ControlLayoutConfig _draft = const ControlLayoutConfig();
  final List<ControlLayoutConfig> _undoStack = [];
  final List<ControlLayoutConfig> _redoStack = [];
  String? _selectedButtonId;
  int _activeControlPage = 0;
  ValidationResult _lastValidation = const ValidationResult.valid();

  bool get isActive => _isActive;
  ControlLayoutConfig get draft => _draft;
  LayoutBucket get activeBucket => _bucket;
  int get activeControlPage => _activeControlPage;
  ControlRole? get selectedRole => selectedButton?.role;
  ButtonConfig? get selectedButton {
    final id = _selectedButtonId;
    if (id == null) return null;
    final button = _draft.resolvedButtons[id];
    if (button == null || !button.visible) return null;
    return button;
  }

  /// Raw selection id, unlike [selectedButton] this does not resolve
  /// against [_draft.resolvedButtons] — it stays set for a selected vacant
  /// slot (see [vacantSlotSelectionId]), which has no backing ButtonConfig,
  /// so the grid can still draw that slot's selection highlight.
  String? get selectedSlotId => _selectedButtonId;

  bool get canDeleteSelectedButton {
    final button = selectedButton;
    final role = button?.role;
    return button != null && (role == null || role.isMotionControl);
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasUnsavedChanges => _draft != _layoutSettings.configFor(_bucket);
  ValidationResult get lastValidation => _lastValidation;

  /// Enters Customization Mode: pins the layout bucket for this session from
  /// the currently-connected PLC type, seeds the draft from that bucket's
  /// committed config, clears undo/redo history, and forces E-Stop before
  /// draft editing begins (the real gating mechanism is per-control
  /// AbsorbPointer, wired in EditableControlTile — this is a belt-and-
  /// suspenders guarantee that nothing is moving when editing begins).
  Future<void> enter() async {
    if (_isActive) return;
    await _craneController.triggerEStop();
    _bucket = LayoutBucket.forPlcType(_craneController.connectedPlcType);
    _draft = _layoutSettings.configFor(_bucket);
    _undoStack.clear();
    _redoStack.clear();
    _selectedButtonId = null;
    _lastValidation = const ValidationResult.valid();
    _isActive = true;
    notifyListeners();
  }

  void selectRole(ControlRole? role) {
    _selectedButtonId = role?.name;
    notifyListeners();
  }

  void selectButton(ButtonConfig? button) {
    _selectedButtonId = button?.id;
    notifyListeners();
  }

  /// Selects a vacant grid slot so it draws the same highlight as a selected
  /// occupied slot. Uses a synthetic id (see [vacantSlotSelectionId]) that
  /// never resolves in [selectedButton], so rotate/delete stay disabled —
  /// there is no button here yet, only a placeholder.
  void selectVacantSlot(int pageIndex, int slotIndex) {
    _selectedButtonId = vacantSlotSelectionId(pageIndex, slotIndex);
    notifyListeners();
  }

  void setActiveControlPage(int pageIndex) {
    final next = pageIndex < 0 ? 0 : pageIndex;
    if (_activeControlPage == next) return;
    _activeControlPage = next;
    notifyListeners();
  }

  void rotateSelectedButton() {
    final button = selectedButton;
    if (!_isActive || button == null) return;
    applyDraftChange(
      _draft.withButton(
        button.id,
        button.copyWith(rotation: button.rotation.next),
      ),
    );
  }

  GridMutationResult deleteSelectedButton({
    int slotCount = ButtonConfig.controlSlotCount,
  }) {
    final button = selectedButton;
    if (!_isActive || button == null) {
      return const GridMutationResult.invalid('Select a button first.');
    }
    final result = buildButtonDelete(
      buttons: _draft.resolvedButtons,
      selected: button,
      slotCount: slotCount,
    );
    if (!result.isValid) return result;
    _selectedButtonId = null;
    applyDraftChange(_draft.copyWith(buttons: result.buttons));
    return result;
  }

  void createControlPage() {
    if (!_isActive) return;
    final nextCount = _draft.controlPageCount + 1;
    _activeControlPage = nextCount - 1;
    applyDraftChange(_draft.copyWith(controlPageCount: nextCount));
  }

  GridMutationResult addControlButton(
    ButtonConfig button, {
    int? preferredPageIndex,
    int? preferredSlot,
  }) {
    if (!_isActive) {
      return const GridMutationResult.invalid(
        'Enter customization mode first.',
      );
    }
    final result = buildButtonAdd(
      buttons: _draft.resolvedButtons,
      button: button,
      preferredPageIndex: preferredPageIndex ?? _activeControlPage,
      preferredSlot: preferredSlot,
    );
    if (!result.isValid) return result;

    final placed = result.buttons![button.id]!;
    final nextPageCount = placed.pageIndex + 1 > _draft.controlPageCount
        ? placed.pageIndex + 1
        : _draft.controlPageCount;
    _activeControlPage = placed.pageIndex;
    applyDraftChange(
      _draft.copyWith(buttons: result.buttons, controlPageCount: nextPageCount),
    );
    _selectedButtonId = button.id;
    notifyListeners();
    return result;
  }

  void autoArrangeControls({int slotCount = ButtonConfig.controlSlotCount}) {
    if (!_isActive) return;
    applyDraftChange(
      _draft.copyWith(
        buttons: autoArrangeButtons(
          _draft.resolvedButtons,
          slotCount: slotCount,
        ),
      ),
    );
  }

  /// Like [applyDraftChange], but also drops any control page left fully
  /// vacant by [next] (drag-off, resize-off) as part of the same
  /// undo step, and re-points [_activeControlPage] at wherever the active
  /// page landed after compaction. Screens use this instead of
  /// [applyDraftChange] for slot-drop and resize mutations, since either can
  /// empty a page as a side effect. Never used for additive flows
  /// (createControlPage, addControlButton) — those intentionally leave a
  /// page blank for the operator to fill next.
  void applyDraftChangeAndCompact(ControlLayoutConfig next) {
    final compacted = compactControlPages(next);
    applyDraftChange(compacted);
    if (compacted.controlPageCount != next.controlPageCount) {
      _activeControlPage = _activeControlPage.clamp(
        0,
        compacted.controlPageCount - 1,
      );
    }
  }

  /// Pushes the current draft onto the undo stack, clears the redo stack,
  /// and adopts [next] as the new draft. Every field edit in the
  /// customization UI flows through here — this is the single mutation
  /// point, keeping undo/redo trivially correct.
  void applyDraftChange(ControlLayoutConfig next) {
    if (next == _draft) return;
    _undoStack.add(_draft);
    if (_undoStack.length > _maxHistoryDepth) _undoStack.removeAt(0);
    _redoStack.clear();
    _draft = next;
    _lastValidation = _validator.validateFullConfig(_draft);
    notifyListeners();
  }

  void applyTemplate(LayoutTemplate template) {
    if (!_isActive) return;
    applyDraftChange(template.build(_bucket));
  }

  void resetDraftToFactoryDefaults() {
    if (!_isActive) return;
    applyDraftChange(ControlLayoutConfig.defaultForBucket(_bucket));
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_draft);
    _draft = _undoStack.removeLast();
    _lastValidation = _validator.validateFullConfig(_draft);
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_draft);
    _draft = _redoStack.removeLast();
    _lastValidation = _validator.validateFullConfig(_draft);
    notifyListeners();
  }

  /// Validates and persists the draft to the pinned bucket (see [enter]).
  /// On success, exits Customization Mode. On failure, stays active so the
  /// errors can be surfaced in the UI — the operator can then fix the
  /// offending field or discard.
  Future<ValidationResult> commit() async {
    final result = await _layoutSettings.replaceConfig(_bucket, _draft);
    _lastValidation = result;
    if (result.isValid) {
      _exitInternal();
    } else {
      notifyListeners();
    }
    return result;
  }

  /// Discards the draft with no persistence call and exits Customization
  /// Mode. The live screen reverts to whatever was last committed.
  void discard() => _exitInternal();

  void _exitInternal() {
    _isActive = false;
    _draft = _layoutSettings.configFor(_bucket);
    _undoStack.clear();
    _redoStack.clear();
    _selectedButtonId = null;
    notifyListeners();
  }
}
