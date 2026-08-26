import 'package:rev_crane_control_ops/models/operator_role.dart';

/// A registered IntelliHMI operator.
///
/// Deliberately does not carry a `logs` field — authentication history is
/// queried from `AuthenticationLogRepository` by [operatorId] instead of
/// duplicated here, so deleting an operator never has to reach into audit
/// data and the two stores stay independently encrypted/rotated.
///
/// [faceTemplateId] is a forward reference only: Stage 1 has no template
/// store yet (that arrives with the camera pipeline), so a profile must be
/// valid with no template at all — hence it, and [lastAuthenticatedAt],
/// are nullable.
class OperatorProfile {
  const OperatorProfile({
    required this.operatorId,
    required this.name,
    required this.employeeId,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
    this.faceTemplateId,
    this.enabled = true,
    this.lastAuthenticatedAt,
    this.schemaVersion = 1,
  });

  final String operatorId;
  final String name;
  final String employeeId;
  final OperatorRole role;
  final String? faceTemplateId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool enabled;
  final DateTime? lastAuthenticatedAt;
  final int schemaVersion;

  OperatorProfile copyWith({
    String? name,
    String? employeeId,
    OperatorRole? role,
    String? faceTemplateId,
    bool clearFaceTemplateId = false,
    DateTime? updatedAt,
    bool? enabled,
    DateTime? lastAuthenticatedAt,
  }) {
    return OperatorProfile(
      operatorId: operatorId,
      name: name ?? this.name,
      employeeId: employeeId ?? this.employeeId,
      role: role ?? this.role,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      faceTemplateId: clearFaceTemplateId
          ? null
          : (faceTemplateId ?? this.faceTemplateId),
      enabled: enabled ?? this.enabled,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'operatorId': operatorId,
    'name': name,
    'employeeId': employeeId,
    'role': role.name,
    if (faceTemplateId != null) 'faceTemplateId': faceTemplateId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'enabled': enabled,
    if (lastAuthenticatedAt != null)
      'lastAuthenticatedAt': lastAuthenticatedAt!.toIso8601String(),
    'schemaVersion': schemaVersion,
  };

  factory OperatorProfile.fromJson(Map<String, dynamic> json) {
    return OperatorProfile(
      operatorId: json['operatorId'] as String,
      name: json['name'] as String,
      employeeId: json['employeeId'] as String,
      role: OperatorRole.tryParse(json['role'] as String?) ??
          OperatorRole.operator,
      faceTemplateId: json['faceTemplateId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      enabled: json['enabled'] as bool? ?? true,
      lastAuthenticatedAt: json['lastAuthenticatedAt'] != null
          ? DateTime.parse(json['lastAuthenticatedAt'] as String)
          : null,
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
    );
  }
}
