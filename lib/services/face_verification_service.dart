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
/// Currently only consumed by the debug-only `FaceVerifyScreen`, but
/// deliberately shaped as a real, swappable-model-safe service (same
/// align → embed → match pipeline as enrollment) rather than screen-local
/// code, since a future face-login flow would need exactly this.
class FaceVerificationService {
  FaceVerificationService({required this.embeddingService});

  final FaceEmbeddingService embeddingService;

  Future<FaceMatchResult> verify({
    required img.Image frame,
    required DetectedFace face,
    required List<FaceTemplate> candidates,
  }) async {
    final aligned = FaceAlignmentService.align(sourceImage: frame, face: face);
    final embedding = await embeddingService.embed(aligned);
    return FaceMatchingService.match(
      liveEmbedding: embedding,
      candidates: candidates,
      currentModelVersion: FaceEmbeddingService.modelVersion,
    );
  }
}
