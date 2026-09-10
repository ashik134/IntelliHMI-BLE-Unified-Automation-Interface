import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Which identity-verification methods a specific PLC (identified by its
/// BLE MAC/remoteId) was configured to use when its first-time setup was
/// completed.
class DeviceSetupRecord {
  const DeviceSetupRecord({
    required this.faceVerificationEnabled,
    required this.biometricEnabled,
    required this.setupAt,
  });

  final bool faceVerificationEnabled;
  final bool biometricEnabled;
  final DateTime setupAt;

  Map<String, dynamic> toJson() => {
    'faceVerificationEnabled': faceVerificationEnabled,
    'biometricEnabled': biometricEnabled,
    'setupAt': setupAt.toIso8601String(),
  };

  factory DeviceSetupRecord.fromJson(Map<String, dynamic> json) {
    return DeviceSetupRecord(
      faceVerificationEnabled: json['faceVerificationEnabled'] as bool? ?? false,
      biometricEnabled: json['biometricEnabled'] as bool? ?? false,
      setupAt: DateTime.tryParse(json['setupAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Persists, per PLC MAC ID, whether that specific device has completed its
/// one-time authentication setup and which identity-verification methods it
/// enabled. Nothing secret lives here — only booleans, a MAC, and a
/// timestamp — so `SharedPreferences` is the right store.
///
/// Deliberately keyed by MAC ID rather than global: a device's setup state
/// must never leak to a different PLC (see [CraneController.currentScreen]).
class DeviceSetupRegistry {
  DeviceSetupRegistry._();

  static const String _kRegistry = 'device_setup_registry_v1';

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

  /// Returns this MAC's setup record, or `null` if it has never completed
  /// first-time setup.
  static Future<DeviceSetupRecord?> get(String macId) async {
    final registry = await _readRegistry();
    final entry = registry[macId];
    if (entry is! Map<String, dynamic>) return null;
    return DeviceSetupRecord.fromJson(entry);
  }

  static Future<bool> isSetupComplete(String macId) async {
    return (await get(macId)) != null;
  }

  static Future<void> markSetupComplete(
    String macId, {
    required bool faceVerificationEnabled,
    required bool biometricEnabled,
  }) async {
    final registry = await _readRegistry();
    registry[macId] = DeviceSetupRecord(
      faceVerificationEnabled: faceVerificationEnabled,
      biometricEnabled: biometricEnabled,
      setupAt: DateTime.now(),
    ).toJson();
    await _writeRegistry(registry);
  }

  /// Test-only: remove all stored setup state.
  static Future<void> resetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRegistry);
  }
}
