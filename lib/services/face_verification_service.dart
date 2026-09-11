import 'package:image/image.dart' as img;

import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_match_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/services/face_alignment_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';

/// Turns one already-detected face into a live [FaceMatchResult] against a
/// given set of enrolled templates — the read-only counterpart to
/// `FaceEnrollmentService`. No sample accumulation, no persistence, no
/// duplicate-registration semantics: every call is independent.
///
/// Deliberately shaped as a real, swappable-model-safe service (same
/// align → embed → match pipeline as enrollment) rather than screen-local
/// code. [embed] and [match] are split apart (rather than only exposing
/// the combined [verify]) so a caller collecting several live frames — see
/// `FaceVerificationScreen` — can pool their embeddings with
/// `FaceEmbeddingService.averageEmbeddings` and match once against the
/// averaged result, instead of matching each noisy frame independently.
class FaceVerificationService {
  FaceVerificationService({required this.embeddingService});

  final FaceEmbeddingService embeddingService;

  Future<List<double>> embed({
    required img.Image frame,
    required DetectedFace face,
  }) async {
    final aligned = FaceAlignmentService.align(sourceImage: frame, face: face);
    return embeddingService.embed(aligned);
  }

  FaceMatchResult match({
    required List<double> embedding,
    required List<FaceTemplate> candidates,
  }) {
    return FaceMatchingService.match(
      liveEmbedding: embedding,
      candidates: candidates,
      currentModelVersion: FaceEmbeddingService.modelVersion,
    );
  }

  /// Convenience wrapper over [embed] + [match] for a single frame — used
  /// by the debug-only `FaceVerifyScreen`, which shows a per-attempt result
  /// rather than pooling frames.
  Future<FaceMatchResult> verify({
    required img.Image frame,
    required DetectedFace face,
    required List<FaceTemplate> candidates,
  }) async {
    final embedding = await embed(frame: frame, face: face);
    return match(embedding: embedding, candidates: candidates);
  }
}
