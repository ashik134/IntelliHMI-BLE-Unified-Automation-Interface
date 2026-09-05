import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/models/operator_role.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/screens/operator/operator_management_screen.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';

OperatorProfile _profile(String id, {required String name}) {
  final now = DateTime(2026);
  return OperatorProfile(
    operatorId: id,
    name: name,
    employeeId: 'EMP-$id',
    role: OperatorRole.operator,
    faceTemplateId: 'template-$id',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pumpManagement(
  WidgetTester tester, {
  required OperatorRepository operatorRepository,
  required FaceTemplateRepository templateRepository,
  required AuthAuditLogService auditLog,
  AddOperatorScreenBuilder? addOperatorScreenBuilder,
}) async {
  await tester.pumpWidget(
    Provider<AuthAuditLogService>.value(
      value: auditLog,
      child: MaterialApp(
        home: OperatorManagementScreen(
          repository: operatorRepository,
          templateRepository: templateRepository,
          addOperatorScreenBuilder: addOperatorScreenBuilder,
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpRouteTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.any(finder)) return;
  }
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.any(finder)) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryOperatorRepository operatorRepository;
  late _MemoryFaceTemplateRepository templateRepository;
  late _NoopAuditLogService auditLog;

  setUp(() {
    operatorRepository = _MemoryOperatorRepository();
    templateRepository = _MemoryFaceTemplateRepository();
    auditLog = _NoopAuditLogService();
  });

  testWidgets('shows a newly added operator when the add route returns', (
    tester,
  ) async {
    final created = _profile('OP-1', name: 'Ava Chen');

    await _pumpManagement(
      tester,
      operatorRepository: operatorRepository,
      templateRepository: templateRepository,
      auditLog: auditLog,
      addOperatorScreenBuilder:
          (repository, templateRepository, auditLog, forceAdministratorRole) {
            return _CompleteAddRoute(operator: created, repository: repository);
          },
    );

    await _pumpUntilFound(tester, find.text('No operators yet'));
    expect(find.text('No operators yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Add Operator'));
    await _pumpRouteTransition(tester);
    await tester.tap(find.byKey(_CompleteAddRoute.completeButtonKey));
    await _pumpRouteTransition(tester);
    await _pumpUntilFound(tester, find.text('Ava Chen'));

    expect(find.text('Ava Chen'), findsOneWidget);
    expect(find.text('Face enrolled'), findsOneWidget);
  });

  testWidgets('removes a deleted operator when the detail route returns', (
    tester,
  ) async {
    await operatorRepository.add(_profile('OP-1', name: 'Ava Chen'));
    await operatorRepository.add(_profile('OP-2', name: 'Ben Ortiz'));

    await _pumpManagement(
      tester,
      operatorRepository: operatorRepository,
      templateRepository: templateRepository,
      auditLog: auditLog,
    );

    await _pumpUntilFound(tester, find.text('Ava Chen'));
    expect(find.text('Ava Chen'), findsOneWidget);
    expect(find.text('Ben Ortiz'), findsOneWidget);

    await tester.tap(find.text('Ava Chen'));
    await _pumpRouteTransition(tester);
    await tester.tap(find.text('Delete Operator'));
    await _pumpRouteTransition(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await _pumpRouteTransition(tester);
    await _pumpUntilGone(tester, find.text('Ava Chen'));

    expect(find.text('Ava Chen'), findsNothing);
    expect(find.text('Ben Ortiz'), findsOneWidget);
    expect(
      (await operatorRepository.getAll()).map(
        (operator) => operator.operatorId,
      ),
      ['OP-2'],
    );
  });
}

class _CompleteAddRoute extends StatelessWidget {
  const _CompleteAddRoute({required this.operator, required this.repository});

  static const completeButtonKey = Key('complete-add-route');

  final OperatorProfile operator;
  final OperatorRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: completeButtonKey,
          onPressed: () async {
            await repository.add(operator);
            if (context.mounted) Navigator.of(context).pop(operator);
          },
          child: const Text('Complete add'),
        ),
      ),
    );
  }
}

class _MemoryOperatorRepository extends OperatorRepository {
  _MemoryOperatorRepository()
    : super(baseDirectory: Directory.systemTemp, key: SecretKey(const []));

  final List<OperatorProfile> _operators = [];

  @override
  Future<List<OperatorProfile>> getAll() async => List.of(_operators);

  @override
  Future<void> add(OperatorProfile operator) async {
    _operators.add(operator);
  }

  @override
  Future<void> delete(String operatorId) async {
    _operators.removeWhere((operator) => operator.operatorId == operatorId);
  }
}

class _MemoryFaceTemplateRepository extends FaceTemplateRepository {
  _MemoryFaceTemplateRepository()
    : super(baseDirectory: Directory.systemTemp, key: SecretKey(const []));

  @override
  Future<void> upsert(FaceTemplate template) async {}

  @override
  Future<void> deleteByOperatorId(String operatorId) async {}
}

class _NoopAuditLogService extends AuthAuditLogService {
  _NoopAuditLogService() : super();

  @override
  Future<void> recordOperatorEvent({
    required OperatorLifecycleEvent event,
    required String operatorId,
    required String operatorNameSnapshot,
    required String role,
  }) async {}
}
