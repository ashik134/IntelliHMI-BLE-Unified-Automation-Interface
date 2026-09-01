import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_database.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/face_template_cipher.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/secure_key_value_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late OperatorDatabase database;
  late OperatorRepository repository;
  late _MemorySecureStore keyStore;

  setUp(() async {
    sqfliteFfiInit();
    final rawDatabase = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    await OperatorDatabase.createSchemaForTesting(rawDatabase);
    database = OperatorDatabase(opener: () async => rawDatabase);
    keyStore = _MemorySecureStore();
    repository = OperatorRepository(
      database: database,
      cipher: FaceTemplateCipher(keyStore: keyStore),
      now: () => DateTime.utc(2026, 8, 31, 12),
    );
  });

  tearDown(() => database.close());

  test('operator and mandatory encrypted template commit together', () async {
    final operator = await repository.createOperator(
      input: const OperatorInput(
        employeeId: 'EMP-001',
        name: 'Ada Operator',
        role: OperatorAccessLevel.operator,
      ),
      templateBytes: const [4, 8, 15, 16, 23, 42],
      templateMethod: '3divi-face-template-extractor-30',
    );

    final operators = await repository.listOperators();
    final authenticatable = await repository.loadAuthenticatableTemplates();
    final stored = await database.templateForOperator(operator.id);

    expect(operators, hasLength(1));
    expect(authenticatable.single.templateBytes, [4, 8, 15, 16, 23, 42]);
    expect(stored!.encrypted.cipherText, isNot([4, 8, 15, 16, 23, 42]));
    expect(keyStore.values, hasLength(1));
  });

  test('database enforces normalized Employee ID uniqueness', () async {
    await repository.createOperator(
      input: const OperatorInput(
        employeeId: 'emp-007',
        name: 'First Operator',
        role: OperatorAccessLevel.operator,
      ),
      templateBytes: const [1, 2, 3],
      templateMethod: 'method-30',
    );

    await expectLater(
      repository.createOperator(
        input: const OperatorInput(
          employeeId: ' EMP-007 ',
          name: 'Second Operator',
          role: OperatorAccessLevel.supervisor,
        ),
        templateBytes: const [9, 8, 7],
        templateMethod: 'method-30',
      ),
      throwsA(isA<DuplicateEmployeeIdException>()),
    );

    expect(await repository.listOperators(), hasLength(1));
    expect(keyStore.values, hasLength(1));
    final audit = await database.listAuditEvents();
    expect(
      audit.any(
        (event) =>
            event.type ==
            OperatorAuditEventType.duplicateEmployeeIdRejected,
      ),
      isTrue,
    );
  });

  test('deletion removes authentication data key and keeps audit snapshot', () async {
    final operator = await repository.createOperator(
      input: const OperatorInput(
        employeeId: 'EMP-009',
        name: 'Deleted Operator',
        role: OperatorAccessLevel.maintenance,
      ),
      templateBytes: const [3, 1, 4, 1, 5],
      templateMethod: 'method-30',
    );
    expect(keyStore.values, hasLength(1));

    await repository.deleteOperator(operator);

    expect(await repository.listOperators(), isEmpty);
    expect(await repository.loadAuthenticatableTemplates(), isEmpty);
    expect(keyStore.values, isEmpty);
    final audit = await database.listAuditEvents();
    final deletion = audit.firstWhere(
      (event) => event.type == OperatorAuditEventType.operatorDeleted,
    );
    expect(deletion.employeeIdSnapshot, 'EMP-009');
    expect(deletion.operatorNameSnapshot, 'Deleted Operator');
  });

  test('re-enrollment swaps data keys only after database replacement', () async {
    final operator = await repository.createOperator(
      input: const OperatorInput(
        employeeId: 'EMP-010',
        name: 'Reenrolled Operator',
        role: OperatorAccessLevel.operator,
      ),
      templateBytes: const [1, 1, 1],
      templateMethod: 'method-30',
    );
    final oldKey = keyStore.values.keys.single;

    await repository.replaceFaceTemplate(
      operator: operator,
      templateBytes: const [2, 2, 2],
      templateMethod: 'method-30',
    );

    expect(keyStore.values, hasLength(1));
    expect(keyStore.values, isNot(contains(oldKey)));
    expect(
      (await repository.loadAuthenticatableTemplates()).single.templateBytes,
      [2, 2, 2],
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
