import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/services/encrypted_store_codec.dart';
import 'package:rev_crane_control_ops/services/secure_key_provider.dart';

const String _kFaceTemplateKeyDomain = 'intellihmi.face-template.key';

/// Thrown when the template store file exists but cannot be decrypted —
/// same fail-closed reasoning as [OperatorStoreCorruptedException]: a
/// corrupted store must never be silently treated as "no templates."
class FaceTemplateStoreCorruptedException implements Exception {
  const FaceTemplateStoreCorruptedException();

  @override
  String toString() =>
      'FaceTemplateStoreCorruptedException: the face template store file '
      'exists but failed to decrypt/parse — refusing to treat it as empty.';
}

/// Encrypted local CRUD store for [FaceTemplate]s — the permanent
/// biometric credential (spec sections 10-11). Same shape as
/// `OperatorRepository`: single JSON-array document, atomic temp-then-
/// rename write, its own domain key (`intellihmi.face-template.key`,
/// reserved since Stage 1 — never the operator-store or audit-log key).
///
/// Deleting an operator (or re-enrolling their face) must delete their
/// prior template here too — this repository only stores templates, it
/// doesn't know when an operator is deleted, so the caller (Stage 4's
/// enrollment flow, and Stage 2's `OperatorDetailScreen._confirmDelete`)
/// is responsible for calling [deleteByOperatorId].
class FaceTemplateRepository {
  FaceTemplateRepository({
    required Directory baseDirectory,
    required SecretKey key,
  }) : _baseDirectory = baseDirectory,
       _key = key;

  static Future<FaceTemplateRepository> open() async {
    final directory = await getApplicationSupportDirectory();
    final key = await SecureKeyProvider.getOrCreateKey(
      _kFaceTemplateKeyDomain,
    );
    return FaceTemplateRepository(baseDirectory: directory, key: key);
  }

  final Directory _baseDirectory;
  final SecretKey _key;

  Future<void> _writeQueue = Future.value();

  File get _file => File('${_baseDirectory.path}/face_templates.db.enc');

  Future<List<FaceTemplate>> _readAll() async {
    final file = _file;
    if (!await file.exists()) return const [];

    final bytes = await file.readAsBytes();
    final plaintext = await EncryptedStoreCodec.decode(_key, bytes);
    if (plaintext == null) {
      throw const FaceTemplateStoreCorruptedException();
    }

    final decoded = jsonDecode(utf8.decode(plaintext)) as List<dynamic>;
    return decoded
        .map((e) => FaceTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _writeAll(List<FaceTemplate> templates) async {
    final file = _file;
    await file.parent.create(recursive: true);

    final plaintext = utf8.encode(
      jsonEncode(templates.map((t) => t.toJson()).toList()),
    );
    final envelope = await EncryptedStoreCodec.encode(_key, plaintext);

    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(envelope, flush: true);
    await tmp.rename(file.path);
  }

  Future<void> _mutate(
    Future<void> Function(List<FaceTemplate> current) action,
  ) {
    final result = _writeQueue.then((_) async {
      final current = await _readAll();
      await action(current);
    });
    _writeQueue = result.catchError((_) {});
    return result;
  }

  Future<List<FaceTemplate>> getAll() => _readAll();

  Future<FaceTemplate?> getByOperatorId(String operatorId) async {
    final all = await _readAll();
    for (final template in all) {
      if (template.operatorId == operatorId) return template;
    }
    return null;
  }

  /// Replaces any existing template for [template.operatorId] — an
  /// operator has at most one active template; re-enrollment supersedes
  /// the prior one rather than accumulating history.
  Future<void> upsert(FaceTemplate template) {
    return _mutate((current) async {
      final updated = [
        for (final existing in current)
          if (existing.operatorId != template.operatorId) existing,
        template,
      ];
      await _writeAll(updated);
    });
  }

  Future<void> deleteByOperatorId(String operatorId) {
    return _mutate((current) async {
      final updated = current
          .where((t) => t.operatorId != operatorId)
          .toList();
      await _writeAll(updated);
    });
  }

  /// This repository's directory path and raw key bytes — everything
  /// needed to reconstruct an equivalent [FaceTemplateRepository] on
  /// another isolate (see `FaceEnrollmentWorker`). This repository
  /// *instance* is deliberately not sent across an isolate boundary
  /// itself: [_writeQueue] holds a [Future] bound to this isolate's event
  /// loop, which isn't sendable, so the receiving isolate must build its
  /// own instance from these plain values instead.
  Future<({String directoryPath, List<int> keyBytes})>
  exportForIsolateTransfer() async {
    return (directoryPath: _baseDirectory.path, keyBytes: await _key.extractBytes());
  }
}
