import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/models/permission.dart';

/// Centralized permission check. Holds no resources or mutable state (pure
/// lookup over [RolePermissions]), so — unlike the storage services — a
/// static utility is appropriate here; later stages' controllers/widgets
/// call [can] instead of comparing roles inline.
class AuthorizationService {
  AuthorizationService._();

  static bool can(OperatorRole role, Permission permission) =>
      RolePermissions.forRole(role).contains(permission);
}
