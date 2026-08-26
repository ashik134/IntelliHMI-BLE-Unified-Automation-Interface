import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';

Future<SecretKey> _testKey() => AesGcm.with256bits().newSecretKey();

FaceTemplate _template(String operatorId, {List<double>? embedding}) {
  return FaceTemplate(
    templateId: 'T-$operatorId',
    operatorId: operatorId,
    embedding: embedding ?? List.filled(192, 0.1),
    modelVersion: 'mobilefacenet_v1',
    createdAt: DateTime.now(),
  );
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('face_template_repo_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('round-trips upsert/get/delete; file is not plaintext', () async {
    final key = await _testKey();
    final repo = FaceTemplateRepository(baseDirectory: tempDir, key: key);

    await repo.upsert(_template('OP-1'));
    await repo.upsert(_template('OP-2'));

    final rawBytes = await File(
      '${tempDir.path}/face_templates.db.enc',
    ).readAsBytes();
    final raw = utf8.decode(rawBytes, allowMalformed: true);
    expect(raw.contains('OP-1'), isFalse);

    expect(await repo.getAll(), hasLength(2));
    expect((await repo.getByOperatorId('OP-1'))!.templateId, 'T-OP-1');

    await repo.deleteByOperatorId('OP-1');
    final remaining = await repo.getAll();
    expect(remaining, hasLength(1));
    expect(remaining.single.operatorId, 'OP-2');
  });

  test('upsert replaces a prior template for the same operator', () async {
    final key = await _testKey();
    final repo = FaceTemplateRepository(baseDirectory: tempDir, key: key);

    await repo.upsert(_template('OP-1', embedding: List.filled(192, 0.1)));
    await repo.upsert(_template('OP-1', embedding: List.filled(192, 0.9)));

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.embedding.first, 0.9);
  });

  test('a corrupted (but existing) file fails closed by throwing', () async {
    final key = await _testKey();
    final repo = FaceTemplateRepository(baseDirectory: tempDir, key: key);
    await repo.upsert(_template('OP-1'));

    final file = File('${tempDir.path}/face_templates.db.enc');
    final flipped = List<int>.from(await file.readAsBytes());
    flipped[flipped.length - 1] ^= 0xFF;
    await file.writeAsBytes(flipped, flush: true);

    expect(
      repo.getAll(),
      throwsA(isA<FaceTemplateStoreCorruptedException>()),
    );
  });

  test('a missing file is treated as empty, not corrupted', () async {
    final key = await _testKey();
    final repo = FaceTemplateRepository(baseDirectory: tempDir, key: key);
    expect(await repo.getAll(), isEmpty);
  });

  test('an atomic write leaves no leftover .tmp file', () async {
    final key = await _testKey();
    final repo = FaceTemplateRepository(baseDirectory: tempDir, key: key);
    await repo.upsert(_template('OP-1'));
    expect(
      File('${tempDir.path}/face_templates.db.enc.tmp').existsSync(),
      isFalse,
    );
  });
}
