import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/services/encrypted_store_codec.dart';
import 'package:rev_crane_control_ops/services/secure_key_provider.dart';

const String _kOperatorStoreKeyDomain = 'intellihmi.operator-store.key';

/// Thrown when the operator store file exists but cannot be decrypted —
/// wrong/rotated key, corruption, or tampering. Deliberately distinct from
/// "no operators yet" (a freshly-created, still-empty store): a future
/// bootstrap flow that crowns the first administrator when the store is
/// empty must never treat an unreadable store as an empty one, or a
/// corrupted file could be used to force a fresh bootstrap.
class OperatorStoreCorruptedException implements Exception {
  const OperatorStoreCorruptedException();

  @override
  String toString() =>
      'OperatorStoreCorruptedException: the operator store file exists but '
      'failed to decrypt/parse — refusing to treat it as empty.';
}

/// Encrypted local CRUD store for the [OperatorProfile] list.
///
/// Unlike the append-only audit log, this is a small, fully-rewritten-on-
/// every-change document: the whole list is one JSON array, encrypted as
/// one envelope, written via a temp-file-then-atomic-rename so a crash
/// mid-write leaves either the complete old file or the complete new one.
/// No face template bytes live here — see spec sections 11/29 and Stage 3.
class OperatorRepository {
  OperatorRepository({
    required Directory baseDirectory,
    required SecretKey key,
  }) : _baseDirectory = baseDirectory,
       _key = key;

  /// Resolves the real on-device app-support directory and the operator
  /// store's domain key, mirroring how `AuthAuditLogService` lazily
  /// resolves its own repository. Call once per screen/session; there's
  /// no need to thread this through `main.dart`'s provider tree yet since
  /// only Operator Management uses it so far.
  static Future<OperatorRepository> open() async {
    final directory = await getApplicationSupportDirectory();
    final key = await SecureKeyProvider.getOrCreateKey(
      _kOperatorStoreKeyDomain,
    );
    return OperatorRepository(baseDirectory: directory, key: key);
  }

  final Directory _baseDirectory;
  final SecretKey _key;

  /// Serializes every mutation so concurrent add/update/delete calls can't
  /// race and clobber each other's read-modify-write.
  Future<void> _writeQueue = Future.value();

  File get _file => File('${_baseDirectory.path}/operators.db.enc');

  Future<List<OperatorProfile>> _readAll() async {
    final file = _file;
    if (!await file.exists()) return const [];

    final bytes = await file.readAsBytes();
    final plaintext = await EncryptedStoreCodec.decode(_key, bytes);
    if (plaintext == null) {
      throw const OperatorStoreCorruptedException();
    }

    final decoded = jsonDecode(utf8.decode(plaintext)) as List<dynamic>;
    return decoded
        .map((e) => OperatorProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAll(List<OperatorProfile> operators) async {
    final file = _file;
    await file.parent.create(recursive: true);

    final plaintext = utf8.encode(
      jsonEncode(operators.map((o) => o.toJson()).toList()),
    );
    final envelope = await EncryptedStoreCodec.encode(_key, plaintext);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(envelope, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _mutate(
    Future<void> Function(List<OperatorProfile> current) action,
  ) {
    final result = _writeQueue.then((_) async {
      final current = await _readAll();
      await action(current);
    });
    // Keep the queue alive even if this mutation fails, so a later call
    // isn't stuck behind a permanently-rejected future — the failure
    // itself is still surfaced to the caller via the returned `result`.
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<List<OperatorProfile>> getAll() => _readAll();

  Future<OperatorProfile?> getById(String operatorId) async {
    final all = await _readAll();
    for (final operator in all) {
      if (operator.operatorId == operatorId) return operator;
    }
    return null;
  }

  Future<void> add(OperatorProfile operator) {
    return _mutate((current) async {
      await _writeAll([...current, operator]);
    });
  }

  Future<void> update(OperatorProfile operator) {
    return _mutate((current) async {
      final updated = [
        for (final existing in current)
          existing.operatorId == operator.operatorId ? operator : existing,
      ];
      await _writeAll(updated);
    });
  }

  Future<void> setEnabled(String operatorId, bool enabled) {
    return _mutate((current) async {
      final updated = [
        for (final existing in current)
          existing.operatorId == operatorId
              ? existing.copyWith(enabled: enabled, updatedAt: DateTime.now())
              : existing,
      ];
      await _writeAll(updated);
    });
  }

  /// Removes the operator's profile record. Any associated face template
  /// (Stage 3) must be deleted by the caller from the template store too —
  /// this repository only ever holds profile metadata, never the template.
  Future<void> delete(String operatorId) {
    return _mutate((current) async {
      final updated = current
          .where((existing) => existing.operatorId != operatorId)
          .toList();
      await _writeAll(updated);
    });
  }
}
