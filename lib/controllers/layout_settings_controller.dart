import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/core/constants/app_constants.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutSettingsController
// ─────────────────────────────────────────────────────────────────────────────

class LayoutSettingsController extends ChangeNotifier {
  LayoutSettingsController({LayoutValidationService? validationService})
    : _validator = validationService ?? const LayoutValidationService();

  final LayoutValidationService _validator;

  ControlLayoutConfig _config = const ControlLayoutConfig();
  bool _loaded = false;

  ControlLayoutConfig get config => _config;

  /// True once [load] has completed (or failed with fallback to defaults).
  bool get isLoaded => _loaded;

  static const String _prefsKey = AppConstants.prefsKeyLayoutConfig;

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Loads the persisted config.  Safe to call multiple times; subsequent
  /// calls are no-ops if already loaded.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _config = repairControlGridLayout(
          ControlLayoutConfig.fromJsonString(raw),
        );
      }
    } catch (_) {
      _config = const ControlLayoutConfig();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _config.toJsonString());
    } catch (_) {
      // Non-fatal – layout reverts to defaults on next cold start.
    }
  }

  // ── Mutation API ───────────────────────────────────────────────────────────

  /// Updates the sizing configuration after validation.
  ///
  /// Returns a [ValidationResult].  When [ValidationResult.isValid] is false
  /// the config is NOT changed; callers should display [ValidationResult.errors]
  /// to the operator.
  ValidationResult updateSizeConfig(ControlWidgetSizeConfig sizeConfig) {
    final result = _validator.validateSizeConfig(sizeConfig);
    if (!result.isValid) return result;
    _config = _config.copyWith(sizeConfig: sizeConfig);
    notifyListeners();
    _persist();
    return result;
  }

  /// Updates labels after validation.
  ValidationResult updateLabelConfig(ControlLabelConfig labelConfig) {
    final result = _validator.validateLabelConfig(labelConfig);
    if (!result.isValid) return result;
    _config = _config.copyWith(labelConfig: labelConfig);
    notifyListeners();
    _persist();
    return result;
  }

  /// Updates arrangement toggles (no safety validation required).
  void updateArrangementConfig(ControlArrangementConfig arrangementConfig) {
    _config = _config.copyWith(arrangementConfig: arrangementConfig);
    notifyListeners();
    _persist();
  }

  /// Updates a single axis's control type / wiring / height scale, after
  /// validation (touch-target + scale bounds).
  ValidationResult updateAxisConfig(AxisKind axis, AxisControlConfig config) {
    final result = _validator.validateAxisConfig(axis, config);
    if (!result.isValid) return result;
    _config = _config.copyWith(
      axisConfigs: _config.axisConfigs.withAxis(axis, config),
    );
    notifyListeners();
    _persist();
    return result;
  }

  /// Updates a single role's cosmetic style, after validation. Throws if
  /// [role] is [ControlRole.estop] — E-Stop appearance is not customizable.
  ValidationResult updateRoleStyle(ControlRole role, ButtonStyleConfig style) {
    final result = _validator.validateRoleStyle(role, style);
    if (!result.isValid) return result;
    _config = _config.copyWith(
      roleStyles: _config.roleStyles.withRole(role, style),
    );
    notifyListeners();
    _persist();
    return result;
  }

  /// Updates the display order of the three motion axes (PLC38 only).
  ValidationResult updateAxisOrder(List<AxisKind> axisOrder) {
    final result = _validator.validateAxisOrder(axisOrder);
    if (!result.isValid) return result;
    _config = _config.copyWith(axisOrder: axisOrder);
    notifyListeners();
    _persist();
    return result;
  }

  /// Replaces the entire config after validation. Used by
  /// CustomizationModeController.commit() to persist a fully-edited draft
  /// in one atomic step.
  Future<ValidationResult> replaceConfig(ControlLayoutConfig next) async {
    final repaired = repairControlGridLayout(next);
    final result = _validator.validateFullConfig(repaired);
    if (!result.isValid) return result;
    _config = repaired;
    notifyListeners();
    await _persist();
    return result;
  }

  /// Resets every sub-configuration to factory defaults.
  Future<void> resetToDefaults() async {
    _config = const ControlLayoutConfig();
    notifyListeners();
    await _persist();
  }
}
