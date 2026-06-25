import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Hardware-backed secure storage for biometric-protected operator credentials.

class SecureCredentialStore {
  SecureCredentialStore._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String _kEmail = 'bio_op_email_v1';
  static const String _kPassword = 'bio_op_password_v1';
  static const String _kEnrolled = 'bio_enrolled_v1';

  // ── Enrollment state ──────────────────────────────────────────────────────

  static Future<bool> hasCredentials() async {
    try {
      final enrolled = await _storage.read(key: _kEnrolled);
      if (enrolled != 'true') return false;

      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);

      return email != null &&
          email.isNotEmpty &&
          password != null &&
          password.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  //  Write

  static Future<void> storeCredentials({
    required String email,
    required String password,
  }) async {
    await _storage.write(key: _kEmail, value: email);
    await _storage.write(key: _kPassword, value: password);
    await _storage.write(key: _kEnrolled, value: 'true');
  }

  // Read

  static Future<({String email, String password})?>
  retrieveCredentials() async {
    try {
      final email = await _storage.read(key: _kEmail);
      final password = await _storage.read(key: _kPassword);

      if (email == null ||
          email.isEmpty ||
          password == null ||
          password.isEmpty) {
        return null;
      }

      return (email: email, password: password);
    } catch (_) {
      return null;
    }
  }

  //  Revocation

  static Future<void> clearCredentials() async {
    try {
      await Future.wait([
        _storage.delete(key: _kEmail),
        _storage.delete(key: _kPassword),
        _storage.delete(key: _kEnrolled),
      ]);
    } catch (_) {
      //next successful login will overwrite any stale data.
    }
  }
}
