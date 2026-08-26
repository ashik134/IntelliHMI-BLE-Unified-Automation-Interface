import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/repositories/authentication_log_repository.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';

// NOTE on scope: CraneController.authenticate()'s own "never awaits the
// log write" behavior can't be exercised end-to-end here — _bleService is
// a hardcoded `BleService()` field with no test seam, so instantiating
// CraneController in a plain test would attempt real BLE platform-channel
// calls. What *is* testable, and is the actual mechanism the fire-and-
// forget guarantee rests on, is proven below: record() calls are
// serialized (not raced) and a failing write is contained inside the
// service rather than propagating to whatever called record() without
// awaiting it.

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // AuthAuditLogService.ensureLoaded() (invoked by getEntries()) reads
    // the retention policy via SharedPreferences.getInstance() — without
    // this mock that's a real platform-channel round trip with no engine
    // to answer it.
    SharedPreferences.setMockInitialValues({});
  });

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('audit_log_service_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('rapid unawaited record() calls all persist, newest first', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final repository = AuthenticationLogRepository(
      baseDirectory: tempDir,
      key: key,
    );
    final service = AuthAuditLogService(repository: repository);

    // Fire without awaiting any individually — exactly how CraneController
    // calls this via unawaited().
    final futures = [
      for (var i = 0; i < 5; i++)
        service.record(
          result: AuthEventResult.success,
          method: AuthEventMethod.password,
          userIdentifier: 'op-$i',
        ),
    ];
    await Future.wait(futures);

    final entries = await service.getEntries();
    expect(entries.map((e) => e.userIdentifier), [
      'op-4',
      'op-3',
      'op-2',
      'op-1',
      'op-0',
    ]);
  });

  test('a write failure is contained, never thrown back at the caller', () async {
    // A path that can never be a valid directory (a file already sits
    // where a directory would need to be created), so append() reliably
    // throws internally on every call.
    final blockingFile = File('${tempDir.path}/not_a_directory');
    await blockingFile.create();
    final badDirectory = Directory('${blockingFile.path}/nested');

    final key = await AesGcm.with256bits().newSecretKey();
    final repository = AuthenticationLogRepository(
      baseDirectory: badDirectory,
      key: key,
    );
    final service = AuthAuditLogService(repository: repository);

    // Must complete normally — this is exactly the guarantee that lets
    // CraneController fire-and-forget this call without risking an
    // unhandled exception on the BLE/auth call stack.
    await expectLater(
      service.record(
        result: AuthEventResult.error,
        method: AuthEventMethod.password,
      ),
      completes,
    );
  });

  test('operator lifecycle events are recorded under their own category', () async {
    final key = await AesGcm.with256bits().newSecretKey();
    final repository = AuthenticationLogRepository(
      baseDirectory: tempDir,
      key: key,
    );
    final service = AuthAuditLogService(repository: repository);

    await service.recordOperatorEvent(
      event: OperatorLifecycleEvent.enrolled,
      operatorId: 'OP-1',
      operatorNameSnapshot: 'Ashik R',
      role: 'Engineer',
    );

    final entries = await service.getEntries(
      category: AuthLogCategory.operatorManagement,
    );
    expect(entries, hasLength(1));
    expect(entries.single.lifecycleEvent, OperatorLifecycleEvent.enrolled);
    expect(entries.single.operatorNameSnapshot, 'Ashik R');
  });
}
