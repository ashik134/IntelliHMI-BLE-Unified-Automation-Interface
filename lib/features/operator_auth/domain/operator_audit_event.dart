enum OperatorAuditEventType {
  operatorRegistered,
  faceEnrollmentSucceeded,
  faceEnrollmentFailed,
  duplicateEmployeeIdRejected,
  duplicateFaceRejected,
  faceAuthenticationSucceeded,
  faceAuthenticationFailed,
  unknownFaceRejected,
  livenessFailed,
  spoofRejected,
  disabledOperatorRejected,
  operatorEnabled,
  operatorDisabled,
  faceReenrolled,
  operatorDeleted,
}

enum OperatorAuditResult { success, rejected, failure }

class OperatorAuditEvent {
  const OperatorAuditEvent({
    required this.type,
    required this.result,
    required this.occurredAt,
    this.operatorId,
    this.employeeIdSnapshot,
    this.operatorNameSnapshot,
    this.roleSnapshot,
    this.failureReason,
  });

  final OperatorAuditEventType type;
  final OperatorAuditResult result;
  final DateTime occurredAt;
  final String? operatorId;
  final String? employeeIdSnapshot;
  final String? operatorNameSnapshot;
  final String? roleSnapshot;
  final String? failureReason;
}
