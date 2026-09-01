import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/secure_key_value_store.dart';

enum AdministratorVerificationStatus {
  success,
  notCommissioned,
  invalidCredential,
  temporarilyLocked,
}

class AdministratorVerificationResult {
  const AdministratorVerificationResult(
    this.status, {
    this.retryAfter,
  });

  final AdministratorVerificationStatus status;
  final Duration? retryAfter;

  bool get isSuccess => status == AdministratorVerificationStatus.success;
}

class AdministratorCredentialException implements Exception {
  const AdministratorCredentialException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Stores only a salted PBKDF2 verifier for the commissioning-provided local
/// administrator credential. The plaintext credential is never persisted.
class AdministratorCredentialService {
  AdministratorCredentialService({
    SecureKeyValueStore? store,
    DateTime Function()? now,
    int iterations = _defaultIterations,
  }) : _store = store ?? const AdministratorSecureStore(),
       _now = now ?? DateTime.now,
       _iterations = iterations {
    if (iterations < 1000) {
      throw ArgumentError.value(iterations, 'iterations', 'Must be at least 1000');
    }
  }

  static const String _credentialKey = 'admin_credential_verifier_v1';
  static const String _attemptStateKey = 'admin_attempt_state_v1';
  static const int _defaultIterations = 210000;
  static const int _saltLength = 32;
  static const int _verifierLength = 32;
  static const int _failuresBeforeLock = 5;

  final SecureKeyValueStore _store;
  final DateTime Function() _now;
  final int _iterations;

  Future<bool> get isCommissioned async =>
      (await _store.read(_credentialKey)) != null;

  /// One-time provisioning. The caller must expose this only in an explicitly
  /// commissioned deployment build; this method refuses to replace an existing
  /// credential.
  Future<void> commission(String credential) async {
    final validationError = validateCredential(credential);
    if (validationError != null) {
      throw AdministratorCredentialException(validationError);
    }
    if (await isCommissioned) {
      throw const AdministratorCredentialException(
        'Administrator authorization is already commissioned.',
      );
    }

    await _store.write(
      _credentialKey,
      await _buildCredentialRecord(credential),
    );
    await _store.delete(_attemptStateKey);
  }

  Future<AdministratorVerificationResult> verify(String credential) async {
    final rawRecord = await _store.read(_credentialKey);
    if (rawRecord == null) {
      return const AdministratorVerificationResult(
        AdministratorVerificationStatus.notCommissioned,
      );
    }

    final attemptState = await _readAttemptState();
    final now = _now().toUtc();
    if (attemptState.blockedUntil != null &&
        attemptState.blockedUntil!.isAfter(now)) {
      return AdministratorVerificationResult(
        AdministratorVerificationStatus.temporarilyLocked,
        retryAfter: attemptState.blockedUntil!.difference(now),
      );
    }

    try {
      final decoded = jsonDecode(rawRecord) as Map<String, dynamic>;
      final iterations = decoded['iterations'] as int;
      final salt = base64Decode(decoded['salt'] as String);
      final expected = base64Decode(decoded['verifier'] as String);
      final actual = await _deriveVerifierInWorker(
        credential: credential,
        salt: salt,
        iterations: iterations,
        outputBytes: expected.length,
      );

      if (_constantTimeEquals(actual, expected)) {
        await _store.delete(_attemptStateKey);
        return const AdministratorVerificationResult(
          AdministratorVerificationStatus.success,
        );
      }
    } catch (_) {
      // A malformed or inaccessible verifier fails closed.
    }

    final failures = attemptState.failures + 1;
    DateTime? blockedUntil;
    if (failures >= _failuresBeforeLock) {
      final exponent = (failures - _failuresBeforeLock).clamp(0, 5);
      blockedUntil = now.add(Duration(seconds: 30 * (1 << exponent)));
    }
    await _writeAttemptState(
      _AdministratorAttemptState(
        failures: failures,
        blockedUntil: blockedUntil,
      ),
    );

    return AdministratorVerificationResult(
      blockedUntil == null
          ? AdministratorVerificationStatus.invalidCredential
          : AdministratorVerificationStatus.temporarilyLocked,
      retryAfter: blockedUntil?.difference(now),
    );
  }

  Future<void> changeCredential({
    required String currentCredential,
    required String newCredential,
  }) async {
    final result = await verify(currentCredential);
    if (!result.isSuccess) {
      throw const AdministratorCredentialException(
        'Current administrator credential was not accepted.',
      );
    }
    final validationError = validateCredential(newCredential);
    if (validationError != null) {
      throw AdministratorCredentialException(validationError);
    }

    // Secure storage replaces this single value atomically; the current
    // verifier remains valid if generating or writing the replacement fails.
    await _store.write(
      _credentialKey,
      await _buildCredentialRecord(newCredential),
    );
    await _store.delete(_attemptStateKey);
  }

  static String? validateCredential(String credential) {
    if (credential.length > 128) {
      return 'Administrator credential is too long.';
    }
    final isNumericPin = RegExp(r'^\d+$').hasMatch(credential);
    if (isNumericPin && credential.length < 6) {
      return 'Administrator PIN must contain at least 6 digits.';
    }
    if (!isNumericPin && credential.length < 10) {
      return 'Administrator password must contain at least 10 characters.';
    }
    if (credential.trim().isEmpty) {
      return 'Administrator credential is required.';
    }
    return null;
  }

  Future<String> _buildCredentialRecord(String credential) async {
    final saltKey = SecretKeyData.random(length: _saltLength);
    final salt = List<int>.of(await saltKey.extractBytes());
    saltKey.destroy();
    final verifier = await _deriveVerifierInWorker(
      credential: credential,
      salt: salt,
      iterations: _iterations,
      outputBytes: _verifierLength,
    );
    return jsonEncode(<String, Object>{
      'version': 1,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'verifier': base64Encode(verifier),
    });
  }

  Future<_AdministratorAttemptState> _readAttemptState() async {
    try {
      final raw = await _store.read(_attemptStateKey);
      if (raw == null) return const _AdministratorAttemptState();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final blockedRaw = decoded['blockedUntil'] as String?;
      return _AdministratorAttemptState(
        failures: decoded['failures'] as int? ?? 0,
        blockedUntil: blockedRaw == null ? null : DateTime.parse(blockedRaw),
      );
    } catch (_) {
      return const _AdministratorAttemptState();
    }
  }

  Future<void> _writeAttemptState(_AdministratorAttemptState state) =>
      _store.write(
        _attemptStateKey,
        jsonEncode(<String, Object?>{
          'failures': state.failures,
          'blockedUntil': state.blockedUntil?.toIso8601String(),
        }),
      );
}

class _AdministratorAttemptState {
  const _AdministratorAttemptState({this.failures = 0, this.blockedUntil});

  final int failures;
  final DateTime? blockedUntil;
}

Future<List<int>> _deriveVerifierInWorker({
  required String credential,
  required List<int> salt,
  required int iterations,
  required int outputBytes,
}) {
  if (Platform.isAndroid) {
    return _deriveVerifierOnAndroid(
      credential: credential,
      salt: salt,
      iterations: iterations,
      outputBytes: outputBytes,
    );
  }
  return _deriveVerifierInDartIsolate(
    credential: credential,
    salt: salt,
    iterations: iterations,
    outputBytes: outputBytes,
  );
}

Future<List<int>> _deriveVerifierOnAndroid({
  required String credential,
  required List<int> salt,
  required int iterations,
  required int outputBytes,
}) async {
  const channel = MethodChannel('rev_crane_control_ops/security');
  try {
    final result = await channel.invokeMethod<Uint8List>(
      'deriveAdminVerifier',
      <String, Object>{
        'credential': credential,
        'salt': Uint8List.fromList(salt),
        'iterations': iterations,
        'outputBytes': outputBytes,
      },
    );
    if (result == null || result.length != outputBytes) {
      throw StateError('Android credential derivation returned invalid data.');
    }
    return List<int>.of(result);
  } on MissingPluginException {
    return _deriveVerifierInDartIsolate(
      credential: credential,
      salt: salt,
      iterations: iterations,
      outputBytes: outputBytes,
    );
  }
}

Future<List<int>> _deriveVerifierInDartIsolate({
  required String credential,
  required List<int> salt,
  required int iterations,
  required int outputBytes,
}) {
  return Isolate.run(() async {
    final algorithm = Pbkdf2.hmacSha256(
      iterations: iterations,
      bits: outputBytes * 8,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: credential,
      nonce: salt,
    );
    final bytes = List<int>.of(await key.extractBytes());
    if (key is SecretKeyData) key.destroy();
    return bytes;
  });
}

bool _constantTimeEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
