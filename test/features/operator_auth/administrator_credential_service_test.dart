import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/administrator_credential_service.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/secure_key_value_store.dart';

void main() {
  test('commissioning persists a salted verifier and never the credential', () async {
    final store = _MemorySecureStore();
    final service = AdministratorCredentialService(
      store: store,
      iterations: 1000,
    );

    await service.commission('67483921');

    expect(await service.isCommissioned, isTrue);
    final persisted = store.values.values.single;
    expect(persisted, isNot(contains('67483921')));
    final record = jsonDecode(persisted) as Map<String, dynamic>;
    expect(record['kdf'], 'PBKDF2-HMAC-SHA256');
    expect(base64Decode(record['salt'] as String), hasLength(32));
    expect(base64Decode(record['verifier'] as String), hasLength(32));
  });

  test('verification accepts only the commissioned local credential', () async {
    final service = AdministratorCredentialService(
      store: _MemorySecureStore(),
      iterations: 1000,
    );
    await service.commission('commissioning-password');

    final rejected = await service.verify('not-the-password');
    final accepted = await service.verify('commissioning-password');

    expect(
      rejected.status,
      AdministratorVerificationStatus.invalidCredential,
    );
    expect(accepted.status, AdministratorVerificationStatus.success);
  });

  test('commissioning cannot silently overwrite an existing verifier', () async {
    final service = AdministratorCredentialService(
      store: _MemorySecureStore(),
      iterations: 1000,
    );
    await service.commission('first-password');

    await expectLater(
      service.commission('second-password'),
      throwsA(isA<AdministratorCredentialException>()),
    );
    expect((await service.verify('first-password')).isSuccess, isTrue);
  });

  test('credential policy supports six digit PINs and strong passwords', () {
    expect(AdministratorCredentialService.validateCredential('12345'), isNotNull);
    expect(AdministratorCredentialService.validateCredential('123456'), isNull);
    expect(AdministratorCredentialService.validateCredential('shortpass'), isNotNull);
    expect(
      AdministratorCredentialService.validateCredential('long-password'),
      isNull,
    );
  });
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
