import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefsKeyEmail, email);
    await prefs.setString(AppConstants.prefsKeyPassword, password);
  }

  Future<String?> getEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefsKeyEmail);
  }

  Future<String?> getPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(AppConstants.prefsKeyPassword);
  }

  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefsKeyEmail);
    await prefs.remove(AppConstants.prefsKeyPassword);
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
