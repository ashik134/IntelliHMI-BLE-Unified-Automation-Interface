import 'dart:typed_data';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:face_sdk_3divi/face_sdk_3divi.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';

class ThreeDiviFaceRecognitionEngine implements FaceRecognitionEngine {
  ThreeDiviFaceRecognitionEngine({this.onInitializationStage});

  final void Function(String stage)? onInitializationStage;

  FacerecService? _service;
  AsyncProcessingBlock? _detector;
  AsyncProcessingBlock? _fitter;
  AsyncProcessingBlock? _qualityControl;
  AsyncProcessingBlock? _livenessEstimator;
  AsyncProcessingBlock? _templateExtractor;
  AsyncProcessingBlock? _verificationModule;
  AsyncProcessingBlock? _matcherModule;
  String? _sdkVersion;
  bool _isAnalyzing = false;

  @override
  bool get isInitialized =>
      _service != null &&
      _detector != null &&
      _fitter != null &&
      _qualityControl != null &&
      _livenessEstimator != null;

  @override
  String? get sdkVersion => _sdkVersion;

  @override
  Future<void> initialize() async {
    if (isInitialized) return;

    try {
      onInitializationStage?.call('Loading 3DiVi native service');
      final service = await FaceSdkPlugin.createFacerecService();
      _service = service;
      _sdkVersion = service.getVersion();

      onInitializationStage?.call('Loading face detector');
      _detector = await service.createAsyncProcessingBlock({
        'unit_type': 'FACE_DETECTOR',
        'modification': 'ssyv_light',
        'version': 1,
      });
      onInitializationStage?.call('Loading face fitter');
      _fitter = await service.createAsyncProcessingBlock({
        'unit_type': 'FACE_FITTER',
        'modification': 'fda',
        'version': 1,
      });
      onInitializationStage?.call('Loading quality control');
      _qualityControl = await service.createAsyncProcessingBlock({
        'unit_type': 'QUALITY_CONTROL',
        'modification': 'core',
        'mode': ['recognition'],
      });
      onInitializationStage?.call('Loading passive liveness / PAD');
      _livenessEstimator = await service.createAsyncProcessingBlock({
        'unit_type': 'LIVENESS_ESTIMATOR',
        'modification': '2d_ensemble_light',
        'version': 4,
      });
      onInitializationStage?.call('3DiVi biometric blocks ready');
    } catch (error) {
      await dispose();
      throw FaceEngineException('3DiVi initialization', _safeDetails(error));
    }
  }

  @override
  Future<FaceFrameAnalysis> analyzeCameraFrame(
    CameraImage image, {
    required int rotationQuarterTurns,
  }) async {
    final service = _service;
    final detector = _detector;
    final fitter = _fitter;
    final qualityControl = _qualityControl;
    final livenessEstimator = _livenessEstimator;

    if (!isInitialized ||
        service == null ||
        detector == null ||
        fitter == null ||
        qualityControl == null ||
        livenessEstimator == null) {
      throw const FaceEngineException(
        'Frame analysis',
        'Face SDK is not initialized',
      );
    }
    if (_isAnalyzing) {
      throw const FaceEngineException(
        'Frame analysis',
        'A previous camera frame is still being processed',
      );
    }

    _isAnalyzing = true;
    final stopwatch = Stopwatch()..start();
    Context? data;

    try {
      data = service.createContextFromCameraImage(image, rotationQuarterTurns);
      await detector.process(data);

      final objects = data['objects'];
      final faceCount = objects.len();
      final faces = <NormalizedFaceBounds>[];

      for (var index = 0; index < faceCount; index += 1) {
        final bounds = objects[index]['bbox'];
        faces.add(
          NormalizedFaceBounds(
            left: _normalized(bounds[0].get_value()),
            top: _normalized(bounds[1].get_value()),
            right: _normalized(bounds[2].get_value()),
            bottom: _normalized(bounds[3].get_value()),
          ),
        );
      }

      if (faceCount != 1) {
        return FaceFrameAnalysis(
          faces: faces,
          processingTime: stopwatch.elapsed,
        );
      }

      await fitter.process(data);
      await qualityControl.process(data);

      final face = data['objects'][0];
      final quality = face['quality'];
      final qualityAccepted = quality['value'].get_value() == true;
      final qualityFailureCode = qualityAccepted
          ? null
          : _firstQualityFailureCode(quality);

      if (!qualityAccepted) {
        return FaceFrameAnalysis(
          faces: faces,
          processingTime: stopwatch.elapsed,
          qualityAccepted: false,
          qualityFailureCode: qualityFailureCode,
        );
      }

      await livenessEstimator.process(data);
      final liveness = face['liveness'];
      final rawVerdict = liveness['value'].get_value().toString();
      final rawConfidence = liveness.contains('confidence')
          ? liveness['confidence'].get_value()
          : null;

      return FaceFrameAnalysis(
        faces: faces,
        processingTime: stopwatch.elapsed,
        qualityAccepted: true,
        liveness: _livenessVerdict(rawVerdict),
        livenessConfidence: rawConfidence is num
            ? rawConfidence.toDouble().clamp(0.0, 1.0)
            : null,
      );
    } catch (error) {
      throw FaceEngineException('Frame analysis', _safeDetails(error));
    } finally {
      stopwatch.stop();
      data?.dispose();
      _isAnalyzing = false;
    }
  }

  @override
  Future<FaceEnrollmentCapture> createEnrollmentTemplate(
    CameraImage image, {
    required int rotationQuarterTurns,
  }) async {
    await _ensureRecognitionBlocks();
    final analysis = await analyzeCameraFrame(
      image,
      rotationQuarterTurns: rotationQuarterTurns,
    );
    if (analysis.qualityAccepted != true ||
        analysis.liveness != FaceLivenessVerdict.real) {
      return FaceEnrollmentCapture(analysis: analysis);
    }

    final service = _service;
    final detector = _detector;
    final fitter = _fitter;
    final extractor = _templateExtractor;
    if (service == null ||
        detector == null ||
        fitter == null ||
        extractor == null) {
      throw const FaceEngineException(
        'Template extraction',
        '3DiVi recognition blocks are not initialized',
      );
    }

    _isAnalyzing = true;
    Context? data;
    ContextTemplate? template;
    try {
      data = service.createContextFromCameraImage(image, rotationQuarterTurns);
      await detector.process(data);
      if (data['objects'].len() != 1) {
        return FaceEnrollmentCapture(analysis: analysis);
      }
      await fitter.process(data);
      await extractor.process(data);
      final templateContext = data['objects'][0]['face_template']['template'];
      template = service.convertTemplate(templateContext);
      return FaceEnrollmentCapture(
        analysis: analysis,
        templateBytes: Uint8List.fromList(template.save()),
        templateMethod: template.getMethodName(),
      );
    } catch (error) {
      throw FaceEngineException('Template extraction', _safeDetails(error));
    } finally {
      template?.dispose();
      data?.dispose();
      _isAnalyzing = false;
    }
  }

  @override
  Future<FaceTemplateComparison> compareTemplates(
    Uint8List first,
    Uint8List second,
  ) async {
    if (first.isEmpty || second.isEmpty) {
      throw const FaceEngineException(
        'Template comparison',
        'Biometric templates cannot be empty',
      );
    }
    await _ensureRecognitionBlocks();
    final service = _service;
    final verifier = _verificationModule;
    if (service == null || verifier == null) {
      throw const FaceEngineException(
        'Template comparison',
        '3DiVi verification block is not initialized',
      );
    }

    ContextTemplate? firstTemplate;
    ContextTemplate? secondTemplate;
    Context? comparison;
    try {
      firstTemplate = service.loadContextTemplate(first);
      secondTemplate = service.loadContextTemplate(second);
      comparison = service.createContext({
        'template1': {'template': firstTemplate},
        'template2': {'template': secondTemplate},
      });
      await verifier.process(comparison);
      final result = comparison['result'];
      return FaceTemplateComparison(
        score: _doubleValue(result['score']),
        distance: _doubleValue(result['distance']),
        falseAcceptanceRate: _doubleValue(result['far']),
        falseRejectionRate: _doubleValue(result['frr']),
      );
    } catch (error) {
      throw FaceEngineException('Template comparison', _safeDetails(error));
    } finally {
      comparison?.dispose();
      secondTemplate?.dispose();
      firstTemplate?.dispose();
    }
  }

  @override
  Future<List<FaceIdentificationCandidate>> identifyTemplate(
    Uint8List query,
    List<FaceGalleryTemplate> gallery, {
    int maxResults = 2,
  }) async {
    if (query.isEmpty) {
      throw const FaceEngineException(
        'Operator identification',
        'Query biometric template cannot be empty',
      );
    }
    if (gallery.isEmpty) return const [];
    if (maxResults < 1) {
      throw const FaceEngineException(
        'Operator identification',
        'At least one matcher result must be requested',
      );
    }

    await _ensureRecognitionBlocks(includeMatcher: true);
    final service = _service;
    final matcher = _matcherModule;
    if (service == null || matcher == null) {
      throw const FaceEngineException(
        'Operator identification',
        '3DiVi matcher block is not initialized',
      );
    }

    ContextTemplate? queryTemplate;
    final galleryTemplates = <ContextTemplate>[];
    DynamicTemplateIndex? index;
    Context? matcherData;
    try {
      queryTemplate = service.loadContextTemplate(query);
      for (final entry in gallery) {
        if (entry.id.isEmpty || entry.templateBytes.isEmpty) {
          throw const FaceEngineException(
            'Operator identification',
            'Gallery identifiers and templates cannot be empty',
          );
        }
        galleryTemplates.add(service.loadContextTemplate(entry.templateBytes));
      }

      final capacity = math.max(gallery.length, 1);
      index = service.createDynamicTemplateIndexWithTemplates(
        galleryTemplates,
        gallery.map((entry) => entry.id).toList(growable: false),
        {
          'modification': '100m',
          'version': 1,
          'capacity': capacity,
          'max_license_count': math.max(capacity, 100),
          'force_unique_uuids': true,
        },
      );
      matcherData = service.createContext({
        'template_index': index,
        'queries': queryTemplate,
        'knn': math.min(maxResults, gallery.length),
      });
      await matcher.process(matcherData);

      final rawResults = matcherData['results'];
      final results = <FaceIdentificationCandidate>[];
      for (
        var resultIndex = 0;
        resultIndex < rawResults.len();
        resultIndex += 1
      ) {
        final result = rawResults[resultIndex];
        results.add(
          FaceIdentificationCandidate(
            galleryId: result['uuid'].get_value().toString(),
            score: _doubleValue(result['score']),
            distance: _doubleValue(result['distance']),
          ),
        );
      }
      results.sort((first, second) => second.score.compareTo(first.score));
      return results;
    } catch (error) {
      if (error is FaceEngineException) rethrow;
      throw FaceEngineException('Operator identification', _safeDetails(error));
    } finally {
      matcherData?.dispose();
      index?.dispose();
      for (final template in galleryTemplates.reversed) {
        template.dispose();
      }
      queryTemplate?.dispose();
    }
  }

  Future<void> _ensureRecognitionBlocks({bool includeMatcher = false}) async {
    if (!isInitialized) await initialize();
    if (_templateExtractor != null &&
        _verificationModule != null &&
        (!includeMatcher || _matcherModule != null)) {
      return;
    }
    final service = _service;
    if (service == null) {
      throw const FaceEngineException(
        'Recognition initialization',
        'Face SDK service is unavailable',
      );
    }
    try {
      _templateExtractor ??= await service.createAsyncProcessingBlock({
        'unit_type': 'FACE_TEMPLATE_EXTRACTOR',
        'modification': '100m',
        'version': 1,
      });
      _verificationModule ??= await service.createAsyncProcessingBlock({
        'unit_type': 'VERIFICATION_MODULE',
        'modification': '100m',
        'version': 1,
      });
      if (includeMatcher) {
        _matcherModule ??= await service.createAsyncProcessingBlock({
          'unit_type': 'MATCHER_MODULE',
          'modification': '100m',
          'version': 1,
          'threads_count': 1,
          'internal_threads_count': 1,
        });
      }
    } catch (error) {
      throw FaceEngineException(
        'Recognition initialization',
        _safeDetails(error),
      );
    }
  }

  double _doubleValue(Context value) {
    final raw = value.get_value();
    if (raw is num) return raw.toDouble();
    throw StateError('3DiVi result is not numeric.');
  }

  String? _firstQualityFailureCode(Context quality) {
    if (!quality.contains('failed_checks')) return null;
    final failedChecks = quality['failed_checks'];
    if (failedChecks.len() == 0) return null;
    final firstCheck = failedChecks[0];
    if (!firstCheck.contains('check')) return null;
    return firstCheck['check'].get_value().toString();
  }

  FaceLivenessVerdict _livenessVerdict(String value) {
    switch (value.toUpperCase()) {
      case 'REAL':
        return FaceLivenessVerdict.real;
      case 'FAKE':
        return FaceLivenessVerdict.fake;
      default:
        return FaceLivenessVerdict.inconclusive;
    }
  }

  double _normalized(dynamic value) {
    if (value is! num) return 0;
    return value.toDouble().clamp(0.0, 1.0);
  }

  String _safeDetails(Object error) {
    final message = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    return message.length <= 500 ? message : '${message.substring(0, 500)}…';
  }

  @override
  Future<void> dispose() async {
    final blocks = <AsyncProcessingBlock?>[
      _matcherModule,
      _verificationModule,
      _templateExtractor,
      _livenessEstimator,
      _qualityControl,
      _fitter,
      _detector,
    ];

    _matcherModule = null;
    _verificationModule = null;
    _templateExtractor = null;
    _livenessEstimator = null;
    _qualityControl = null;
    _fitter = null;
    _detector = null;

    for (final block in blocks) {
      if (block == null) continue;
      try {
        await block.dispose();
      } catch (_) {
        // Continue disposing the remaining native resources.
      }
    }

    final service = _service;
    _service = null;
    _sdkVersion = null;
    service?.dispose();
  }
}
