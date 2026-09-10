import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';

/// One head pose in the guided enrollment sequence (spec section 7).
/// [frontal] doubles as the anti-photo liveness gate's pose (paired with
/// a blink challenge — see `FaceEnrollmentService`); [left]/[right]/[up]
/// each act as their own liveness signal via a sustained pose hold, so
/// there's no separate liveness step layered on top of them.
enum FacePose {
  frontal('Look straight at the camera.', 'Front'),
  left('Turn your head slightly left.', 'Left'),
  right('Turn your head slightly right.', 'Right'),
  up('Look slightly up.', 'Up');

  const FacePose(this.instruction, this.label);

  final String instruction;
  final String label;
}

/// Whether [face] currently satisfies [pose]'s target head-angle window,
/// per [config]'s thresholds/sign conventions. Pure function over already-
/// detected angles — no ML Kit/camera dependency.
bool matchesPoseTarget(
  FacePose pose,
  DetectedFace face,
  FaceEnrollmentConfig config,
) {
  final yaw = face.headEulerAngleY;
  final pitch = face.headEulerAngleX;
  if (yaw == null || pitch == null) return false;

  switch (pose) {
    case FacePose.frontal:
      return yaw.abs() <= config.maxFrontalPoseAngle / 2 &&
          pitch.abs() <= config.maxFrontalPoseAngle / 2;
    case FacePose.left:
      return config.yawLeftIsPositive
          ? yaw >= config.leftTurnYawThreshold
          : yaw <= config.leftTurnYawThreshold;
    case FacePose.right:
      return config.yawLeftIsPositive
          ? yaw <= config.rightTurnYawThreshold
          : yaw >= config.rightTurnYawThreshold;
    case FacePose.up:
      return config.pitchUpIsPositive
          ? pitch >= config.lookUpPitchThreshold
          : pitch <= config.lookUpPitchThreshold;
  }
}

/// Which landmarks a given [pose] realistically still shows and therefore
/// requires — e.g. a left turn foreshortens/hides the right cheek, so
/// `FaceGeometryValidator` shouldn't fail the frame just because that one
/// landmark went unreported.
class PoseLandmarkRequirements {
  const PoseLandmarkRequirements({
    required this.requireLeftEye,
    required this.requireRightEye,
    required this.requireNose,
    required this.requireLeftCheek,
    required this.requireRightCheek,
  });

  factory PoseLandmarkRequirements.forPose(FacePose pose) {
    switch (pose) {
      case FacePose.frontal:
      case FacePose.up:
        return const PoseLandmarkRequirements(
          requireLeftEye: true,
          requireRightEye: true,
          requireNose: true,
          requireLeftCheek: true,
          requireRightCheek: true,
        );
      case FacePose.left:
        // Turning the head to the subject's own left rotates their right
        // cheek toward the camera and their left cheek away from it — so
        // the left cheek landmark is the one that may go unreported.
        return const PoseLandmarkRequirements(
          requireLeftEye: true,
          requireRightEye: true,
          requireNose: true,
          requireLeftCheek: false,
          requireRightCheek: true,
        );
      case FacePose.right:
        return const PoseLandmarkRequirements(
          requireLeftEye: true,
          requireRightEye: true,
          requireNose: true,
          requireLeftCheek: true,
          requireRightCheek: false,
        );
    }
  }

  final bool requireLeftEye;
  final bool requireRightEye;
  final bool requireNose;
  final bool requireLeftCheek;
  final bool requireRightCheek;
}
