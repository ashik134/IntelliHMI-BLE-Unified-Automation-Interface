import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_capture_diagnostics.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_enrollment_service.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_diagnostics_panel.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

enum _ScreenPhase {
  initializing,
  permissionDenied,
  cameraError,
  capturing,
  duplicate,
  failed,
  success,
}

/// Live front-camera face-enrollment capture flow.
///
/// Pops with a [FaceTemplate] once enough good samples are captured and
/// the representative embedding clears the duplicate-face check, or
/// `null` on cancel/permission-denied/unrecoverable failure. Nothing is
/// ever written to disk by this screen or by `FaceEnrollmentService` —
/// persistence is the caller's job (`AddOperatorScreen`/
/// `OperatorDetailScreen`), so there is never a partial operator/template
/// left behind regardless of how this screen exits.
///
/// Camera-display concerns (front-camera mirroring, preview aspect/
/// rotation) are handled only in [build] below, entirely separate from
/// ML-processing coordinates (`CameraFrameConverter`, `FaceDetectionService`,
/// `FaceEnrollmentService`) — the raw camera buffer handed to the ML
/// pipeline is never mirrored; only the on-screen `CameraPreview` is,
/// purely for a natural selfie-style view.
class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({
    super.key,
    required this.operatorId,
    required this.templateRepository,
  });

  final String operatorId;
  final FaceTemplateRepository templateRepository;

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  FaceDetectionService? _detectionService;
  FaceEmbeddingService? _embeddingService;
  FaceEnrollmentService? _enrollmentService;

  _ScreenPhase _phase = _ScreenPhase.initializing;
  FaceEnrollmentState _captureState = const FaceEnrollmentState.initial();
  FaceCaptureDiagnostics _diagnostics = const FaceCaptureDiagnostics.empty();
  bool _busyFrame = false;
  bool _finalizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // UX-only: keeps the capture layout from awkwardly rotating mid-
    // session. Rotation *compensation* for ML Kit does not depend on
    // this — see `CameraFrameConverter.toInputImage`, which reads the
    // camera plugin's own live-tracked device orientation regardless.
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    unawaited(_initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    unawaited(_disposeCamera());
    unawaited(_detectionService?.close());
    _embeddingService?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_disposeCamera());
    } else if (state == AppLifecycleState.resumed &&
        _phase == _ScreenPhase.capturing) {
      unawaited(_initializeCamera());
    }
  }

  Future<void> _disposeCamera() async {
    final controller = _cameraController;
    _cameraController = null;
    await FrontCameraSession.close(controller);
  }

  Future<void> _initialize() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _phase = _ScreenPhase.permissionDenied);
      return;
    }

    try {
      final detectionService = FaceDetectionService();
      final embeddingService = await FaceEmbeddingService.load();
      if (!mounted) {
        await detectionService.close();
        embeddingService.close();
        return;
      }

      _detectionService = detectionService;
      _embeddingService = embeddingService;
      _enrollmentService = FaceEnrollmentService(
        embeddingService: embeddingService,
        templateRepository: widget.templateRepository,
      );

      await _initializeCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScreenPhase.cameraError);
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final controller = await FrontCameraSession.open();
      if (!mounted) {
        await FrontCameraSession.close(controller);
        return;
      }

      _cameraController = controller;
      setState(() => _phase = _ScreenPhase.capturing);
      await controller.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScreenPhase.cameraError);
    }
  }

  void _onFrame(CameraImage image) {
    if (_busyFrame || _finalizing) return;
    _busyFrame = true;
    unawaited(_processFrame(image).whenComplete(() => _busyFrame = false));
  }

  Future<void> _processFrame(CameraImage image) async {
    final controller = _cameraController;
    final detectionService = _detectionService;
    final enrollmentService = _enrollmentService;
    if (controller == null ||
        detectionService == null ||
        enrollmentService == null) {
      return;
    }

    final inputImage = CameraFrameConverter.toInputImage(
      image,
      controller.description,
      controller.value.deviceOrientation,
    );
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final faces = await detectionService.detectFaces(inputImage, imageSize);

    // Debug-only: precompute the RGB frame once here (reused below by
    // evaluateAndCapture's frameProvider instead of decoding it a second
    // time) so the live diagnostics panel has real numbers to show. In a
    // release build this block never runs, so release behavior is
    // unchanged from before diagnostics existed — evaluateAndCapture's
    // frameProvider still decodes lazily, only if actually needed.
    img.Image? precomputedFrame;
    if (kDebugMode) {
      if (faces.length == 1) {
        precomputedFrame = CameraFrameConverter.toRgbImage(image);
        _diagnostics = _buildDiagnostics(faces.single, imageSize, precomputedFrame);
      } else {
        _diagnostics = FaceCaptureDiagnostics(faceCount: faces.length);
      }
    }

    final state = await enrollmentService.evaluateAndCapture(
      frameProvider: () =>
          precomputedFrame ?? CameraFrameConverter.toRgbImage(image),
      faces: faces,
      imageSize: imageSize,
    );
    if (!mounted) return;
    setState(() => _captureState = state);

    final reachedTarget = state.status == FaceEnrollmentStatus.processing &&
        state.samplesCaptured >= state.samplesRequired;
    if (reachedTarget && !_finalizing) {
      await _finalize();
    }
  }

  /// Debug-only (see [kDebugMode] guard at the call site). Reuses
  /// `FaceEmbeddingService.cropToFace` — the same crop the real embedding
  /// pipeline uses — so the brightness/sharpness numbers shown match what
  /// the actual quality gate is evaluating, not a different region.
  static FaceCaptureDiagnostics _buildDiagnostics(
    DetectedFace face,
    Size imageSize,
    img.Image frame,
  ) {
    final crop = FaceEmbeddingService.cropToFace(frame, face.boundingBox);
    return FaceCaptureDiagnostics(
      faceCount: 1,
      yawDegrees: face.headEulerAngleY,
      pitchDegrees: face.headEulerAngleX,
      faceWidthFraction: face.boundingBox.width / imageSize.width,
      brightness: FrameQualityAnalyzer.estimateBrightness(crop),
      sharpness: FrameQualityAnalyzer.estimateSharpness(crop),
    );
  }

  Future<void> _finalize() async {
    final enrollmentService = _enrollmentService;
    if (enrollmentService == null || _finalizing) return;
    _finalizing = true;

    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // Ignore — screen is about to show an outcome regardless.
      }
    }

    final result = await enrollmentService.finalizeEnrollment(
      operatorId: widget.operatorId,
    );
    if (!mounted) return;

    if (result.success) {
      setState(() => _phase = _ScreenPhase.success);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      Navigator.of(context).pop(result.template);
      return;
    }

    setState(() {
      _phase = result.failureReason == FaceEnrollmentFailureReason.duplicateFace
          ? _ScreenPhase.duplicate
          : _ScreenPhase.failed;
    });
  }

  Future<void> _retry() async {
    _enrollmentService?.reset();
    _finalizing = false;
    setState(() {
      _phase = _ScreenPhase.capturing;
      _captureState = const FaceEnrollmentState.initial();
    });
    final controller = _cameraController;
    if (controller != null && !controller.value.isStreamingImages) {
      await controller.startImageStream(_onFrame);
    }
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _ScreenPhase.success,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _buildBody(context)),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _ScreenPhase.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandViolet),
        );
      case _ScreenPhase.permissionDenied:
        return _MessageState(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission required',
          message:
              'IntelliHMI needs camera access to enroll an operator\'s '
              'face. Grant it in system settings, then try again.',
          primaryLabel: 'Open Settings',
          onPrimary: () => unawaited(openAppSettings()),
          onCancel: _cancel,
        );
      case _ScreenPhase.cameraError:
        return _MessageState(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          message:
              'The camera could not be started. Close any other app using '
              'it and try again.',
          primaryLabel: 'Retry',
          onPrimary: () {
            setState(() => _phase = _ScreenPhase.initializing);
            unawaited(_initialize());
          },
          onCancel: _cancel,
        );
      case _ScreenPhase.duplicate:
        return _MessageState(
          icon: Icons.person_search_rounded,
          title: 'Already registered',
          message: FaceEnrollmentStatus.duplicateDetected.caption,
          tone: BrandTone.danger,
          primaryLabel: 'Try Again',
          onPrimary: () => unawaited(_retry()),
          onCancel: _cancel,
        );
      case _ScreenPhase.failed:
        return _MessageState(
          icon: Icons.error_outline_rounded,
          title: 'Enrollment failed',
          message:
              'Could not capture a clear, consistent set of samples. Make '
              'sure your face is well lit and hold steady, then try again.',
          tone: BrandTone.danger,
          primaryLabel: 'Try Again',
          onPrimary: () => unawaited(_retry()),
          onCancel: _cancel,
        );
      case _ScreenPhase.success:
        return const _MessageState(
          icon: Icons.check_circle_rounded,
          title: 'Enrollment complete',
          message: 'Face captured successfully.',
          tone: BrandTone.success,
        );
      case _ScreenPhase.capturing:
        return _buildCapture(context);
    }
  }

  Widget _buildCapture(BuildContext context) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandViolet),
      );
    }

    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Mirroring is applied ONLY here, for display — the frames fed to
        // ML Kit/the embedding pipeline are never touched by this
        // transform (see class doc comment).
        Transform(
          alignment: Alignment.center,
          transform: isFrontCamera
              ? Matrix4.rotationY(math.pi)
              : Matrix4.identity(),
          child: CameraPreview(controller),
        ),
        Container(color: Colors.black.withAlpha(60)),
        FaceCaptureOverlay(state: _captureState),
        if (kDebugMode) FaceCaptureDiagnosticsPanel(diagnostics: _diagnostics),
        Positioned(
          top: 8,
          left: 8,
          child: BrandIconButton(
            icon: Icons.close_rounded,
            dark: true,
            tooltip: 'Cancel',
            onTap: _cancel,
          ),
        ),
      ],
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.message,
    this.tone = BrandTone.info,
    this.primaryLabel,
    this.onPrimary,
    this.onCancel,
  });

  final IconData icon;
  final String title;
  final String message;
  final BrandTone tone;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandStatusBanner(icon: icon, title: title, message: message, tone: tone),
            if (primaryLabel != null) ...[
              const SizedBox(height: 20),
              BrandPrimaryButton(label: primaryLabel!, onPressed: onPrimary),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              BrandSecondaryButton(label: 'Cancel', onPressed: onCancel),
            ],
          ],
        ),
      ),
    );
  }
}
