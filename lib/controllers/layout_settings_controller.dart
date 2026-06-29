import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';

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

  static const String _prefsKey = 'control_layout_config_v1';

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Loads the persisted config.  Safe to call multiple times; subsequent
  /// calls are no-ops if already loaded.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        _config = ControlLayoutConfig.fromJsonString(raw);
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

  /// Stores the selected widget type for future use.
  /// Does NOT change the active control widget implementation.
  void updateWidgetType(ControlWidgetType widgetType) {
    _config = _config.copyWith(widgetType: widgetType);
    notifyListeners();
    _persist();
  }

  /// Updates the toggle-control wiring configuration.
  void updatePushConfig(PushControlConfig pushConfig) {
    _config = _config.copyWith(pushConfig: pushConfig);
    notifyListeners();
    _persist();
  }

  @Deprecated('Use updatePushConfig instead.')
  void updatepushConfig(PushControlConfig pushConfig) {
    updatePushConfig(pushConfig);
  }

  /// Resets every sub-configuration to factory defaults.
  Future<void> resetToDefaults() async {
    _config = const ControlLayoutConfig();
    notifyListeners();
    await _persist();
  }
}
