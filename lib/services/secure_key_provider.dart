import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Get-or-create a domain-scoped AES-256 key, Keystore-backed via
/// [FlutterSecureStorage] (same configuration as
/// [SecureCredentialStore]/[DeviceIdentityService]).
///
/// Callers pass a unique domain name per store (e.g. `intellihmi.auth-log.key`,
/// `intellihmi.operator-store.key`) so a compromise or bug in one store's
/// format can't be leveraged against another store's ciphertext — each
/// domain gets its own independently-generated key, never shared.
class SecureKeyProvider {
  SecureKeyProvider._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static final AesGcm _algorithm = AesGcm.with256bits();

  static final Map<String, SecretKey> _cache = {};

  static Future<SecretKey> getOrCreateKey(String domain) async {
    final cached = _cache[domain];
    if (cached != null) return cached;

    try {
      final stored = await _storage.read(key: domain);
      if (stored != null && stored.isNotEmpty) {
        final key = SecretKey(base64Decode(stored));
        _cache[domain] = key;
        return key;
      }
    } catch (_) {
      // Fall through and mint a fresh key below.
    }

    final generated = await _algorithm.newSecretKey();
    final bytes = await generated.extractBytes();
    try {
      await _storage.write(key: domain, value: base64Encode(bytes));
    } catch (_) {
      // Key still works for this process even if it couldn't persist; the
      // next launch will mint a new one and existing ciphertext for this
      // domain becomes unreadable, but it never blocks the caller.
    }
    _cache[domain] = generated;
    return generated;
  }

  /// Test-only: forget cached keys so a test's temp-directory stores start
  /// from a clean slate instead of reusing a previous test's in-memory key.
  static void resetCacheForTesting() => _cache.clear();
}
