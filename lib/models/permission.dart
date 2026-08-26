import 'package:rev_crane_control_ops/models/operator_role.dart';

/// A capability an operator role may or may not hold. This is the only
/// vocabulary controllers/widgets should use for authorization checks —
/// never a role comparison inline (see spec section 4).
enum Permission {
  controlAccess,
  alarmAcknowledge,
  configDiagnostics,
  operatorManagement,
  securitySettings,
  credentialReset,
}

/// The single place role → capability rules live. Roles are additive by
/// convention here (each tier includes the previous one's permissions) but
/// that's just how these defaults happen to be laid out, not a structural
/// requirement — entries can be edited independently.
class RolePermissions {
  RolePermissions._();

  static const Map<OperatorRole, Set<Permission>> _map = {
    OperatorRole.operator: {Permission.controlAccess},
    OperatorRole.supervisor: {
      Permission.controlAccess,
      Permission.alarmAcknowledge,
    },
    OperatorRole.engineer: {
      Permission.controlAccess,
      Permission.alarmAcknowledge,
      Permission.configDiagnostics,
    },
    OperatorRole.administrator: {
      Permission.controlAccess,
      Permission.alarmAcknowledge,
      Permission.configDiagnostics,
      Permission.operatorManagement,
      Permission.securitySettings,
      Permission.credentialReset,
    },
  };

  static Set<Permission> forRole(OperatorRole role) =>
      _map[role] ?? const <Permission>{};
}
