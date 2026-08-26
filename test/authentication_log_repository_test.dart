import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/repositories/authentication_log_repository.dart';
import 'package:rev_crane_control_ops/services/encrypted_store_codec.dart';

Future<SecretKey> _testKey() => AesGcm.with256bits().newSecretKey();

AuthLogEntry _entry({
  AuthEventResult result = AuthEventResult.success,
  DateTime? timestamp,
}) {
  return AuthLogEntry(
    timestamp: timestamp ?? DateTime.now(),
    category: AuthLogCategory.authentication,
    result: result,
    method: AuthEventMethod.password,
    userIdentifier: 'operator@intellihmi.test',
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('auth_log_repo_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('round-trips entries and the file on disk is not plaintext', () async {
    final key = await _testKey();
    final repo = AuthenticationLogRepository(baseDirectory: tempDir, key: key);

    await repo.append(_entry());

    final raw = await File('${tempDir.path}/auth_log.enc').readAsString();
    expect(raw.contains('operator@intellihmi.test'), isFalse);

    final result = await repo.readAll();
    expect(result.entries, hasLength(1));
    expect(result.entries.single.userIdentifier, 'operator@intellihmi.test');
    expect(result.truncated, isFalse);
  });

  test(
    'two records under the same key produce different ciphertext lines',
    () async {
      final key = await _testKey();
      final repo = AuthenticationLogRepository(
        baseDirectory: tempDir,
        key: key,
      );

      await repo.append(_entry());
      await repo.append(_entry());

      final lines = await File(
        '${tempDir.path}/auth_log.enc',
      ).readAsLines();
      expect(lines, hasLength(2));
      expect(lines[0], isNot(equals(lines[1])));
    },
  );

  test(
    'a crash-truncated trailing record is dropped, prior entries survive',
    () async {
      final key = await _testKey();
      final repo = AuthenticationLogRepository(
        baseDirectory: tempDir,
        key: key,
      );

      await repo.append(_entry(result: AuthEventResult.success));
      await repo.append(_entry(result: AuthEventResult.failed));

      final file = File('${tempDir.path}/auth_log.enc');
      final bytes = await file.readAsBytes();
      final firstNewline = bytes.indexOf(10); // '\n'
      // Keep all of line 1 plus a few bytes of line 2 — simulates a crash
      // mid-write, before line 2's own GCM tag was fully flushed.
      final truncated = bytes.sublist(0, firstNewline + 6);
      await file.writeAsBytes(truncated, flush: true);

      final result = await repo.readAll();
      expect(result.entries, hasLength(1));
      expect(result.entries.single.result, AuthEventResult.success);
      expect(result.truncated, isTrue);
    },
  );

  test('rewrite atomically replaces the file, no leftover .tmp', () async {
    final key = await _testKey();
    final repo = AuthenticationLogRepository(baseDirectory: tempDir, key: key);

    await repo.append(_entry());
    await repo.append(_entry());
    await repo.append(_entry());

    final all = await repo.readAll();
    await repo.rewrite(all.entries.sublist(1));

    final result = await repo.readAll();
    expect(result.entries, hasLength(2));
    expect(File('${tempDir.path}/auth_log.enc.tmp').existsSync(), isFalse);
  });

  group('EncryptedStoreCodec', () {
    test('decode fails closed (returns null) on tampered ciphertext', () async {
      final key = await _testKey();
      final wrongKey = await _testKey();
      final plaintext = 'not real json'.codeUnits;
      final envelope = await EncryptedStoreCodec.encode(key, plaintext);

      expect(await EncryptedStoreCodec.decode(key, envelope), plaintext);
      expect(await EncryptedStoreCodec.decode(wrongKey, envelope), isNull);

      final flipped = List<int>.from(envelope);
      flipped[flipped.length - 1] ^= 0xFF;
      expect(await EncryptedStoreCodec.decode(key, flipped), isNull);
    });

    test('decode fails closed on a truncated envelope', () async {
      final key = await _testKey();
      final envelope = await EncryptedStoreCodec.encode(key, [1, 2, 3]);
      expect(
        await EncryptedStoreCodec.decode(key, envelope.sublist(0, 5)),
        isNull,
      );
    });
  });
}
