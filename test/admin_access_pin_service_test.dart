import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/services/admin_access_pin_service.dart';

// AdminAccessPinService reads/writes via a hardcoded FlutterSecureStorage
// instance (matching the existing SecureCredentialStore/DeviceIdentityService
// style, neither of which has a test seam either) — real platform channel
// calls throw MissingPluginException in a plain widget test with no
// device/emulator behind it, so this file provides an in-memory mock for
// the `plugins.it_nomads.com/flutter_secure_storage` channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = <String, String>{};
  const channel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );

  setUp(() async {
    storage.clear();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'read':
              return storage[call.arguments['key'] as String];
            case 'write':
              storage[call.arguments['key'] as String] =
                  call.arguments['value'] as String;
              return null;
            case 'delete':
              storage.remove(call.arguments['key'] as String);
              return null;
            case 'containsKey':
              return storage.containsKey(call.arguments['key'] as String);
            case 'deleteAll':
              storage.clear();
              return null;
            case 'readAll':
              return storage;
            default:
              return null;
          }
        });
    await AdminAccessPinService.resetForTesting();
  });

  test('isSet() is false until a PIN is created', () async {
    expect(await AdminAccessPinService.isSet(), isFalse);
    await AdminAccessPinService.setPin('123456');
    expect(await AdminAccessPinService.isSet(), isTrue);
  });

  test('rejects PINs shorter than the minimum or non-numeric', () async {
    expect(AdminAccessPinService.isValidPinFormat('12345'), isFalse);
    expect(AdminAccessPinService.isValidPinFormat('12a456'), isFalse);
    expect(AdminAccessPinService.isValidPinFormat('123456'), isTrue);
    expect(
      () => AdminAccessPinService.setPin('123'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('verify() succeeds for the correct PIN, fails for the wrong one', () async {
    await AdminAccessPinService.setPin('654321');
    expect(
      await AdminAccessPinService.verify('654321'),
      AdminPinVerifyResult.success,
    );
    expect(
      await AdminAccessPinService.verify('000000'),
      AdminPinVerifyResult.incorrect,
    );
  });

  test('the stored value is a hash, not the PIN itself', () async {
    await AdminAccessPinService.setPin('111222');
    final stored = storage.values.join(' ');
    expect(stored.contains('111222'), isFalse);
  });

  test('locks out after 5 consecutive wrong attempts', () async {
    await AdminAccessPinService.setPin('999999');

    for (var i = 0; i < 4; i++) {
      expect(
        await AdminAccessPinService.verify('000000'),
        AdminPinVerifyResult.incorrect,
        reason: 'attempt ${i + 1}',
      );
    }
    // 5th wrong attempt trips the lockout and reports it immediately.
    expect(
      await AdminAccessPinService.verify('000000'),
      AdminPinVerifyResult.lockedOut,
    );
    // Even the correct PIN is refused while locked out.
    expect(
      await AdminAccessPinService.verify('999999'),
      AdminPinVerifyResult.lockedOut,
    );
    expect(await AdminAccessPinService.remainingLockoutSeconds(), greaterThan(0));
  });

  test('unlocks again once the lockout window has passed', () async {
    await AdminAccessPinService.setPin('999999');
    for (var i = 0; i < 5; i++) {
      await AdminAccessPinService.verify('000000');
    }
    expect(await AdminAccessPinService.remainingLockoutSeconds(), greaterThan(0));

    // Simulate the lockout window having already elapsed.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'admin_access_pin_locked_until_epoch_ms',
      DateTime.now().subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );

    expect(await AdminAccessPinService.remainingLockoutSeconds(), 0);
    expect(
      await AdminAccessPinService.verify('999999'),
      AdminPinVerifyResult.success,
    );
  });

  test('a successful verify clears prior failed-attempt count', () async {
    await AdminAccessPinService.setPin('555555');
    await AdminAccessPinService.verify('000000');
    await AdminAccessPinService.verify('000000');
    expect(await AdminAccessPinService.failedAttemptCount(), 2);

    await AdminAccessPinService.verify('555555');
    expect(await AdminAccessPinService.failedAttemptCount(), 0);
  });

  test('changePin requires the current PIN', () async {
    await AdminAccessPinService.setPin('111111');

    await expectLater(
      AdminAccessPinService.changePin(
        currentPin: '222222',
        newPin: '333333',
      ),
      throwsA(isA<StateError>()),
    );
    expect(
      await AdminAccessPinService.verify('111111'),
      AdminPinVerifyResult.success,
    );

    await AdminAccessPinService.changePin(
      currentPin: '111111',
      newPin: '333333',
    );
    expect(
      await AdminAccessPinService.verify('333333'),
      AdminPinVerifyResult.success,
    );
  });
}
