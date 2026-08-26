import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  /// SharedPreferences is intentionally limited to the non-secret operator
  /// email. Passwords belong in SecureCredentialStore only.
  Future<void> saveOperatorEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefsKeyEmail, email);
  }

  Future<String?> getOperatorEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefsKeyEmail);
  }

  Future<void> clearOperatorEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(AppConstants.prefsKeyEmail),
      prefs.remove(AppConstants.legacyPrefsKeyPassword),
    ]);
  }

  /// Removes plaintext passwords written by older app versions while leaving
  /// the remembered, non-secret email intact.
  Future<void> clearLegacyPassword() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.legacyPrefsKeyPassword);
  }

  Future<void> saveLastDeviceId(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefsKeyDeviceId, deviceId);
  }

  Future<String?> getLastDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefsKeyDeviceId);
  }
}
