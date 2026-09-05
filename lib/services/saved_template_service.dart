import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/core/constants/app_constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart' show LayoutBucket;
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/saved_template.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SavedTemplateService
//
// Persists user-created "Save as Template" snapshots (see SavedTemplate),
// alongside — not replacing — the curated built-ins in LayoutTemplateService.
// Stored as a single JSON array under one SharedPreferences key, the same
// storage mechanism LayoutSettingsController uses for the active per-bucket
// configs.
// ─────────────────────────────────────────────────────────────────────────────

class SavedTemplateService extends ChangeNotifier {
  List<SavedTemplate> _templates = const [];
  bool _loaded = false;

  /// True once [load] has completed (or failed with fallback to empty).
  bool get isLoaded => _loaded;

  List<SavedTemplate> templatesFor(LayoutBucket bucket) =>
      _templates.where((t) => t.bucket == bucket).toList(growable: false);

  /// Loads every saved template. Safe to call multiple times; subsequent
  /// calls are no-ops if already loaded.
  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.prefsKeySavedTemplates);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        _templates = decoded
            .map((e) => SavedTemplate.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _templates = const [];
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_templates.map((t) => t.toJson()).toList());
      await prefs.setString(AppConstants.prefsKeySavedTemplates, raw);
    } catch (_) {
      // Non-fatal – saved templates revert to their last-persisted state on
      // next cold start.
    }
  }

  /// Saves [config] as a new template named [name] under [bucket].
  ///
  /// Returns `false` without saving if a template with the same name
  /// (case-insensitive) already exists for [bucket].
  Future<bool> saveTemplate({
    required String name,
    required LayoutBucket bucket,
    required ControlLayoutConfig config,
  }) async {
    await load();
    final trimmed = name.trim();
    final duplicate = _templates.any(
      (t) =>
          t.bucket == bucket &&
          t.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (duplicate) return false;

    _templates = [
      ..._templates,
      SavedTemplate(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmed,
        bucket: bucket,
        config: config,
        createdAt: DateTime.now(),
      ),
    ];
    notifyListeners();
    await _persist();
    return true;
  }
}
