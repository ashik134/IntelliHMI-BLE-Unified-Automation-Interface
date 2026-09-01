import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/features/operator_auth/application/operator_enrollment_service.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_database.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/face_template_cipher.dart';
import 'package:rev_crane_control_ops/features/operator_auth/security/secure_key_value_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'duplicate face is rejected before a second operator is committed',
    () async {
      sqfliteFfiInit();
      final rawDatabase = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      await OperatorDatabase.createSchemaForTesting(rawDatabase);
      final database = OperatorDatabase(opener: () async => rawDatabase);
      final repository = OperatorRepository(
        database: database,
        cipher: FaceTemplateCipher(keyStore: _MemorySecureStore()),
      );
      final existingOperator = await repository.createOperator(
        input: const OperatorInput(
          employeeId: 'EMP-001',
          name: 'Existing Operator',
          role: OperatorAccessLevel.operator,
        ),
        templateBytes: const [1, 2, 3],
        templateMethod: '3divi-100m',
      );
      await repository.setEnabled(existingOperator, false);

      final candidateBytes = Uint8List.fromList(const [4, 5, 6]);
      final service = OperatorEnrollmentService(
        repository: repository,
        engine: _FixedComparisonEngine(score: 0.96),
      );
      await expectLater(
        service.register(
          input: const OperatorInput(
            employeeId: 'EMP-002',
            name: 'Duplicate Face',
            role: OperatorAccessLevel.supervisor,
          ),
          capture: FaceEnrollmentCapture(
            analysis: const FaceFrameAnalysis(
              faces: [
                NormalizedFaceBounds(
                  left: 0.2,
                  top: 0.2,
                  right: 0.8,
                  bottom: 0.8,
                ),
              ],
              processingTime: Duration(milliseconds: 100),
              qualityAccepted: true,
              liveness: FaceLivenessVerdict.real,
            ),
            templateBytes: candidateBytes,
            templateMethod: '3divi-100m',
          ),
        ),
        throwsA(isA<DuplicateFaceException>()),
      );

      expect(await repository.listOperators(), hasLength(1));
      expect(candidateBytes, everyElement(0));
      final audit = await database.listAuditEvents();
      expect(
        audit.any(
          (event) => event.type == OperatorAuditEventType.duplicateFaceRejected,
        ),
        isTrue,
      );
      await database.close();
    },
  );
}

class _FixedComparisonEngine implements FaceRecognitionEngine {
  _FixedComparisonEngine({required this.score});

  final double score;

  @override
  bool get isInitialized => true;

  @override
  String? get sdkVersion => 'test';

  @override
  Future<FaceTemplateComparison> compareTemplates(
    Uint8List first,
    Uint8List second,
  ) async => FaceTemplateComparison(
    score: score,
    distance: 0.1,
    falseAcceptanceRate: 0.0001,
    falseRejectionRate: 0.01,
  );

  @override
  Future<List<FaceIdentificationCandidate>> identifyTemplate(
    Uint8List query,
    List<FaceGalleryTemplate> gallery, {
    int maxResults = 2,
  }) => throw UnimplementedError();

  @override
  Future<FaceFrameAnalysis> analyzeCameraFrame(
    CameraImage image, {
    required int rotationQuarterTurns,
  }) => throw UnimplementedError();

  @override
  Future<FaceEnrollmentCapture> createEnrollmentTemplate(
    CameraImage image, {
    required int rotationQuarterTurns,
  }) => throw UnimplementedError();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> dispose() async {}
}

class _MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
