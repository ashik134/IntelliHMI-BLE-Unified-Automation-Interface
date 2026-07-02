import 'package:flutter/foundation.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CustomizationModeController
//
// Owns the DRAFT layout config while Customization Mode is active. This is
// the safety boundary between "editing" and "operating": normal screens read
// LayoutSettingsController.config (committed); while isActive, screens read
// `draft` instead. Nothing reaches SharedPreferences — and therefore nothing
// can affect the live control screen once Customization Mode exits — until
// commit() is called and passes validation.
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
  ControlLayoutConfig _draft = const ControlLayoutConfig();
  final List<ControlLayoutConfig> _undoStack = [];
  final List<ControlLayoutConfig> _redoStack = [];
  ControlRole? _selectedRole;
  ValidationResult _lastValidation = const ValidationResult.valid();

  bool get isActive => _isActive;
  ControlLayoutConfig get draft => _draft;
  ControlRole? get selectedRole => _selectedRole;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get hasUnsavedChanges => _draft != _layoutSettings.config;
  ValidationResult get lastValidation => _lastValidation;

  /// Enters Customization Mode: seeds the draft from the committed config,
  /// clears undo/redo history, and stops any in-flight motion as
  /// defense-in-depth (the real gating mechanism is per-control
  /// AbsorbPointer, wired in EditableControlTile — this is a belt-and-
  /// suspenders guarantee that nothing is moving when editing begins).
  Future<void> enter() async {
    if (_isActive) return;
    await _craneController.stopAllMotion();
    _draft = _layoutSettings.config;
    _undoStack.clear();
    _redoStack.clear();
    _selectedRole = null;
    _lastValidation = const ValidationResult.valid();
    _isActive = true;
    notifyListeners();
  }

  void selectRole(ControlRole? role) {
    _selectedRole = role;
    notifyListeners();
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

  /// Validates and persists the draft. On success, exits Customization Mode.
  /// On failure, stays active so the errors can be surfaced in the UI —
  /// the operator can then fix the offending field or discard.
  Future<ValidationResult> commit() async {
    final result = await _layoutSettings.replaceConfig(_draft);
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
    _draft = _layoutSettings.config;
    _undoStack.clear();
    _redoStack.clear();
    _selectedRole = null;
    notifyListeners();
  }
}
