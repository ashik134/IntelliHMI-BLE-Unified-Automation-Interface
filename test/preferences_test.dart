import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPreferences operator email persistence', () {
    test('defaults to no remembered operator email', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = AppPreferences();

      expect(await preferences.getOperatorEmail(), isNull);
    });

    test('stores only the operator email', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = AppPreferences();

      await preferences.saveOperatorEmail('operator@company.com');

      final values = await SharedPreferences.getInstance();
      expect(
        values.getString(AppConstants.prefsKeyEmail),
        'operator@company.com',
      );
      expect(values.containsKey(AppConstants.legacyPrefsKeyPassword), isFalse);
    });

    test('legacy cleanup removes password but preserves email', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefsKeyEmail: 'operator@company.com',
        AppConstants.legacyPrefsKeyPassword: 'plaintext-password',
      });
      final preferences = AppPreferences();

      await preferences.clearLegacyPassword();

      final values = await SharedPreferences.getInstance();
      expect(
        values.getString(AppConstants.prefsKeyEmail),
        'operator@company.com',
      );
      expect(values.containsKey(AppConstants.legacyPrefsKeyPassword), isFalse);
    });

    test('turning remembrance off can clear the operator email', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefsKeyEmail: 'operator@company.com',
      });
      final preferences = AppPreferences();

      await preferences.clearOperatorEmail();

      expect(await preferences.getOperatorEmail(), isNull);
    });
  });
}
