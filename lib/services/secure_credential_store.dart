import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for PLC credentials cached to support a silent sign-in —
/// either the OS-biometric login shortcut, or the automatic PLC reauth that
/// follows a successful Face Verification on an already-configured device.
///
/// Keyed per PLC MAC ID: a credential cached for one device must never be
/// replayed against a different one, so every entry is scoped by [macId]
/// rather than shared globally across every PLC this tablet has connected
/// to.
class SecureCredentialStore {
  SecureCredentialStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _kEmailPrefix = 'bio_op_email_v1::';
  static const String _kPasswordPrefix = 'bio_op_password_v1::';
  static const String _kEnrolledPrefix = 'bio_enrolled_v1::';

  static String _emailKey(String macId) => '$_kEmailPrefix$macId';
  static String _passwordKey(String macId) => '$_kPasswordPrefix$macId';
  static String _enrolledKey(String macId) => '$_kEnrolledPrefix$macId';

  // ── Enrollment state ──────────────────────────────────────────────────────

  static Future<bool> hasCredentials(String macId) async {
    try {
      final enrolled = await _storage.read(key: _enrolledKey(macId));
      final email = await _storage.read(key: _emailKey(macId));
      final password = await _storage.read(key: _passwordKey(macId));

      final isComplete =
          enrolled == 'true' &&
          email != null &&
          email.isNotEmpty &&
          password != null &&
          password.isNotEmpty;
      final hasAnyStoredValue =
          enrolled != null || email != null || password != null;
      if (!isComplete && hasAnyStoredValue) {
        await clearCredentials(macId);
      }
      return isComplete;
    } catch (_) {
      return false;
    }
  }

  //  Write

  static Future<void> storeCredentials({
    required String macId,
    required String email,
    required String password,
  }) async {
    try {
      await _storage.write(key: _emailKey(macId), value: email);
      await _storage.write(key: _passwordKey(macId), value: password);
      await _storage.write(key: _enrolledKey(macId), value: 'true');
    } catch (_) {
      await clearCredentials(macId);
      rethrow;
    }
  }

  // Read

  static Future<({String email, String password})?> retrieveCredentials(
    String macId,
  ) async {
    try {
      final enrolled = await _storage.read(key: _enrolledKey(macId));
      final email = await _storage.read(key: _emailKey(macId));
      final password = await _storage.read(key: _passwordKey(macId));

      if (enrolled != 'true' ||
          email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        await clearCredentials(macId);
        return null;
      }

      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  //  Revocation

  static Future<void> clearCredentials(String macId) async {
    try {
      await Future.wait([
        _storage.delete(key: _emailKey(macId)),
        _storage.delete(key: _passwordKey(macId)),
        _storage.delete(key: _enrolledKey(macId)),
      ]);
    } catch (_) {
      //next successful login will overwrite any stale data.
    }
  }
}
