import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Keystore-backed storage reserved for administrator authorization data.
///
/// A separate namespace gives it a different Android Keystore alias from PLC
/// credential storage and from face-template encryption keys.
class AdministratorSecureStore implements SecureKeyValueStore {
  const AdministratorSecureStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(storageNamespace: 'intellihmi_admin_auth_v1'),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'intellihmi_admin_auth_v1',
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keystore-backed storage reserved exclusively for face-template data keys.
class FaceTemplateKeyStore implements SecureKeyValueStore {
  const FaceTemplateKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'intellihmi_face_template_keys_v1',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'intellihmi_face_template_keys_v1',
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
