/// Outcome of an authentication attempt (password, biometric, face, or PIN).
enum AuthEventResult {
  success('Success'),
  failed('Failed'),
  cancelled('Cancelled'),
  error('Error');

  const AuthEventResult(this.displayName);

  final String displayName;

  static AuthEventResult? tryParse(String? value) {
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}

/// Which credential/factor an authentication attempt used.
///
/// `face` and `pin` are not implemented until later stages — the enum grows
/// now so the on-disk schema never has to change shape again to add them.
enum AuthEventMethod {
  password('Password'),
  biometric('Biometric'),
  face('Face'),
  pin('PIN');

  const AuthEventMethod(this.displayName);

  final String displayName;

  static AuthEventMethod? tryParse(String? value) {
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}

/// Operator-record lifecycle events (Operator Management, added in Stage 2).
enum OperatorLifecycleEvent {
  /// A bare profile was created — name/employeeId/role only, no biometric
  /// template yet. Distinct from [enrolled], which is reserved for when a
  /// face template is actually attached (Stage 3/4) — logging profile
  /// creation as "Operator Enrolled" would misleadingly imply a biometric
  /// credential exists before it does.
  profileCreated('Operator Profile Created'),
  enrolled('Operator Enrolled'),
  reenrolled('Operator Re-enrolled'),
  disabled('Operator Disabled'),
  enabled('Operator Enabled'),
  deleted('Operator Deleted');

  const OperatorLifecycleEvent(this.displayName);

  final String displayName;

  static OperatorLifecycleEvent? tryParse(String? value) {
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}

/// Top-level grouping used by the Event Log's filter chips.
enum AuthLogCategory {
  authentication('Authentication'),
  operatorManagement('Operator Management'),
  system('System');

  const AuthLogCategory(this.displayName);

  final String displayName;

  static AuthLogCategory fromName(String value) => values.firstWhere(
    (v) => v.name == value,
    orElse: () => AuthLogCategory.system,
  );
}

/// A single audit-log record. Never carries face images, embeddings, or any
/// other biometric payload — only enough metadata to explain who/what/when.
class AuthLogEntry {
  const AuthLogEntry({
    required this.timestamp,
    required this.category,
    this.result,
    this.method,
    this.lifecycleEvent,
    this.userIdentifier,
    this.operatorId,
    this.operatorNameSnapshot,
    this.role,
    this.deviceId,
    this.plcDeviceName,
    this.plcDeviceId,
    this.plcType,
    this.connectionStatus,
    this.sessionCorrelationId,
    this.failureReason,
    this.detailCode,
    this.schemaVersion = 1,
  });

  final DateTime timestamp;
  final AuthLogCategory category;

  /// Set when [category] is [AuthLogCategory.authentication].
  final AuthEventResult? result;
  final AuthEventMethod? method;

  /// Set when [category] is [AuthLogCategory.operatorManagement].
  final OperatorLifecycleEvent? lifecycleEvent;

  final String? userIdentifier;
  final String? operatorId;
  final String? operatorNameSnapshot;
  final String? role;
  final String? deviceId;
  final String? plcDeviceName;
  final String? plcDeviceId;
  final String? plcType;
  final String? connectionStatus;

  /// Short one-way hash of the active BLE session id — enough to correlate
  /// entries within the same session, never the real session/nonce material.
  final String? sessionCorrelationId;

  final String? failureReason;
  final String? detailCode;
  final int schemaVersion;

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'category': category.name,
    if (result != null) 'result': result!.name,
    if (method != null) 'method': method!.name,
    if (lifecycleEvent != null) 'lifecycleEvent': lifecycleEvent!.name,
    if (userIdentifier != null) 'userIdentifier': userIdentifier,
    if (operatorId != null) 'operatorId': operatorId,
    if (operatorNameSnapshot != null)
      'operatorNameSnapshot': operatorNameSnapshot,
    if (role != null) 'role': role,
    if (deviceId != null) 'deviceId': deviceId,
    if (plcDeviceName != null) 'plcDeviceName': plcDeviceName,
    if (plcDeviceId != null) 'plcDeviceId': plcDeviceId,
    if (plcType != null) 'plcType': plcType,
    if (connectionStatus != null) 'connectionStatus': connectionStatus,
    if (sessionCorrelationId != null)
      'sessionCorrelationId': sessionCorrelationId,
    if (failureReason != null) 'failureReason': failureReason,
    if (detailCode != null) 'detailCode': detailCode,
    'schemaVersion': schemaVersion,
  };

  factory AuthLogEntry.fromJson(Map<String, dynamic> json) {
    return AuthLogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      category: AuthLogCategory.fromName(json['category'] as String),
      result: AuthEventResult.tryParse(json['result'] as String?),
      method: AuthEventMethod.tryParse(json['method'] as String?),
      lifecycleEvent: OperatorLifecycleEvent.tryParse(
        json['lifecycleEvent'] as String?,
      ),
      userIdentifier: json['userIdentifier'] as String?,
      operatorId: json['operatorId'] as String?,
      operatorNameSnapshot: json['operatorNameSnapshot'] as String?,
      role: json['role'] as String?,
      deviceId: json['deviceId'] as String?,
      plcDeviceName: json['plcDeviceName'] as String?,
      plcDeviceId: json['plcDeviceId'] as String?,
      plcType: json['plcType'] as String?,
      connectionStatus: json['connectionStatus'] as String?,
      sessionCorrelationId: json['sessionCorrelationId'] as String?,
      failureReason: json['failureReason'] as String?,
      detailCode: json['detailCode'] as String?,
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }
}
