enum OperatorAccessLevel { operator, supervisor, maintenance }

extension OperatorAccessLevelLabel on OperatorAccessLevel {
  String get label => switch (this) {
    OperatorAccessLevel.operator => 'Operator',
    OperatorAccessLevel.supervisor => 'Supervisor',
    OperatorAccessLevel.maintenance => 'Maintenance',
  };
}

class OperatorRecord {
  const OperatorRecord({
    required this.id,
    required this.employeeId,
    required this.name,
    required this.role,
    required this.enabled,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String employeeId;
  final String name;
  final OperatorAccessLevel role;
  final bool enabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
  bool get hasFaceEnrollment => !isDeleted;
}

class OperatorInput {
  const OperatorInput({
    required this.employeeId,
    required this.name,
    required this.role,
  });

  final String employeeId;
  final String name;
  final OperatorAccessLevel role;

  String get normalizedEmployeeId => employeeId.trim().toUpperCase();

  String? validate() {
    final id = employeeId.trim();
    final displayName = name.trim();
    if (id.isEmpty) return 'Employee ID is required.';
    if (id.length > 64) return 'Employee ID must be 64 characters or fewer.';
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(id)) {
      return 'Employee ID may contain letters, numbers, dots, dashes, and underscores.';
    }
    if (displayName.isEmpty) return 'Operator name is required.';
    if (displayName.length > 120) {
      return 'Operator name must be 120 characters or fewer.';
    }
    return null;
  }
}
