import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/core/constants/app_constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LayoutSettingsController
//
// Holds one persisted ControlLayoutConfig per PLC layout bucket rather than a
// single app-wide config. Customizing one PLC type's grid must never affect
// another PLC type's screen.
// ─────────────────────────────────────────────────────────────────────────────

class LayoutSettingsController extends ChangeNotifier {
  LayoutSettingsController({LayoutValidationService? validationService})
    : _validator = validationService ?? const LayoutValidationService();

  final LayoutValidationService _validator;

  final Map<LayoutBucket, ControlLayoutConfig> _configs = {
    for (final bucket in LayoutBucket.values)
      bucket: ControlLayoutConfig.defaultForBucket(bucket),
  };
  bool _loaded = false;

  ControlLayoutConfig configFor(LayoutBucket bucket) => _configs[bucket]!;

  /// True once [load] has completed (or failed with fallback to defaults).
  bool get isLoaded => _loaded;

  static String _prefsKeyFor(LayoutBucket bucket) => switch (bucket) {
    LayoutBucket.plc14 => AppConstants.prefsKeyLayoutConfigHoistOnly,
    LayoutBucket.plc21 => AppConstants.prefsKeyLayoutConfigPlc21,
    LayoutBucket.plc38 => AppConstants.prefsKeyLayoutConfigFull,
  };

  static String _migrationPrefsKeyFor(LayoutBucket bucket) => switch (bucket) {
    LayoutBucket.plc14 => AppConstants.prefsKeyLayoutConfigHoistOnly,
    LayoutBucket.plc21 => AppConstants.prefsKeyLayoutConfigHoistOnly,
    LayoutBucket.plc38 => AppConstants.prefsKeyLayoutConfigFull,
  };

  // ── Persistence ────────────────────────────────────────────────────────────

  /// Loads every bucket's persisted config. Safe to call multiple times;
  /// subsequent calls are no-ops if already loaded.
  ///
  /// One-time migration: if a bucket's own key has never been written but
  /// the legacy pre-split single-config key (`prefsKeyLayoutConfig`) has a
  /// value, that old config seeds this bucket's starting point instead of
  /// the factory default — so an existing install's customizations aren't
  /// silently discarded for whichever screen the user actually used them on.
  /// Once every bucket has its own key, the legacy key is left untouched but
  /// never consulted again.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacyRaw = prefs.getString(AppConstants.prefsKeyLayoutConfig);

      for (final bucket in LayoutBucket.values) {
        final raw = prefs.getString(_prefsKeyFor(bucket));
        if (raw != null && raw.isNotEmpty) {
          _configs[bucket] = _repairForOwnGridLayout(
            ControlLayoutConfig.fromJsonString(raw),
          );
        } else {
          final migrationRaw = prefs.getString(_migrationPrefsKeyFor(bucket));
          if (migrationRaw != null && migrationRaw.isNotEmpty) {
            _configs[bucket] = _repairForOwnGridLayout(
              ControlLayoutConfig.fromJsonString(migrationRaw),
            );
          } else if (legacyRaw != null && legacyRaw.isNotEmpty) {
            _configs[bucket] = _repairForOwnGridLayout(
              ControlLayoutConfig.fromJsonString(legacyRaw),
            );
          }
        }
      }
    } catch (_) {
      _configs.addAll({
        for (final bucket in LayoutBucket.values)
          bucket: ControlLayoutConfig.defaultForBucket(bucket),
      });
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// [repairControlGridLayout] against [config]'s OWN [gridLayout] — never
  /// the static 2x3 default. Without this, every cold-start load would
  /// silently re-flatten an already-correctly-saved wider grid (e.g. 4x4)
  /// back toward 2x3, since [repairControlGridLayout]'s own default
  /// params fall back to the static constants.
  ControlLayoutConfig _repairForOwnGridLayout(ControlLayoutConfig config) {
    final grid = config.gridLayout;
    return repairControlGridLayout(
      config,
      slotCount: grid.slotCount,
      columns: grid.columns,
      rows: grid.rows,
    );
  }

  Future<void> _persist(LayoutBucket bucket) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKeyFor(bucket),
        _configs[bucket]!.toJsonString(),
      );
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
  ValidationResult updateSizeConfig(
    LayoutBucket bucket,
    ControlWidgetSizeConfig sizeConfig,
  ) {
    final result = _validator.validateSizeConfig(sizeConfig);
    if (!result.isValid) return result;
    _configs[bucket] = _configs[bucket]!.copyWith(sizeConfig: sizeConfig);
    notifyListeners();
    _persist(bucket);
    return result;
  }

  /// Updates labels after validation.
  ValidationResult updateLabelConfig(
    LayoutBucket bucket,
    ControlLabelConfig labelConfig,
  ) {
    final result = _validator.validateLabelConfig(labelConfig);
    if (!result.isValid) return result;
    _configs[bucket] = _configs[bucket]!.copyWith(labelConfig: labelConfig);
    notifyListeners();
    _persist(bucket);
    return result;
  }

  /// Updates arrangement toggles (no safety validation required).
  void updateArrangementConfig(
    LayoutBucket bucket,
    ControlArrangementConfig arrangementConfig,
  ) {
    _configs[bucket] = _configs[bucket]!.copyWith(
      arrangementConfig: arrangementConfig,
    );
    notifyListeners();
    _persist(bucket);
  }

  /// Replaces a bucket's entire config after validation. Used to persist a
  /// fully-edited draft in one atomic step (e.g. by a future layout editor).
  Future<ValidationResult> replaceConfig(
    LayoutBucket bucket,
    ControlLayoutConfig next,
  ) async {
    final repaired = _repairForOwnGridLayout(next);
    final result = _validator.validateFullConfig(repaired);
    if (!result.isValid) return result;
    _configs[bucket] = repaired;
    notifyListeners();
    await _persist(bucket);
    return result;
  }

  /// Resets a bucket's every sub-configuration to factory defaults.
  Future<void> resetToDefaults(LayoutBucket bucket) async {
    _configs[bucket] = ControlLayoutConfig.defaultForBucket(bucket);
    notifyListeners();
    await _persist(bucket);
  }
}
