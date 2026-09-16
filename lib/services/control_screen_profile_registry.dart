import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';

/// Persists which [ControlScreenProfile] a specific operator has chosen for
/// a specific PLC, keyed by the combination of `operatorId` (or a session
/// email fallback — see [CraneController.currentOperatorIdentity]) and the
/// PLC's BLE MAC id. Nothing secret lives here — only an enum choice — so
/// `SharedPreferences` is the right store, same reasoning as
/// [DeviceSetupRegistry].
///
/// Deliberately nested (`{ operatorId: { macId: profileName } }`) rather
/// than a composite string key: a BLE MAC id already contains colons, so
/// concatenating operatorId+macId into one delimited string risks collision.
/// A JSON object key needs no delimiter/escaping, so nesting sidesteps the
/// problem entirely and keeps each operator's PLC map independent — the same
/// PLC MAC can therefore hold a different profile per operator, and the same
/// operator can hold a different profile per PLC.
class ControlScreenProfileRegistry {
  ControlScreenProfileRegistry._();

  static const String _kRegistry = 'control_screen_profile_registry_v1';

  static Future<Map<String, dynamic>> _readRegistry() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kRegistry);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeRegistry(Map<String, dynamic> registry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRegistry, jsonEncode(registry));
  }

  /// Returns the saved profile for this (operatorId, macId) pair, or `null`
  /// if none was ever saved — or the saved value is no longer a recognized
  /// [ControlScreenProfile] — so callers can fall back to profile selection.
  static Future<ControlScreenProfile?> get(
    String operatorId,
    String macId,
  ) async {
    final registry = await _readRegistry();
    final operatorEntry = registry[operatorId];
    if (operatorEntry is! Map<String, dynamic>) return null;
    return ControlScreenProfile.fromString(operatorEntry[macId] as String?);
  }

  static Future<void> save(
    String operatorId,
    String macId,
    ControlScreenProfile profile,
  ) async {
    final registry = await _readRegistry();
    final operatorEntry = Map<String, dynamic>.from(
      (registry[operatorId] as Map?)?.cast<String, dynamic>() ?? {},
    );
    operatorEntry[macId] = profile.name;
    registry[operatorId] = operatorEntry;
    await _writeRegistry(registry);
  }

  /// Test-only: remove all stored profile choices.
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRegistry);
  }
}
