/// Configurable operator role. Deliberately generic — permissions are
/// looked up from [RolePermissions] rather than hard-coded against PLC
/// outputs or individual widgets (see [AuthorizationService]).
enum OperatorRole {
  operator('Operator'),
  supervisor('Supervisor'),
  engineer('Engineer'),
  administrator('Administrator');

  const OperatorRole(this.displayName);

  final String displayName;

  static OperatorRole? tryParse(String? value) {
    for (final v in values) {
      if (v.name == value) return v;
    }
    return null;
  }
}
