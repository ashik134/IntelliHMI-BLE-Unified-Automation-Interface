import 'dart:typed_data';

import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';

class DuplicateFaceException implements Exception {
  const DuplicateFaceException();

  @override
  String toString() => 'This face is already registered to another operator.';
}

class OperatorEnrollmentService {
  OperatorEnrollmentService({
    required OperatorRepository repository,
    required FaceRecognitionEngine engine,
  }) : _repository = repository,
       _engine = engine;

  /// Conservative application threshold above the SDK examples' 0.85 sample
  /// threshold. It must be validated against the customer's physical-device
  /// population before production sign-off.
  static const double duplicateFaceScoreThreshold = 0.90;

  final OperatorRepository _repository;
  final FaceRecognitionEngine _engine;

  Future<OperatorRecord> register({
    required OperatorInput input,
    required FaceEnrollmentCapture capture,
  }) async {
    if (!capture.succeeded) {
      await _repository.recordRejection(
        type: OperatorAuditEventType.faceEnrollmentFailed,
        input: input,
        reason: 'No accepted live biometric template was produced.',
      );
      throw StateError('Face enrollment did not complete successfully.');
    }
    final bytes = capture.templateBytes!;
    final method = capture.templateMethod!;
    try {
      await _rejectDuplicateFace(
        candidate: bytes,
        candidateMethod: method,
        input: input,
      );
      return await _repository.createOperator(
        input: input,
        templateBytes: bytes,
        templateMethod: method,
      );
    } finally {
      _wipe(bytes);
    }
  }

  Future<void> reenroll({
    required OperatorRecord operator,
    required FaceEnrollmentCapture capture,
  }) async {
    if (!capture.succeeded) {
      throw StateError('Replacement face enrollment did not complete.');
    }
    final bytes = capture.templateBytes!;
    final method = capture.templateMethod!;
    final input = OperatorInput(
      employeeId: operator.employeeId,
      name: operator.name,
      role: operator.role,
    );
    try {
      await _rejectDuplicateFace(
        candidate: bytes,
        candidateMethod: method,
        input: input,
        excludedOperatorId: operator.id,
      );
      await _repository.replaceFaceTemplate(
        operator: operator,
        templateBytes: bytes,
        templateMethod: method,
      );
    } finally {
      _wipe(bytes);
    }
  }

  Future<void> _rejectDuplicateFace({
    required Uint8List candidate,
    required String candidateMethod,
    required OperatorInput input,
    String? excludedOperatorId,
  }) async {
    final enrolled = await _repository.loadEnrolledTemplates();
    try {
      for (final existing in enrolled) {
        if (existing.operator.id == excludedOperatorId) continue;
        if (existing.method != candidateMethod) {
          throw StateError(
            'Stored face-template method does not match the configured 3DiVi method.',
          );
        }
        final existingBytes = Uint8List.fromList(existing.templateBytes);
        late final FaceTemplateComparison comparison;
        try {
          comparison = await _engine.compareTemplates(
            candidate,
            existingBytes,
          );
        } finally {
          _wipe(existingBytes);
        }
        if (comparison.score >= duplicateFaceScoreThreshold) {
          await _repository.recordRejection(
            type: OperatorAuditEventType.duplicateFaceRejected,
            input: input,
            reason: '3DiVi comparison exceeded the duplicate-face threshold.',
          );
          throw const DuplicateFaceException();
        }
      }
    } finally {
      for (final existing in enrolled) {
        _wipe(existing.templateBytes);
      }
    }
  }

  void _wipe(List<int> bytes) {
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = 0;
    }
  }
}
