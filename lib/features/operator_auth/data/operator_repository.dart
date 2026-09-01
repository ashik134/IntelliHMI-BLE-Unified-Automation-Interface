import 'package:rev_crane_control_ops/features/operator_auth/data/operator_database.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/face_template_cipher.dart';
import 'package:uuid/uuid.dart';

class DecryptedOperatorTemplate {
  const DecryptedOperatorTemplate({
    required this.operator,
    required this.templateBytes,
    required this.method,
  });

  final OperatorRecord operator;
  final List<int> templateBytes;
  final String method;
}

class OperatorRepository {
  OperatorRepository({
    OperatorDatabase? database,
    FaceTemplateCipher? cipher,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _database = database ?? OperatorDatabase(),
       _cipher = cipher ?? FaceTemplateCipher(),
       _uuid = uuid ?? const Uuid(),
       _now = now ?? DateTime.now;

  final OperatorDatabase _database;
  final FaceTemplateCipher _cipher;
  final Uuid _uuid;
  final DateTime Function() _now;

  Future<List<OperatorRecord>> listOperators({String search = ''}) =>
      _database.listOperators(search: search);

  Future<bool> employeeIdExists(String employeeId) =>
      _database.employeeIdExists(employeeId);

  Future<OperatorRecord> createOperator({
    required OperatorInput input,
    required List<int> templateBytes,
    required String templateMethod,
  }) async {
    final validationError = input.validate();
    if (validationError != null) throw ArgumentError(validationError);
    if (templateBytes.isEmpty) {
      throw ArgumentError('Face enrollment must succeed before registration.');
    }

    if (await _database.employeeIdExists(input.employeeId)) {
      await recordRejection(
        type: OperatorAuditEventType.duplicateEmployeeIdRejected,
        input: input,
        reason: 'Employee ID already exists.',
      );
      throw DuplicateEmployeeIdException(input.employeeId.trim());
    }

    final encrypted = await _cipher.encrypt(
      templateBytes: templateBytes,
      templateMethod: templateMethod,
    );
    final now = _now().toUtc();
    final operator = OperatorRecord(
      id: _uuid.v4(),
      employeeId: input.employeeId.trim(),
      name: input.name.trim(),
      role: input.role,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    final template = StoredFaceTemplate(
      id: _uuid.v4(),
      operatorId: operator.id,
      method: templateMethod,
      encrypted: encrypted,
      createdAt: now,
    );

    try {
      await _database.createOperatorWithTemplate(
        operator: operator,
        template: template,
      );
      return operator;
    } catch (error) {
      await _cipher.destroyKey(encrypted.keyReference);
      if (error is DuplicateEmployeeIdException) {
        await recordRejection(
          type: OperatorAuditEventType.duplicateEmployeeIdRejected,
          input: input,
          reason: 'Employee ID uniqueness constraint rejected registration.',
        );
      }
      rethrow;
    }
  }

  Future<List<DecryptedOperatorTemplate>> loadAuthenticatableTemplates() async {
    return _loadTemplates(enabledOnly: true);
  }

  /// Includes disabled (but not deleted) operators for population-wide
  /// duplicate-face prevention.
  Future<List<DecryptedOperatorTemplate>> loadEnrolledTemplates() async {
    return _loadTemplates(enabledOnly: false);
  }

  Future<List<DecryptedOperatorTemplate>> _loadTemplates({
    required bool enabledOnly,
  }) async {
    final stored = await _database.loadOperatorsWithTemplates(
      enabledOnly: enabledOnly,
    );
    final result = <DecryptedOperatorTemplate>[];
    try {
      for (final entry in stored) {
        final bytes = await _cipher.decrypt(
          encrypted: entry.template.encrypted,
          templateMethod: entry.template.method,
        );
        result.add(
          DecryptedOperatorTemplate(
            operator: entry.operator,
            templateBytes: bytes,
            method: entry.template.method,
          ),
        );
      }
      return result;
    } catch (_) {
      for (final entry in result) {
        for (var index = 0; index < entry.templateBytes.length; index += 1) {
          entry.templateBytes[index] = 0;
        }
      }
      rethrow;
    }
  }

  Future<void> setEnabled(OperatorRecord operator, bool enabled) =>
      _database.setEnabled(
        operator: operator,
        enabled: enabled,
        occurredAt: _now().toUtc(),
      );

  Future<void> replaceFaceTemplate({
    required OperatorRecord operator,
    required List<int> templateBytes,
    required String templateMethod,
  }) async {
    if (operator.isDeleted) throw StateError('Operator is deleted.');
    final previous = await _database.templateForOperator(operator.id);
    if (previous == null) throw StateError('Operator has no face enrollment.');
    final encrypted = await _cipher.encrypt(
      templateBytes: templateBytes,
      templateMethod: templateMethod,
    );
    final replacement = StoredFaceTemplate(
      id: _uuid.v4(),
      operatorId: operator.id,
      method: templateMethod,
      encrypted: encrypted,
      createdAt: _now().toUtc(),
    );
    try {
      await _database.replaceTemplate(
        operator: operator,
        replacement: replacement,
        occurredAt: _now().toUtc(),
      );
    } catch (_) {
      await _cipher.destroyKey(encrypted.keyReference);
      rethrow;
    }
    await _cipher.destroyKey(previous.encrypted.keyReference);
  }

  Future<void> deleteOperator(OperatorRecord operator) async {
    final removedTemplate = await _database.softDeleteOperator(
      operator: operator,
      occurredAt: _now().toUtc(),
    );
    if (removedTemplate != null) {
      await _cipher.destroyKey(removedTemplate.encrypted.keyReference);
    }
  }

  Future<void> recordRejection({
    required OperatorAuditEventType type,
    required OperatorInput input,
    required String reason,
  }) => _database.appendAudit(
    OperatorAuditEvent(
      type: type,
      result: OperatorAuditResult.rejected,
      occurredAt: _now().toUtc(),
      employeeIdSnapshot: input.employeeId.trim(),
      operatorNameSnapshot: input.name.trim(),
      roleSnapshot: input.role.name,
      failureReason: reason,
    ),
  );

  Future<void> recordAuthenticationEvent({
    required OperatorAuditEventType type,
    required OperatorAuditResult result,
    OperatorRecord? operator,
    String? failureReason,
  }) {
    const authenticationTypes = {
      OperatorAuditEventType.faceAuthenticationSucceeded,
      OperatorAuditEventType.faceAuthenticationFailed,
      OperatorAuditEventType.unknownFaceRejected,
      OperatorAuditEventType.livenessFailed,
      OperatorAuditEventType.spoofRejected,
      OperatorAuditEventType.disabledOperatorRejected,
    };
    if (!authenticationTypes.contains(type)) {
      throw ArgumentError.value(type, 'type', 'Not an authentication event.');
    }
    return _database.appendAudit(
      OperatorAuditEvent(
        type: type,
        result: result,
        occurredAt: _now().toUtc(),
        operatorId: operator?.id,
        employeeIdSnapshot: operator?.employeeId,
        operatorNameSnapshot: operator?.name,
        roleSnapshot: operator?.role.name,
        failureReason: failureReason,
      ),
    );
  }

  Future<void> close() => _database.close();
}
