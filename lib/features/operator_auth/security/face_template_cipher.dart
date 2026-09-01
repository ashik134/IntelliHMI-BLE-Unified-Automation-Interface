import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/secure_key_value_store.dart';
import 'package:uuid/uuid.dart';

class EncryptedFaceTemplate {
  const EncryptedFaceTemplate({
    required this.keyReference,
    required this.cipherText,
    required this.nonce,
    required this.mac,
    required this.algorithm,
    required this.schemaVersion,
  });

  final String keyReference;
  final List<int> cipherText;
  final List<int> nonce;
  final List<int> mac;
  final String algorithm;
  final int schemaVersion;
}

/// AES-256-GCM template encryption using an independently generated data key
/// per enrollment. Data keys are stored under a face-only Keystore namespace;
/// deleting one key provides cryptographic erasure for that template.
class FaceTemplateCipher {
  FaceTemplateCipher({
    SecureKeyValueStore? keyStore,
    Uuid? uuid,
  }) : _keyStore = keyStore ?? const FaceTemplateKeyStore(),
       _uuid = uuid ?? const Uuid();

  static const String algorithmName = 'AES-256-GCM';
  static const int schemaVersion = 1;
  static const String _keyPrefix = 'face_template_data_key_v1_';

  final SecureKeyValueStore _keyStore;
  final Uuid _uuid;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<EncryptedFaceTemplate> encrypt({
    required List<int> templateBytes,
    required String templateMethod,
  }) async {
    if (templateBytes.isEmpty) {
      throw ArgumentError.value(
        templateBytes,
        'templateBytes',
        'A biometric template cannot be empty',
      );
    }

    final keyReference = _uuid.v4();
    final secretKey = await _cipher.newSecretKey();
    final keyBytes = List<int>.of(await secretKey.extractBytes());
    await _keyStore.write('$_keyPrefix$keyReference', base64Encode(keyBytes));

    try {
      final nonce = _cipher.newNonce();
      final secretBox = await _cipher.encrypt(
        templateBytes,
        secretKey: secretKey,
        nonce: nonce,
        aad: _aad(keyReference, templateMethod),
      );
      return EncryptedFaceTemplate(
        keyReference: keyReference,
        cipherText: secretBox.cipherText,
        nonce: secretBox.nonce,
        mac: secretBox.mac.bytes,
        algorithm: algorithmName,
        schemaVersion: schemaVersion,
      );
    } catch (_) {
      await _keyStore.delete('$_keyPrefix$keyReference');
      rethrow;
    } finally {
      if (secretKey is SecretKeyData) secretKey.destroy();
      for (var index = 0; index < keyBytes.length; index += 1) {
        keyBytes[index] = 0;
      }
    }
  }

  Future<List<int>> decrypt({
    required EncryptedFaceTemplate encrypted,
    required String templateMethod,
  }) async {
    if (encrypted.algorithm != algorithmName ||
        encrypted.schemaVersion != schemaVersion) {
      throw StateError('Unsupported face-template encryption format.');
    }
    final encodedKey = await _keyStore.read(
      '$_keyPrefix${encrypted.keyReference}',
    );
    if (encodedKey == null) {
      throw StateError('Face-template encryption key is unavailable.');
    }

    final keyBytes = base64Decode(encodedKey);
    final secretKey = SecretKeyData(
      keyBytes,
      overwriteWhenDestroyed: true,
      debugLabel: 'face-template-data-key',
    );
    try {
      return await _cipher.decrypt(
        SecretBox(
          encrypted.cipherText,
          nonce: encrypted.nonce,
          mac: Mac(encrypted.mac),
        ),
        secretKey: secretKey,
        aad: _aad(encrypted.keyReference, templateMethod),
      );
    } finally {
      secretKey.destroy();
    }
  }

  Future<void> destroyKey(String keyReference) =>
      _keyStore.delete('$_keyPrefix$keyReference');

  List<int> _aad(String keyReference, String templateMethod) => utf8.encode(
    'intellihmi-face-template|$schemaVersion|$templateMethod|$keyReference',
  );
}
