import 'dart:typed_data';

import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_audit_event.dart';
import 'package:rev_crane_control_ops/features/operator_auth/domain/operator_record.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';

enum OperatorIdentificationStatus {
  authenticated,
  unknown,
  disabled,
  livenessFailed,
  spoofRejected,
  failed,
}

class OperatorIdentificationResult {
  const OperatorIdentificationResult({
    required this.status,
    required this.message,
    this.operator,
    this.score,
  });

  final OperatorIdentificationStatus status;
  final String message;
  final OperatorRecord? operator;
  final double? score;

  bool get isAuthenticated =>
      status == OperatorIdentificationStatus.authenticated && operator != null;
}

/// Applies IntelliHMI authentication policy around the official 3DiVi 1:N
/// matcher. The SDK returns ranked candidates; this service is deliberately
/// responsible for thresholds, ambiguity, operator state, auditing, and
/// clearing all decrypted biometric buffers.
class OperatorIdentificationService {
  OperatorIdentificationService({
    required OperatorRepository repository,
    required FaceRecognitionEngine engine,
    this.minimumAcceptedScore = 0.90,
    this.minimumScoreSeparation = 0.04,
  }) : _repository = repository,
       _engine = engine;

  final OperatorRepository _repository;
  final FaceRecognitionEngine _engine;

  /// Conservative commissioning value. It must be calibrated against the
  /// customer's device/camera population before production acceptance.
  final double minimumAcceptedScore;

  /// A high top score is still rejected when the next candidate is too close.
  final double minimumScoreSeparation;

  Future<OperatorIdentificationResult> identify(
    FaceEnrollmentCapture capture,
  ) async {
    final query = capture.templateBytes;
    List<DecryptedOperatorTemplate> population = const [];
    final galleryCopies = <FaceGalleryTemplate>[];

    try {
      if (capture.analysis.liveness == FaceLivenessVerdict.fake) {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.spoofRejected,
          result: OperatorAuditResult.rejected,
          failureReason:
              '3DiVi passive liveness/PAD classified the face as fake.',
        );
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.spoofRejected,
          message: 'Spoof detected. Control access was rejected.',
        );
      }
      if (capture.analysis.liveness != FaceLivenessVerdict.real) {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.livenessFailed,
          result: OperatorAuditResult.rejected,
          failureReason: '3DiVi liveness/PAD did not produce a real verdict.',
        );
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.livenessFailed,
          message:
              'Liveness could not be confirmed. Control access was rejected.',
        );
      }
      if (capture.analysis.qualityAccepted != true ||
          query == null ||
          query.isEmpty ||
          capture.templateMethod == null) {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.faceAuthenticationFailed,
          result: OperatorAuditResult.failure,
          failureReason:
              'No valid quality-accepted query template was produced.',
        );
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.failed,
          message:
              'A valid biometric template could not be captured. Try again.',
        );
      }

      population = await _repository.loadEnrolledTemplates();
      if (population.isEmpty) {
        await _recordUnknown('No enrolled operators are available.');
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.unknown,
          message:
              'No operators are registered. Registration must be completed through administrator-protected Settings.',
        );
      }

      final matchingMethod = population
          .where((entry) => entry.method == capture.templateMethod)
          .toList(growable: false);
      if (matchingMethod.isEmpty) {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.faceAuthenticationFailed,
          result: OperatorAuditResult.failure,
          failureReason: 'Enrolled templates use an incompatible SDK method.',
        );
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.failed,
          message:
              'Enrolled biometric data is incompatible with this SDK configuration.',
        );
      }

      for (final entry in matchingMethod) {
        galleryCopies.add(
          FaceGalleryTemplate(
            id: entry.operator.id,
            templateBytes: Uint8List.fromList(entry.templateBytes),
          ),
        );
      }
      final candidates = await _engine.identifyTemplate(
        query,
        galleryCopies,
        maxResults: galleryCopies.length > 1 ? 2 : 1,
      );
      if (candidates.isEmpty || candidates.first.score < minimumAcceptedScore) {
        await _recordUnknown(
          'Identification confidence was below policy threshold.',
        );
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.unknown,
          message:
              'Face not registered. Ask an administrator to complete registration in Settings.',
        );
      }

      final best = candidates.first;
      if (candidates.length > 1 &&
          best.score - candidates[1].score < minimumScoreSeparation) {
        await _recordUnknown('Identification result was ambiguous.');
        return const OperatorIdentificationResult(
          status: OperatorIdentificationStatus.unknown,
          message:
              'Face could not be identified with sufficient confidence. Access was rejected.',
        );
      }

      OperatorRecord? matched;
      for (final entry in matchingMethod) {
        if (entry.operator.id == best.galleryId) {
          matched = entry.operator;
          break;
        }
      }
      if (matched == null) {
        throw StateError(
          '3DiVi matcher returned an unknown gallery identifier.',
        );
      }
      if (!matched.enabled || matched.isDeleted) {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.disabledOperatorRejected,
          result: OperatorAuditResult.rejected,
          operator: matched,
          failureReason: 'The identified operator is disabled.',
        );
        return OperatorIdentificationResult(
          status: OperatorIdentificationStatus.disabled,
          message: 'This operator is disabled. Control access was rejected.',
          operator: matched,
          score: best.score,
        );
      }

      await _repository.recordAuthenticationEvent(
        type: OperatorAuditEventType.faceAuthenticationSucceeded,
        result: OperatorAuditResult.success,
        operator: matched,
      );
      return OperatorIdentificationResult(
        status: OperatorIdentificationStatus.authenticated,
        message: 'Face authentication successful.',
        operator: matched,
        score: best.score,
      );
    } catch (_) {
      try {
        await _repository.recordAuthenticationEvent(
          type: OperatorAuditEventType.faceAuthenticationFailed,
          result: OperatorAuditResult.failure,
          failureReason: 'Biometric identification could not be completed.',
        );
      } catch (_) {
        // Authentication already fails closed if its audit store is unavailable.
      }
      return const OperatorIdentificationResult(
        status: OperatorIdentificationStatus.failed,
        message:
            'Face authentication is unavailable. Control access remains locked.',
      );
    } finally {
      if (query != null) _wipe(query);
      for (final entry in galleryCopies) {
        _wipe(entry.templateBytes);
      }
      for (final entry in population) {
        _wipe(entry.templateBytes);
      }
    }
  }

  Future<void> _recordUnknown(String reason) =>
      _repository.recordAuthenticationEvent(
        type: OperatorAuditEventType.unknownFaceRejected,
        result: OperatorAuditResult.rejected,
        failureReason: reason,
      );

  void _wipe(List<int> bytes) {
    for (var index = 0; index < bytes.length; index += 1) {
      bytes[index] = 0;
    }
  }
}
