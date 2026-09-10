import 'dart:math' as math;
import 'dart:ui';

import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_pose.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';

/// Result of [FaceGeometryValidator.evaluate].
class FaceGeometryResult {
  const FaceGeometryResult({
    required this.passed,
    required this.landmarksPresent,
    required this.landmarksContained,
    this.worstOffsetFraction,
  });

  /// True when every landmark [PoseLandmarkRequirements] calls for this
  /// pose is both present and within the safe region.
  final bool passed;

  /// False if a landmark [PoseLandmarkRequirements] requires for the
  /// current pose wasn't reported by ML Kit at all (e.g. eyes not
  /// detected) — distinct from [landmarksContained], which is about
  /// *position*, not presence.
  final bool landmarksPresent;

  /// False if a required, present landmark sits outside the safe region
  /// (too close to the oval's edge, or past it).
  final bool landmarksContained;

  /// The largest safe-region-relative offset among the checked landmarks
  /// (1.0 == exactly on the safe-region boundary, >1.0 == outside it) —
  /// for debug diagnostics only.
  final double? worstOffsetFraction;
}

/// Validates that a detected face's facial landmarks stay within a "safe
/// inner region" nested inside the on-screen guide oval (spec section 4),
/// rather than only checking the bounding box's center — a tilted or
/// off-axis face can have a centered bounding box while its nose or a
/// cheek juts toward the oval's edge, which a pure bounding-box check
/// can't see.
///
/// Deliberately works entirely in **upright-image-fraction space**
/// (fraction of the frame's shorter side, measured from the frame's own
/// geometric center) rather than mapping onto Flutter's rendered screen
/// coordinates. This is the same space `FaceDetectionService
/// .maxCenterOffsetFraction`/`centerToleranceRadiusPx` already use to
/// guarantee the drawn guide oval and the bounding-box centering check
/// agree — see that class's doc comments. Reusing it here means "inside
/// the safe region" is resolution/aspect-ratio/device independent by
/// construction, without needing the screen-pixel-to-camera-frame
/// transform this codebase has otherwise deliberately avoided as too
/// fragile to verify without a real device (see `FaceCaptureOverlay`'s
/// doc comment).
class FaceGeometryValidator {
  FaceGeometryValidator._();

  static FaceGeometryResult evaluate({
    required DetectedFace face,
    required Size imageSize,
    required int rotationDegrees,
    required FacePose pose,
    FaceEnrollmentConfig config = FaceEnrollmentConfig.defaults,
  }) {
    final requirements = PoseLandmarkRequirements.forPose(pose);
    final uprightImageSize = FaceDetectionService.uprightSize(
      imageSize,
      rotationDegrees,
    );
    final center = Offset(
      uprightImageSize.width / 2,
      uprightImageSize.height / 2,
    );
    final shortestSide = uprightImageSize.shortestSide == 0
        ? 1.0
        : uprightImageSize.shortestSide;
    final safeRadius = config.safeRegionFraction * shortestSide;

    math.Point<int>? upright(math.Point<int>? raw) {
      if (raw == null) return null;
      final asRect = Rect.fromLTWH(
        raw.x.toDouble(),
        raw.y.toDouble(),
        0,
        0,
      );
      final transformed = FaceDetectionService.uprightRect(
        asRect,
        imageSize,
        rotationDegrees,
      );
      return math.Point<int>(
        transformed.left.round(),
        transformed.top.round(),
      );
    }

    final checks = <(bool required, math.Point<int>? point)>[
      (requirements.requireLeftEye, upright(face.leftEyePosition)),
      (requirements.requireRightEye, upright(face.rightEyePosition)),
      (requirements.requireNose, upright(face.noseBasePosition)),
      (requirements.requireLeftCheek, upright(face.leftCheekPosition)),
      (requirements.requireRightCheek, upright(face.rightCheekPosition)),
    ];

    var landmarksPresent = true;
    var landmarksContained = true;
    double? worstOffsetFraction;

    for (final (required, point) in checks) {
      if (!required) continue;
      if (point == null) {
        landmarksPresent = false;
        continue;
      }
      final offset = Offset(point.x.toDouble(), point.y.toDouble());
      final distance = (offset - center).distance;
      final offsetFraction = distance / safeRadius;
      if (worstOffsetFraction == null || offsetFraction > worstOffsetFraction) {
        worstOffsetFraction = offsetFraction;
      }
      if (distance > safeRadius) {
        landmarksContained = false;
      }
    }

    return FaceGeometryResult(
      passed: landmarksPresent && landmarksContained,
      landmarksPresent: landmarksPresent,
      landmarksContained: landmarksContained,
      worstOffsetFraction: worstOffsetFraction,
    );
  }
}
