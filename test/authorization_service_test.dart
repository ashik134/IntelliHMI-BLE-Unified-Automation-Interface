import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/models/permission.dart';
import 'package:rev_crane_control_ops/services/authorization_service.dart';

void main() {
  test('operator only has control access', () {
    expect(
      AuthorizationService.can(OperatorRole.operator, Permission.controlAccess),
      isTrue,
    );
    expect(
      AuthorizationService.can(
        OperatorRole.operator,
        Permission.alarmAcknowledge,
      ),
      isFalse,
    );
    expect(
      AuthorizationService.can(
        OperatorRole.operator,
        Permission.operatorManagement,
      ),
      isFalse,
    );
  });

  test('supervisor adds alarm acknowledgement only', () {
    expect(
      AuthorizationService.can(
        OperatorRole.supervisor,
        Permission.alarmAcknowledge,
      ),
      isTrue,
    );
    expect(
      AuthorizationService.can(
        OperatorRole.supervisor,
        Permission.configDiagnostics,
      ),
      isFalse,
    );
  });

  test('engineer adds configuration/diagnostics but not operator management', () {
    expect(
      AuthorizationService.can(
        OperatorRole.engineer,
        Permission.configDiagnostics,
      ),
      isTrue,
    );
    expect(
      AuthorizationService.can(
        OperatorRole.engineer,
        Permission.operatorManagement,
      ),
      isFalse,
    );
  });

  test('administrator holds every permission', () {
    for (final permission in Permission.values) {
      expect(
        AuthorizationService.can(OperatorRole.administrator, permission),
        isTrue,
        reason: permission.name,
      );
    }
  });
}
