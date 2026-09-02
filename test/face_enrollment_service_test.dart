import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/face_enrollment_service.dart';

// `FaceEmbeddingService.embed` needs a real on-device TFLite interpreter
// (see its own doc comment), so nothing that depends on live capture —
// i.e. `FaceEnrollmentService.evaluateAndCapture`/`finalizeEnrollment` —
// can be exercised in this environment. `buildTemplate` was split out of
// `finalizeEnrollment` specifically so the outlier-trim/averaging/
// duplicate-check logic is still testable with synthetic embeddings; see
// `face_enrollment_service.dart`'s doc comment on that method.

Future<SecretKey> _testKey() => AesGcm.with256bits().newSecretKey();

List<double> _vec(List<double> base) => List<double>.from(base);

FaceTemplate _template(String operatorId, List<double> embedding) {
  return FaceTemplate(
    templateId: 'T-$operatorId',
    operatorId: operatorId,
    embedding: embedding,
    modelVersion: 'mobilefacenet_v1',
    createdAt: DateTime.now(),
  );
}

void main() {
  late Directory tempDir;
  late FaceTemplateRepository templateRepository;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('face_enrollment_test');
    templateRepository = FaceTemplateRepository(
      baseDirectory: tempDir,
      key: await _testKey(),
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('buildTemplate', () {
    test('fails with insufficientSamples below requiredSamples', () async {
      final result = await FaceEnrollmentService.buildTemplate(
        operatorId: 'OP-1',
        samples: [_vec([1, 0, 0]), _vec([1, 0, 0])],
        templateRepository: templateRepository,
        requiredSamples: 7,
      );
      expect(result.success, isFalse);
      expect(
        result.failureReason,
        FaceEnrollmentFailureReason.insufficientSamples,
      );
    });

    test(
      'averages a tight cluster of samples into a normalized template',
      () async {
        final samples = [
          _vec([1.0, 0.0, 0.0]),
          _vec([0.99, 0.01, 0.0]),
          _vec([0.98, 0.02, 0.0]),
          _vec([1.0, 0.0, 0.01]),
          _vec([0.99, 0.0, 0.0]),
        ];
        final result = await FaceEnrollmentService.buildTemplate(
          operatorId: 'OP-1',
          samples: samples,
          templateRepository: templateRepository,
          requiredSamples: 5,
          minSurvivingSamples: 3,
        );

        expect(result.success, isTrue);
        final embedding = result.template!.embedding;
        expect(embedding.length, 3);

        var normSquared = 0.0;
        for (final v in embedding) {
          normSquared += v * v;
        }
        expect(normSquared, closeTo(1.0, 1e-9));
        // Roughly points the same direction as the tight cluster.
        expect(embedding[0], greaterThan(0.9));
      },
    );

    test('drops an outlier sample and still succeeds', () async {
      final samples = [
        _vec([1.0, 0.0, 0.0]),
        _vec([0.99, 0.01, 0.0]),
        _vec([0.98, 0.02, 0.0]),
        _vec([1.0, 0.0, 0.01]),
        _vec([0.0, 1.0, 0.0]), // wildly different — an outlier
      ];
      final result = await FaceEnrollmentService.buildTemplate(
        operatorId: 'OP-1',
        samples: samples,
        templateRepository: templateRepository,
        requiredSamples: 5,
        minSurvivingSamples: 3,
      );

      expect(result.success, isTrue);
      // The representative should still point mostly along the cluster's
      // direction, not be dragged toward the outlier.
      expect(result.template!.embedding[0], greaterThan(0.9));
    });

    test(
      'fails with insufficientSamples if too many samples are outliers',
      () async {
        final samples = [
          _vec([1.0, 0.0, 0.0]),
          _vec([0.99, 0.01, 0.0]),
          _vec([0.0, 1.0, 0.0]),
          _vec([0.0, -1.0, 0.0]),
          _vec([-1.0, 0.0, 0.0]),
        ];
        final result = await FaceEnrollmentService.buildTemplate(
          operatorId: 'OP-1',
          samples: samples,
          templateRepository: templateRepository,
          requiredSamples: 5,
          minSurvivingSamples: 4,
        );
        expect(result.success, isFalse);
        expect(
          result.failureReason,
          FaceEnrollmentFailureReason.insufficientSamples,
        );
      },
    );

    test(
      'rejects with duplicateFace when another operator already matches',
      () async {
        await templateRepository.upsert(
          _template('OP-EXISTING', _vec([1.0, 0.0, 0.0])),
        );

        final samples = List.generate(
          5,
          (_) => _vec([1.0, 0.0, 0.0]),
        );
        final result = await FaceEnrollmentService.buildTemplate(
          operatorId: 'OP-NEW',
          samples: samples,
          templateRepository: templateRepository,
          requiredSamples: 5,
          minSurvivingSamples: 3,
        );

        expect(result.success, isFalse);
        expect(
          result.failureReason,
          FaceEnrollmentFailureReason.duplicateFace,
        );
        expect(result.template, isNull);
      },
    );

    test(
      'does not flag re-enrollment as a duplicate of the operator\'s own '
      'prior template',
      () async {
        await templateRepository.upsert(
          _template('OP-1', _vec([1.0, 0.0, 0.0])),
        );

        final samples = List.generate(5, (_) => _vec([1.0, 0.0, 0.0]));
        final result = await FaceEnrollmentService.buildTemplate(
          operatorId: 'OP-1',
          samples: samples,
          templateRepository: templateRepository,
          requiredSamples: 5,
          minSurvivingSamples: 3,
        );

        expect(result.success, isTrue);
      },
    );

    test('does not write anything to the template repository', () async {
      final samples = List.generate(5, (_) => _vec([1.0, 0.0, 0.0]));
      await FaceEnrollmentService.buildTemplate(
        operatorId: 'OP-1',
        samples: samples,
        templateRepository: templateRepository,
        requiredSamples: 5,
        minSurvivingSamples: 3,
      );

      expect(await templateRepository.getAll(), isEmpty);
    });
  });
}
