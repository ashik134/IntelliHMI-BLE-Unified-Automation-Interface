import 'package:camera/camera.dart';

import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';

/// Resolves and safely tears down the front-facing [CameraController] used
/// by both `FaceEnrollmentScreen` and `FaceVerifyScreen`. Pulled out once
/// two screens needed the identical bootstrap/teardown sequence, so a
/// camera-lifecycle bug (like the alignment-rotation one this feature
/// already turned up) only has one place to hide instead of two
/// independently-drifting copies. Each screen still owns its own
/// per-frame processing and `AppLifecycleState` handling — those differ
/// meaningfully between "capture N samples then stop" and "match
/// continuously" — only the camera open/close mechanics are shared here.
class FrontCameraSession {
  FrontCameraSession._();

  static Future<CameraController> open() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: CameraFrameConverter.preferredFormatGroup,
    );
    await controller.initialize();
    return controller;
  }

  /// Stops any active image stream (ignoring errors — the controller may
  /// already be torn down by the platform side) and disposes [controller].
  /// Safe to call with `null`.
  static Future<void> close(CameraController? controller) async {
    if (controller == null) return;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Already torn down — nothing left to do.
    }
    await controller.dispose();
  }
}
