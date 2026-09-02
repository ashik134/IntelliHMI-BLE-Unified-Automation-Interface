import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';

Future<SecretKey> _testKey() => AesGcm.with256bits().newSecretKey();

OperatorProfile _profile(
  String id, {
  OperatorRole role = OperatorRole.operator,
  String? employeeId,
}) {
  final now = DateTime.now();
  return OperatorProfile(
    operatorId: id,
    name: 'Test Operator $id',
    employeeId: employeeId ?? 'EMP-$id',
    role: role,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('operator_repo_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('round-trips add/update/enable/delete; file is not plaintext', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);

    await repo.add(_profile('OP-1', role: OperatorRole.engineer));
    await repo.add(_profile('OP-2'));

    // The store is raw encrypted bytes, not text — decode leniently
    // (replacement chars for invalid sequences) purely to prove the
    // plaintext isn't sitting there recoverable, without asserting an
    // encoding the file was never meant to have.
    final rawBytes = await File('${tempDir.path}/operators.db.enc').readAsBytes();
    final raw = utf8.decode(rawBytes, allowMalformed: true);
    expect(raw.contains('Test Operator'), isFalse);
    expect(raw.contains('OP-1'), isFalse);

    var all = await repo.getAll();
    expect(all, hasLength(2));

    final renamed = (await repo.getById('OP-1'))!.copyWith(name: 'Renamed');
    await repo.update(renamed);
    expect((await repo.getById('OP-1'))!.name, 'Renamed');

    await repo.setEnabled('OP-2', false);
    expect((await repo.getById('OP-2'))!.enabled, isFalse);

    await repo.delete('OP-1');
    all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.operatorId, 'OP-2');
  });

  test(
    'faceTemplateId and lastAuthenticatedAt are absent until set',
    () async {
      final key = await _testKey();
      final repo = OperatorRepository(baseDirectory: tempDir, key: key);
      await repo.add(_profile('OP-1'));

      final stored = await repo.getById('OP-1');
      expect(stored!.faceTemplateId, isNull);
      expect(stored.lastAuthenticatedAt, isNull);
    },
  );

  test('a corrupted (but existing) file fails closed by throwing', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    await repo.add(_profile('OP-1'));

    final file = File('${tempDir.path}/operators.db.enc');
    final flipped = List<int>.from(await file.readAsBytes());
    flipped[flipped.length - 1] ^= 0xFF;
    await file.writeAsBytes(flipped, flush: true);

    expect(repo.getAll(), throwsA(isA<OperatorStoreCorruptedException>()));
  });

  test('a missing file is treated as empty, not corrupted', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    expect(await repo.getAll(), isEmpty);
  });

  test('an atomic write leaves no leftover .tmp file', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    await repo.add(_profile('OP-1'));
    expect(File('${tempDir.path}/operators.db.enc.tmp').existsSync(), isFalse);
  });

  test('add() rejects a duplicate employeeId', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    await repo.add(_profile('OP-1', employeeId: 'EMP-100'));

    expect(
      repo.add(_profile('OP-2', employeeId: 'EMP-100')),
      throwsA(isA<DuplicateEmployeeIdException>()),
    );
    final all = await repo.getAll();
    expect(all, hasLength(1));
  });

  test('add() rejects a duplicate employeeId case/whitespace-insensitively', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    await repo.add(_profile('OP-1', employeeId: 'emp-100'));

    expect(
      repo.add(_profile('OP-2', employeeId: '  EMP-100  ')),
      throwsA(isA<DuplicateEmployeeIdException>()),
    );
  });

  test('add() allows a distinct employeeId after a rejected duplicate', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);
    await repo.add(_profile('OP-1', employeeId: 'EMP-100'));

    await expectLater(
      repo.add(_profile('OP-2', employeeId: 'EMP-100')),
      throwsA(isA<DuplicateEmployeeIdException>()),
    );
    await repo.add(_profile('OP-3', employeeId: 'EMP-200'));

    final all = await repo.getAll();
    expect(all.map((o) => o.operatorId).toSet(), {'OP-1', 'OP-3'});
  });

  test('concurrent mutations serialize instead of racing', () async {
    final key = await _testKey();
    final repo = OperatorRepository(baseDirectory: tempDir, key: key);

    await Future.wait([for (var i = 0; i < 10; i++) repo.add(_profile('OP-$i'))]);

    final all = await repo.getAll();
    expect(all.map((o) => o.operatorId).toSet(), {
      for (var i = 0; i < 10; i++) 'OP-$i',
    });
  });
}
