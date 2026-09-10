import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'package:rev_crane_control_ops/config/face_enrollment_config.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_capture_diagnostics.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_pose.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_enrollment_service.dart';
import 'package:rev_crane_control_ops/services/face_geometry_validator.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_diagnostics_panel.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_illumination_overlay.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_pose_checklist.dart';
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

/// Live front-camera guided-pose face-enrollment capture flow (spec
/// sections 2-17): automatically walks the operator through
/// `FaceEnrollmentService.poseSequence` (Front/Left/Right/Up by default),
/// showing live checklist progress, and pops with a [FaceTemplate] once
/// every pose has a high-quality, mutually-consistent sample and the
/// resulting template clears the duplicate-face check — or `null` on
/// cancel/permission-denied/unrecoverable failure.
///
/// Nothing is ever written to disk by this screen or by
/// [FaceEnrollmentService] — persistence is the caller's job
/// (`AddOperatorScreen`/`OperatorDetailScreen`).
///
/// Camera-display concerns (preview aspect/rotation) stay entirely
/// separate from ML-processing coordinates, same as before: the preview
/// shows the camera's true, non-mirrored orientation, matching exactly
/// what's fed to the detection/embedding pipeline, so the on-screen guide
/// oval and the acceptance region it represents never disagree.
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

  /// The device's application-level brightness exactly as
  /// [_activateIllumination] found it, saved once per illuminated session
  /// so it can be restored byte-for-byte — never a hardcoded/assumed
  /// default. Null whenever illumination isn't currently active.
  double? _originalBrightness;

  /// Drives [FaceIlluminationOverlay]'s fade — true only while this screen
  /// has both raised the screen brightness and is showing the white
  /// illumination ring (see [_activateIllumination]/[_restoreBrightness]).
  bool _illuminationActive = false;

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
    unawaited(_restoreBrightness());
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
      unawaited(_restoreBrightness());
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

  /// Turns the screen itself into a front-facing light source: saves
  /// whatever application brightness is currently in effect (once per
  /// illuminated session — the `??=` means a resume-from-background
  /// reactivation can't clobber the true original with the already-raised
  /// value), then raises it to maximum and fades in
  /// [FaceIlluminationOverlay]'s white ring around the guide oval. Only
  /// ever called while entering/re-entering [_ScreenPhase.capturing] —
  /// verification screens never call this, matching the "enrollment only"
  /// requirement for screen illumination.
  ///
  /// Silently gives up on any platform error (brightness control can be
  /// unsupported or permission-gated) — illumination is a UX enhancement,
  /// never a precondition for enrollment to work.
  Future<void> _activateIllumination() async {
    try {
      _originalBrightness ??= await ScreenBrightness().application;
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {
      return;
    }
    if (!mounted || _phase != _ScreenPhase.capturing) return;
    setState(() => _illuminationActive = true);
  }

  /// Restores exactly the brightness [_activateIllumination] found in
  /// place before it ran, and clears [_illuminationActive] so
  /// [FaceIlluminationOverlay] fades back out. Safe to call any number of
  /// times, including when illumination was never activated.
  Future<void> _restoreBrightness() async {
    final original = _originalBrightness;
    _originalBrightness = null;
    _illuminationActive = false;
    if (original == null) return;
    try {
      await ScreenBrightness().setApplicationScreenBrightness(original);
    } catch (_) {
      // Best-effort — nothing further to do if the platform rejects it.
    }
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
      unawaited(_activateIllumination());
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

    final rotation = CameraFrameConverter.rotationDegrees(
      controller.description,
      controller.value.deviceOrientation,
    );
    final inputImage = CameraFrameConverter.toInputImage(
      image,
      controller.description,
      controller.value.deviceOrientation,
    );
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final faces = await detectionService.detectFaces(
      inputImage,
      imageSize,
      rotationDegrees: rotation,
    );

    // Debug-only: precompute the RGB frame once here (reused below by
    // evaluateAndCapture's frameProvider instead of decoding it a second
    // time) so the live diagnostics panel has real numbers to show. In a
    // release build this block never runs, so release behavior is
    // unchanged from before diagnostics existed.
    img.Image? precomputedFrame;
    if (kDebugMode && faces.length == 1) {
      precomputedFrame = CameraFrameConverter.toRgbImage(image);
    }

    final state = await enrollmentService.evaluateAndCapture(
      frameProvider: () =>
          precomputedFrame ?? CameraFrameConverter.toRgbImage(image),
      faces: faces,
      imageSize: imageSize,
      rotationDegrees: rotation,
    );

    if (kDebugMode) {
      _diagnostics = precomputedFrame != null
          ? _buildDiagnostics(
              faces.single,
              imageSize,
              rotation,
              precomputedFrame,
              enrollmentService,
              state,
            )
          : FaceCaptureDiagnostics(faceCount: faces.length);
    }

    if (!mounted) return;
    setState(() => _captureState = state);

    if (state.phase == FaceEnrollmentPhase.generatingTemplate &&
        !_finalizing) {
      await _finalize();
    }
  }

  /// Debug-only (see [kDebugMode] guard at the call site). Reuses the
  /// exact same checks the real capture gate runs
  /// (`FaceDetectionService.evaluateQuality`, `FaceGeometryValidator`,
  /// `FrameQualityAnalyzer`, `matchesPoseTarget`) so this readout can
  /// never disagree with what actually gated the frame — in particular,
  /// the raw yaw/pitch numbers here are what you check on first device
  /// run to confirm left/right/up register in the expected physical
  /// direction (see `FaceEnrollmentConfig.yawLeftIsPositive`/
  /// `pitchUpIsPositive`).
  static FaceCaptureDiagnostics _buildDiagnostics(
    DetectedFace face,
    Size imageSize,
    int rotationDegrees,
    img.Image frame,
    FaceEnrollmentService enrollmentService,
    FaceEnrollmentState state,
  ) {
    final quality = FaceDetectionService.evaluateQuality(
      [face],
      imageSize,
      rotationDegrees: rotationDegrees,
    );
    final pixel = FrameQualityAnalyzer.diagnose(frame, face.boundingBox);
    final pose = enrollmentService.debugCurrentPose;
    final geometry = pose == null
        ? null
        : FaceGeometryValidator.evaluate(
            face: face,
            imageSize: imageSize,
            rotationDegrees: rotationDegrees,
            pose: pose,
          );
    final readyForCapture =
        quality.sizePassed &&
        quality.centerPassed &&
        quality.posePassed &&
        quality.eyesPassed &&
        pixel.brightnessPassed &&
        pixel.sharpnessPassed &&
        (geometry?.passed ?? false);
    final failedReason = !quality.passed
        ? quality.primaryMessage
        : (!pixel.brightnessPassed
              ? FaceQualityIssue.poorLighting.guidance
              : (!pixel.sharpnessPassed
                    ? FaceQualityIssue.tooBlurry.guidance
                    : null));

    return FaceCaptureDiagnostics(
      faceCount: 1,
      yawDegrees: face.headEulerAngleY,
      pitchDegrees: face.headEulerAngleX,
      faceWidthFraction: quality.widthFraction,
      centerOffsetFraction: quality.centerOffsetFraction,
      brightness: pixel.brightness,
      sharpness: pixel.sharpness,
      sizePassed: quality.sizePassed,
      centerPassed: quality.centerPassed,
      posePassed: quality.posePassed,
      eyesPassed: quality.eyesPassed,
      brightnessPassed: pixel.brightnessPassed,
      sharpnessPassed: pixel.sharpnessPassed,
      stableProgress: enrollmentService.stableProgress,
      scanning: enrollmentService.isCapturingPose,
      scanProgress: enrollmentService.isCapturingPose ? state.progress : null,
      identityLocked: enrollmentService.hasIdentityAnchor,
      samplesAccepted: enrollmentService.samplesCaptured,
      readyForCapture: readyForCapture,
      failedReason: failedReason,
      currentPoseLabel: pose?.label,
      poseMatched: pose == null
          ? null
          : matchesPoseTarget(pose, face, FaceEnrollmentConfig.defaults),
      landmarksPresent: geometry?.landmarksPresent,
      landmarksContained: geometry?.landmarksContained,
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
    unawaited(_restoreBrightness());
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
    unawaited(_activateIllumination());
    final controller = _cameraController;
    if (controller != null && !controller.value.isStreamingImages) {
      await controller.startImageStream(_onFrame);
    }
  }

  void _cancel() {
    unawaited(_restoreBrightness());
    Navigator.of(context).pop();
  }

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
          message:
              'This face is already registered to another operator.',
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

  bool get _isGoodFrame =>
      _captureState.phase == FaceEnrollmentPhase.livenessCheck ||
      _captureState.phase == FaceEnrollmentPhase.capturingPose ||
      _captureState.phase == FaceEnrollmentPhase.generatingTemplate ||
      _captureState.phase == FaceEnrollmentPhase.complete;

  bool get _isProblem =>
      _captureState.blockingIssue == FaceQualityIssue.multipleFacesDetected ||
      _captureState.phase == FaceEnrollmentPhase.duplicateDetected ||
      _captureState.phase == FaceEnrollmentPhase.failed ||
      _captureState.phase == FaceEnrollmentPhase.cameraError ||
      _captureState.phase == FaceEnrollmentPhase.permissionDenied;

  Color get _guideColor {
    if (_isProblem) return AppColors.brandDanger;
    if (_isGoodFrame) return AppColors.brandSuccess;
    return Colors.white.withAlpha(210);
  }

  Widget _buildCapture(BuildContext context) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandViolet),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Sized so "inside this circle" and "passes the centering check"
        // are the same statement — see `centerToleranceRadiusPx`'s doc
        // comment. Computed from layout constraints, not per ML frame:
        // depends only on screen size/camera aspect ratio, both stable
        // for the life of this capture session.
        final guideDiameter =
            2 *
            FaceDetectionService.centerToleranceRadiusPx(
              screenSize: constraints.biggest,
              cameraAspectRatio: controller.value.aspectRatio,
            );

        return Stack(
          fit: StackFit.expand,
          children: [
            // True (non-mirrored) orientation — shown exactly as the sensor
            // captures it, matching the frames fed to ML Kit/the embedding
            // pipeline, which are never mirrored either (see class doc
            // comment). Scaled to cover the full screen without distorting
            // the camera's native aspect ratio.
            _CoverCameraPreview(controller: controller),
            Container(color: Colors.black.withAlpha(60)),
            // Screen-as-light-source: opaque white outside the guide oval,
            // fully transparent inside it.
            FaceIlluminationOverlay(
              active: _illuminationActive,
              ovalDiameter: guideDiameter,
            ),
            FaceCaptureOverlay(
              caption: _captureState.caption,
              guideColor: _guideColor,
              guideDiameter: guideDiameter,
              scanProgress:
                  (_captureState.phase == FaceEnrollmentPhase.capturingPose ||
                          _captureState.phase ==
                              FaceEnrollmentPhase.livenessCheck)
                      ? _captureState.progress
                      : null,
            ),
            if (_captureState.poses.isNotEmpty)
              Positioned(
                top: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: FacePoseChecklist(poses: _captureState.poses),
                ),
              ),
            if (kDebugMode)
              FaceCaptureDiagnosticsPanel(diagnostics: _diagnostics),
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
      },
    );
  }
}

/// Renders [CameraPreview] scaled to cover its parent's full bounds while
/// preserving the camera's true aspect ratio — cropping overflow instead
/// of stretching it, and never mirroring.
class _CoverCameraPreview extends StatelessWidget {
  const _CoverCameraPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isEmpty) return const SizedBox.shrink();

        var scale = size.aspectRatio * controller.value.aspectRatio;
        if (scale < 1) scale = 1 / scale;

        return ClipRect(
          child: Transform.scale(
            scale: scale,
            child: Center(child: CameraPreview(controller)),
          ),
        );
      },
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
