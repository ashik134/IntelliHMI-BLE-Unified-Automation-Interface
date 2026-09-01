import 'package:path/path.dart' as path;
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/face_template_cipher.dart';
import 'package:sqflite/sqflite.dart';

typedef OperatorDatabaseOpener = Future<Database> Function();

class StoredFaceTemplate {
  const StoredFaceTemplate({
    required this.id,
    required this.operatorId,
    required this.method,
    required this.encrypted,
    required this.createdAt,
  });

  final String id;
  final String operatorId;
  final String method;
  final EncryptedFaceTemplate encrypted;
  final DateTime createdAt;
}

class OperatorWithTemplate {
  const OperatorWithTemplate({required this.operator, required this.template});

  final OperatorRecord operator;
  final StoredFaceTemplate template;
}

class DuplicateEmployeeIdException implements Exception {
  const DuplicateEmployeeIdException(this.employeeId);

  final String employeeId;

  @override
  String toString() => 'Employee ID $employeeId is already registered.';
}

class OperatorDatabase {
  OperatorDatabase({OperatorDatabaseOpener? opener})
    : _opener = opener ?? _openProductionDatabase;

  static const int schemaVersion = 1;
  static const String databaseFileName = 'intellihmi_operator_auth_v1.db';

  final OperatorDatabaseOpener _opener;
  Future<Database>? _databaseFuture;

  Future<Database> get database => _databaseFuture ??= _opener();

  static Future<Database> _openProductionDatabase() async {
    final root = await getDatabasesPath();
    return openDatabase(
      path.join(root, databaseFileName),
      version: schemaVersion,
      onConfigure: (database) async {
        await database.rawQuery('PRAGMA foreign_keys = ON');
        await database.rawQuery('PRAGMA secure_delete = ON');
      },
      onCreate: _createSchema,
    );
  }

  static Future<void> createSchemaForTesting(Database database) async {
    await database.rawQuery('PRAGMA foreign_keys = ON');
    await database.rawQuery('PRAGMA secure_delete = ON');
    await _createSchema(database, schemaVersion);
  }

  static Future<void> _createSchema(Database database, int version) async {
    await database.execute('''
      CREATE TABLE operators (
        id TEXT PRIMARY KEY NOT NULL,
        employee_id TEXT NOT NULL,
        employee_id_canonical TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        role TEXT NOT NULL,
        enabled INTEGER NOT NULL CHECK (enabled IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE face_templates (
        id TEXT PRIMARY KEY NOT NULL,
        operator_id TEXT NOT NULL UNIQUE,
        method TEXT NOT NULL,
        cipher_algorithm TEXT NOT NULL,
        cipher_schema_version INTEGER NOT NULL,
        key_reference TEXT NOT NULL UNIQUE,
        cipher_text BLOB NOT NULL,
        nonce BLOB NOT NULL,
        mac BLOB NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (operator_id) REFERENCES operators(id) ON DELETE CASCADE
      )
    ''');
    await database.execute('''
      CREATE TABLE operator_audit_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_type TEXT NOT NULL,
        result TEXT NOT NULL,
        failure_reason TEXT,
        operator_id TEXT,
        employee_id_snapshot TEXT,
        operator_name_snapshot TEXT,
        role_snapshot TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE INDEX operator_audit_occurred_at_idx
      ON operator_audit_events(occurred_at DESC)
    ''');
  }

  Future<bool> employeeIdExists(String employeeId) async {
    final db = await database;
    final rows = await db.query(
      'operators',
      columns: const ['id'],
      where: 'employee_id_canonical = ?',
      whereArgs: [employeeId.trim().toUpperCase()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> createOperatorWithTemplate({
    required OperatorRecord operator,
    required StoredFaceTemplate template,
  }) async {
    final db = await database;
    try {
      await db.transaction((transaction) async {
        await transaction.insert('operators', _operatorMap(operator));
        await transaction.insert('face_templates', _templateMap(template));
        await _insertAudit(
          transaction,
          OperatorAuditEvent(
            type: OperatorAuditEventType.operatorRegistered,
            result: OperatorAuditResult.success,
            occurredAt: operator.createdAt,
            operatorId: operator.id,
            employeeIdSnapshot: operator.employeeId,
            operatorNameSnapshot: operator.name,
            roleSnapshot: operator.role.name,
          ),
        );
        await _insertAudit(
          transaction,
          OperatorAuditEvent(
            type: OperatorAuditEventType.faceEnrollmentSucceeded,
            result: OperatorAuditResult.success,
            occurredAt: operator.createdAt,
            operatorId: operator.id,
            employeeIdSnapshot: operator.employeeId,
            operatorNameSnapshot: operator.name,
            roleSnapshot: operator.role.name,
          ),
        );
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw DuplicateEmployeeIdException(operator.employeeId);
      }
      rethrow;
    }
  }

  Future<List<OperatorRecord>> listOperators({
    String search = '',
    bool includeDeleted = false,
  }) async {
    final db = await database;
    final normalizedSearch = '%${search.trim()}%';
    final filters = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) filters.add('deleted_at IS NULL');
    if (search.trim().isNotEmpty) {
      filters.add('(employee_id LIKE ? OR name LIKE ?)');
      args.addAll([normalizedSearch, normalizedSearch]);
    }
    final rows = await db.query(
      'operators',
      where: filters.isEmpty ? null : filters.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE ASC, employee_id_canonical ASC',
    );
    return rows.map(_operatorFromMap).toList(growable: false);
  }

  Future<List<OperatorWithTemplate>> loadOperatorsWithTemplates({
    required bool enabledOnly,
  }) async {
    final db = await database;
    final eligibility = enabledOnly
        ? 'o.enabled = 1 AND o.deleted_at IS NULL'
        : 'o.deleted_at IS NULL';
    final rows = await db.rawQuery('''
      SELECT
        o.id AS o_id, o.employee_id, o.name, o.role, o.enabled,
        o.created_at AS o_created_at, o.updated_at, o.deleted_at,
        t.id AS t_id, t.operator_id, t.method, t.cipher_algorithm,
        t.cipher_schema_version, t.key_reference, t.cipher_text, t.nonce,
        t.mac, t.created_at AS t_created_at
      FROM operators o
      INNER JOIN face_templates t ON t.operator_id = o.id
      WHERE $eligibility
      ORDER BY o.employee_id_canonical ASC
    ''');
    return rows.map((row) {
      final operator = _operatorFromMap(<String, Object?>{
        'id': row['o_id'],
        'employee_id': row['employee_id'],
        'name': row['name'],
        'role': row['role'],
        'enabled': row['enabled'],
        'created_at': row['o_created_at'],
        'updated_at': row['updated_at'],
        'deleted_at': row['deleted_at'],
      });
      return OperatorWithTemplate(
        operator: operator,
        template: _templateFromJoinedMap(row),
      );
    }).toList(growable: false);
  }

  Future<StoredFaceTemplate?> templateForOperator(String operatorId) async {
    final db = await database;
    final rows = await db.query(
      'face_templates',
      where: 'operator_id = ?',
      whereArgs: [operatorId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _templateFromMap(rows.single);
  }

  Future<void> replaceTemplate({
    required OperatorRecord operator,
    required StoredFaceTemplate replacement,
    required DateTime occurredAt,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      await transaction.delete(
        'face_templates',
        where: 'operator_id = ?',
        whereArgs: [operator.id],
      );
      await transaction.insert('face_templates', _templateMap(replacement));
      await transaction.update(
        'operators',
        {'updated_at': occurredAt.toUtc().toIso8601String()},
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [operator.id],
      );
      await _insertAudit(
        transaction,
        OperatorAuditEvent(
          type: OperatorAuditEventType.faceReenrolled,
          result: OperatorAuditResult.success,
          occurredAt: occurredAt,
          operatorId: operator.id,
          employeeIdSnapshot: operator.employeeId,
          operatorNameSnapshot: operator.name,
          roleSnapshot: operator.role.name,
        ),
      );
    });
  }

  Future<void> setEnabled({
    required OperatorRecord operator,
    required bool enabled,
    required DateTime occurredAt,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final count = await transaction.update(
        'operators',
        {
          'enabled': enabled ? 1 : 0,
          'updated_at': occurredAt.toUtc().toIso8601String(),
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [operator.id],
      );
      if (count != 1) throw StateError('Operator is not active.');
      await _insertAudit(
        transaction,
        OperatorAuditEvent(
          type: enabled
              ? OperatorAuditEventType.operatorEnabled
              : OperatorAuditEventType.operatorDisabled,
          result: OperatorAuditResult.success,
          occurredAt: occurredAt,
          operatorId: operator.id,
          employeeIdSnapshot: operator.employeeId,
          operatorNameSnapshot: operator.name,
          roleSnapshot: operator.role.name,
        ),
      );
    });
  }

  Future<StoredFaceTemplate?> softDeleteOperator({
    required OperatorRecord operator,
    required DateTime occurredAt,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      final templateRows = await transaction.query(
        'face_templates',
        where: 'operator_id = ?',
        whereArgs: [operator.id],
        limit: 1,
      );
      final template = templateRows.isEmpty
          ? null
          : _templateFromMap(templateRows.single);
      await transaction.delete(
        'face_templates',
        where: 'operator_id = ?',
        whereArgs: [operator.id],
      );
      final count = await transaction.update(
        'operators',
        {
          'enabled': 0,
          'updated_at': occurredAt.toUtc().toIso8601String(),
          'deleted_at': occurredAt.toUtc().toIso8601String(),
        },
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [operator.id],
      );
      if (count != 1) throw StateError('Operator is already deleted.');
      await _insertAudit(
        transaction,
        OperatorAuditEvent(
          type: OperatorAuditEventType.operatorDeleted,
          result: OperatorAuditResult.success,
          occurredAt: occurredAt,
          operatorId: operator.id,
          employeeIdSnapshot: operator.employeeId,
          operatorNameSnapshot: operator.name,
          roleSnapshot: operator.role.name,
        ),
      );
      return template;
    });
  }

  Future<void> appendAudit(OperatorAuditEvent event) async {
    final db = await database;
    await _insertAudit(db, event);
  }

  Future<List<OperatorAuditEvent>> listAuditEvents({int limit = 250}) async {
    final db = await database;
    final rows = await db.query(
      'operator_audit_events',
      orderBy: 'occurred_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(_auditFromMap).toList(growable: false);
  }

  Future<void> close() async {
    final future = _databaseFuture;
    _databaseFuture = null;
    if (future != null) await (await future).close();
  }

  static Map<String, Object?> _operatorMap(OperatorRecord operator) => {
    'id': operator.id,
    'employee_id': operator.employeeId,
    'employee_id_canonical': operator.employeeId.trim().toUpperCase(),
    'name': operator.name,
    'role': operator.role.name,
    'enabled': operator.enabled ? 1 : 0,
    'created_at': operator.createdAt.toUtc().toIso8601String(),
    'updated_at': operator.updatedAt.toUtc().toIso8601String(),
    'deleted_at': operator.deletedAt?.toUtc().toIso8601String(),
  };

  static OperatorRecord _operatorFromMap(Map<String, Object?> row) =>
      OperatorRecord(
        id: row['id'] as String,
        employeeId: row['employee_id'] as String,
        name: row['name'] as String,
        role: OperatorAccessLevel.values.byName(row['role'] as String),
        enabled: row['enabled'] == 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.parse(row['deleted_at'] as String),
      );

  static Map<String, Object?> _templateMap(StoredFaceTemplate template) => {
    'id': template.id,
    'operator_id': template.operatorId,
    'method': template.method,
    'cipher_algorithm': template.encrypted.algorithm,
    'cipher_schema_version': template.encrypted.schemaVersion,
    'key_reference': template.encrypted.keyReference,
    'cipher_text': template.encrypted.cipherText,
    'nonce': template.encrypted.nonce,
    'mac': template.encrypted.mac,
    'created_at': template.createdAt.toUtc().toIso8601String(),
  };

  static StoredFaceTemplate _templateFromMap(Map<String, Object?> row) =>
      StoredFaceTemplate(
        id: row['id'] as String,
        operatorId: row['operator_id'] as String,
        method: row['method'] as String,
        encrypted: EncryptedFaceTemplate(
          keyReference: row['key_reference'] as String,
          cipherText: List<int>.from(row['cipher_text'] as List<int>),
          nonce: List<int>.from(row['nonce'] as List<int>),
          mac: List<int>.from(row['mac'] as List<int>),
          algorithm: row['cipher_algorithm'] as String,
          schemaVersion: row['cipher_schema_version'] as int,
        ),
        createdAt: DateTime.parse(row['created_at'] as String),
      );

  static StoredFaceTemplate _templateFromJoinedMap(
    Map<String, Object?> row,
  ) => StoredFaceTemplate(
    id: row['t_id'] as String,
    operatorId: row['operator_id'] as String,
    method: row['method'] as String,
    encrypted: EncryptedFaceTemplate(
      keyReference: row['key_reference'] as String,
      cipherText: List<int>.from(row['cipher_text'] as List<int>),
      nonce: List<int>.from(row['nonce'] as List<int>),
      mac: List<int>.from(row['mac'] as List<int>),
      algorithm: row['cipher_algorithm'] as String,
      schemaVersion: row['cipher_schema_version'] as int,
    ),
    createdAt: DateTime.parse(row['t_created_at'] as String),
  );

  static Future<void> _insertAudit(
    DatabaseExecutor executor,
    OperatorAuditEvent event,
  ) => executor.insert('operator_audit_events', {
    'event_type': event.type.name,
    'result': event.result.name,
    'failure_reason': event.failureReason,
    'operator_id': event.operatorId,
    'employee_id_snapshot': event.employeeIdSnapshot,
    'operator_name_snapshot': event.operatorNameSnapshot,
    'role_snapshot': event.roleSnapshot,
    'occurred_at': event.occurredAt.toUtc().toIso8601String(),
  });

  static OperatorAuditEvent _auditFromMap(Map<String, Object?> row) =>
      OperatorAuditEvent(
        type: OperatorAuditEventType.values.byName(row['event_type'] as String),
        result: OperatorAuditResult.values.byName(row['result'] as String),
        occurredAt: DateTime.parse(row['occurred_at'] as String),
        operatorId: row['operator_id'] as String?,
        employeeIdSnapshot: row['employee_id_snapshot'] as String?,
        operatorNameSnapshot: row['operator_name_snapshot'] as String?,
        roleSnapshot: row['role_snapshot'] as String?,
        failureReason: row['failure_reason'] as String?,
      );
}
