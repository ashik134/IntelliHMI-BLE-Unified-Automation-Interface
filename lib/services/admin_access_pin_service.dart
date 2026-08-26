import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AdminPinVerifyResult { success, incorrect, lockedOut }

/// Single app-level PIN gating Operator Management access until Stage 4's
/// real authenticated-administrator sessions exist. Afterward, the same
/// PIN becomes the "Administrator PIN" fallback spec section 24 describes
/// — this is a permanent piece of the design arriving early, not throwaway
/// scaffolding.
///
/// The PIN is verified, never read back: it's stored as a PBKDF2 salted
/// hash (already available via the existing `cryptography` dependency),
/// not an encrypted-and-decryptable value like the audit log/operator
/// store — deliberately a different mechanism from `EncryptedStoreCodec`.
class AdminAccessPinService {
  AdminAccessPinService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _kHash = 'admin_access_pin_hash_v1';
  static const String _kSalt = 'admin_access_pin_salt_v1';
  static const String _kFailedAttempts = 'admin_access_pin_failed_attempts';
  static const String _kLockedUntil =
      'admin_access_pin_locked_until_epoch_ms';

  static const int minPinLength = 6;
  static const int _maxFailedAttempts = 5;
  static const Duration _lockoutDuration = Duration(minutes: 5);

  static final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  static Future<bool> isSet() async {
    final hash = await _storage.read(key: _kHash);
    return hash != null && hash.isNotEmpty;
  }

  static bool isValidPinFormat(String pin) =>
      pin.length >= minPinLength && RegExp(r'^\d+$').hasMatch(pin);

  /// Sets the PIN — used for first-time bootstrap setup. Does not require
  /// knowing a previous PIN; callers that must prove they know the current
  /// PIN before changing it should use [changePin] instead.
  static Future<void> setPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('PIN must be at least $minPinLength digits.');
    }
    final salt = _randomBytes(16);
    final hash = await _deriveHash(pin, salt);
    await _storage.write(key: _kSalt, value: base64Encode(salt));
    await _storage.write(key: _kHash, value: base64Encode(hash));
    await _clearLockoutState();
  }

  static Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final result = await verify(currentPin);
    if (result != AdminPinVerifyResult.success) {
      throw StateError('Current PIN did not verify; refusing to change it.');
    }
    await setPin(newPin);
  }

  static Future<AdminPinVerifyResult> verify(String pin) async {
    final remaining = await remainingLockoutSeconds();
    if (remaining > 0) return AdminPinVerifyResult.lockedOut;

    final storedSaltB64 = await _storage.read(key: _kSalt);
    final storedHashB64 = await _storage.read(key: _kHash);
    if (storedSaltB64 == null || storedHashB64 == null) {
      // Nothing set yet — verification against a nonexistent PIN can never
      // succeed. Callers should check isSet() first and route to setup.
      return AdminPinVerifyResult.incorrect;
    }

    final salt = base64Decode(storedSaltB64);
    final storedHash = base64Decode(storedHashB64);
    final candidateHash = await _deriveHash(pin, salt);

    if (_constantTimeEquals(candidateHash, storedHash)) {
      await _clearLockoutState();
      return AdminPinVerifyResult.success;
    }

    await _recordFailedAttempt();
    // Report lockedOut immediately on the attempt that trips the
    // threshold, rather than "incorrect" now and "lockedOut" only from
    // the next call.
    return (await remainingLockoutSeconds()) > 0
        ? AdminPinVerifyResult.lockedOut
        : AdminPinVerifyResult.incorrect;
  }

  /// Seconds remaining until verification is allowed again, or 0.
  static Future<int> remainingLockoutSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    final lockedUntil = prefs.getInt(_kLockedUntil);
    if (lockedUntil == null) return 0;
    final remainingMs = lockedUntil - DateTime.now().millisecondsSinceEpoch;
    return remainingMs > 0 ? (remainingMs / 1000).ceil() : 0;
  }

  static Future<int> failedAttemptCount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kFailedAttempts) ?? 0;
  }

  static Future<Uint8List> _deriveHash(String pin, List<int> salt) async {
    final secretKey = await _pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
    return Uint8List.fromList(await secretKey.extractBytes());
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  static Future<void> _recordFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final attempts = (prefs.getInt(_kFailedAttempts) ?? 0) + 1;
    await prefs.setInt(_kFailedAttempts, attempts);
    if (attempts >= _maxFailedAttempts) {
      final until = DateTime.now()
          .add(_lockoutDuration)
          .millisecondsSinceEpoch;
      await prefs.setInt(_kLockedUntil, until);
    }
  }

  static Future<void> _clearLockoutState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFailedAttempts);
    await prefs.remove(_kLockedUntil);
  }

  /// Test-only: remove all stored PIN/lockout state.
  static Future<void> resetForTesting() async {
    await _storage.delete(key: _kHash);
    await _storage.delete(key: _kSalt);
    await _clearLockoutState();
  }
}
