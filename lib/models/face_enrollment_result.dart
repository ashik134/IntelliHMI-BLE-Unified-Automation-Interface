import 'package:rev_crane_control_ops/models/face_template.dart';

/// Why `FaceEnrollmentService.finalizeEnrollment` (or the capture screen
/// hosting it) didn't produce a usable template. Never surfaced as a raw
/// exception to the admin — always mapped to plain-language guidance.
enum FaceEnrollmentFailureReason {
  cancelled,
  cameraFailure,
  permissionDenied,
  qualityTimeout,
  inferenceFailure,
  duplicateFace,
  insufficientSamples,
  storageFailure,
}

/// Outcome of a full enrollment attempt. [template] is only set when
/// [success] is true, and is never persisted by
/// `FaceEnrollmentService` itself — see its class doc comment: the caller
/// (`AddOperatorScreen`/`OperatorDetailScreen`) owns the atomic write.
class FaceEnrollmentResult {
  const FaceEnrollmentResult.success(this.template)
    : success = true,
      failureReason = null;

  const FaceEnrollmentResult.failure(FaceEnrollmentFailureReason reason)
    : success = false,
      template = null,
      failureReason = reason;

  final bool success;
  final FaceTemplate? template;
  final FaceEnrollmentFailureReason? failureReason;
}
