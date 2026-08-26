import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/services/encrypted_store_codec.dart';

/// Result of reading the log file: the records that decoded cleanly, plus
/// whether a trailing record had to be discarded (crash-truncated write, or
/// tampering) — each record's own GCM tag is what proves it intact, not its
/// position in the file, so decoding stops at the first bad line and
/// everything before it is still trustworthy.
typedef AuthLogReadResult = ({List<AuthLogEntry> entries, bool truncated});

/// Encrypted, append-only local store for [AuthLogEntry] records.
///
/// This is the seam a future, explicitly-permitted PLC log-export feature
/// would read from (see spec section 19) — no such transmission exists yet.
/// Never stores face images, embeddings, or other biometric payloads.
class AuthenticationLogRepository {
  AuthenticationLogRepository({
    required Directory baseDirectory,
    required SecretKey key,
  }) : _baseDirectory = baseDirectory,
       _key = key;

  final Directory _baseDirectory;
  final SecretKey _key;

  File get _file => File('${_baseDirectory.path}/auth_log.enc');

  Future<AuthLogReadResult> readAll() async {
    final file = _file;
    if (!await file.exists()) {
      return (entries: <AuthLogEntry>[], truncated: false);
    }

    final lines = await file.readAsLines();
    final entries = <AuthLogEntry>[];
    var truncated = false;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final decoded = await _decodeLine(line);
      if (decoded == null) {
        truncated = true;
        break;
      }
      entries.add(decoded);
    }

    return (entries: entries, truncated: truncated);
  }

  Future<AuthLogEntry?> _decodeLine(String line) async {
    List<int> envelope;
    try {
      envelope = base64Decode(line.trim());
    } catch (_) {
      return null;
    }

    final plaintext = await EncryptedStoreCodec.decode(_key, envelope);
    if (plaintext == null) return null;

    try {
      final json = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      return AuthLogEntry.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Encrypts [entry] with a fresh nonce and appends one line to the log.
  Future<void> append(AuthLogEntry entry) async {
    final file = _file;
    await file.parent.create(recursive: true);

    final line = await _encodeLine(entry);
    final sink = file.openWrite(mode: FileMode.append);
    try {
      sink.writeln(line);
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  /// Atomically rewrites the file to contain exactly [entries], in order.
  /// Used only for retention/compaction — never for a single logical
  /// append — via a temp-file-then-rename so a crash mid-write leaves
  /// either the complete old file or the complete new one.
  Future<void> rewrite(List<AuthLogEntry> entries) async {
    final file = _file;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');

    final sink = tmp.openWrite();
    try {
      for (final entry in entries) {
        sink.writeln(await _encodeLine(entry));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    await tmp.rename(file.path);
  }

  Future<String> _encodeLine(AuthLogEntry entry) async {
    final plaintext = utf8.encode(jsonEncode(entry.toJson()));
    final envelope = await EncryptedStoreCodec.encode(_key, plaintext);
    return base64Encode(envelope);
  }

  Future<int> sizeBytes() async {
    final file = _file;
    if (!await file.exists()) return 0;
    return file.length();
  }
}
