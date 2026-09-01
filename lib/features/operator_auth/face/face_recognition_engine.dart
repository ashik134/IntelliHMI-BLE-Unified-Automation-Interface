import 'dart:typed_data';

import 'package:camera/camera.dart';

enum FaceLivenessVerdict { notEvaluated, real, fake, inconclusive }

class NormalizedFaceBounds {
  const NormalizedFaceBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class FaceFrameAnalysis {
  const FaceFrameAnalysis({
    required this.faces,
    required this.processingTime,
    this.qualityAccepted,
    this.qualityFailureCode,
    this.liveness = FaceLivenessVerdict.notEvaluated,
    this.livenessConfidence,
  });

  final List<NormalizedFaceBounds> faces;
  final Duration processingTime;
  final bool? qualityAccepted;
  final String? qualityFailureCode;
  final FaceLivenessVerdict liveness;
  final double? livenessConfidence;

  int get faceCount => faces.length;

  String get qualityGuidance {
    switch (qualityFailureCode) {
      case 'face_overflow':
      case 'face_size_on_image':
      case 'eye_distance':
        return 'Center your face and adjust your distance';
      case 'yaw':
      case 'pitch':
        return 'Look directly at the camera';
      case 'dynamic_range':
        return 'Improve the lighting on your face';
      case 'sharpness':
      case 'noise':
        return 'Hold still and improve image clarity';
      case 'glasses':
        return 'Glasses are interfering with the check';
      case 'gray_scale':
        return 'Camera image is not suitable';
      default:
        return 'Improve face position, lighting, and image clarity';
    }
  }
}

class FaceEnrollmentCapture {
  const FaceEnrollmentCapture({
    required this.analysis,
    this.templateBytes,
    this.templateMethod,
  });

  final FaceFrameAnalysis analysis;
  final Uint8List? templateBytes;
  final String? templateMethod;

  bool get succeeded =>
      analysis.qualityAccepted == true &&
      analysis.liveness == FaceLivenessVerdict.real &&
      templateBytes != null &&
      templateBytes!.isNotEmpty &&
      templateMethod != null;
}

class FaceTemplateComparison {
  const FaceTemplateComparison({
    required this.score,
    required this.distance,
    required this.falseAcceptanceRate,
    required this.falseRejectionRate,
  });

  final double score;
  final double distance;
  final double falseAcceptanceRate;
  final double falseRejectionRate;
}

class FaceGalleryTemplate {
  const FaceGalleryTemplate({required this.id, required this.templateBytes});

  /// An application-owned opaque identifier. The 3DiVi matcher returns this
  /// value; it never receives operator names, Employee IDs, or roles.
  final String id;
  final Uint8List templateBytes;
}

class FaceIdentificationCandidate {
  const FaceIdentificationCandidate({
    required this.galleryId,
    required this.score,
    required this.distance,
  });

  final String galleryId;
  final double score;
  final double distance;
}

abstract interface class FaceRecognitionEngine {
  bool get isInitialized;

  String? get sdkVersion;

  Future<void> initialize();

  Future<FaceFrameAnalysis> analyzeCameraFrame(
    CameraImage image, {
    required int rotationQuarterTurns,
  });

  Future<FaceEnrollmentCapture> createEnrollmentTemplate(
    CameraImage image, {
    required int rotationQuarterTurns,
  });

  Future<FaceTemplateComparison> compareTemplates(
    Uint8List first,
    Uint8List second,
  );

  /// Runs an official 3DiVi 1:N search and returns candidates in descending
  /// score order. Policy decisions (threshold, ambiguity, enabled state) stay
  /// outside the SDK adapter.
  Future<List<FaceIdentificationCandidate>> identifyTemplate(
    Uint8List query,
    List<FaceGalleryTemplate> gallery, {
    int maxResults = 2,
  });

  Future<void> dispose();
}

class FaceEngineException implements Exception {
  const FaceEngineException(this.operation, this.details);

  final String operation;
  final String details;

  @override
  String toString() => '$operation failed: $details';
}
