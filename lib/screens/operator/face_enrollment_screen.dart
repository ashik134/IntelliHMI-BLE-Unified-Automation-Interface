import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/face_capture_diagnostics.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_result.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_enrollment_worker.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_diagnostics_panel.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_illumination_overlay.dart';
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
/// Camera-display concerns (preview aspect/rotation) are handled only in
/// [build] below (via `_CoverCameraPreview`), entirely separate from
/// ML-processing coordinates (`CameraFrameConverter`, `FaceDetectionService`,
/// `FaceEnrollmentService`). The preview is shown in the camera's true,
/// non-mirrored orientation — matching exactly what the raw buffer handed
/// to the ML pipeline sees — so the on-screen guide oval and the
/// acceptance region it represents never disagree.
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
  FaceEnrollmentWorker? _worker;
  StreamSubscription<FaceEnrollmentUpdate>? _workerSubscription;

  _ScreenPhase _phase = _ScreenPhase.initializing;
  FaceEnrollmentState _captureState = const FaceEnrollmentState.initial();
  FaceCaptureDiagnostics _diagnostics = const FaceCaptureDiagnostics.empty();
  bool _busyFrame = false;
  bool _finalizing = false;

  /// Throttles the image-stream callback to roughly 5-8 FPS — detection
  /// and the worker handoff only run on frames that clear this, rather
  /// than on every frame the camera plugin delivers (30-60/sec). Replaces
  /// the old single-flight [_busyFrame] guard's incidental throttling
  /// effect: that guard only ever protected against *overlapping* work
  /// (see [_onFrame]), it never bounded the rate on its own.
  DateTime? _lastFrameSampledAt;

  static const Duration _frameSampleInterval = Duration(milliseconds: 150);

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
    unawaited(DeviceType.restoreDefaultOrientations());
    unawaited(_disposeCamera());
    unawaited(_restoreBrightness());
    unawaited(_detectionService?.close());
    unawaited(_workerSubscription?.cancel());
    // The worker's IsolateInterpreter must finish closing its own nested
    // isolate before the main-isolate interpreter it's attached to is
    // deleted — see FaceEnrollmentWorker.dispose's doc comment — so
    // _embeddingService is only closed once (or if) worker teardown
    // completes, never in parallel with it.
    final worker = _worker;
    final embeddingService = _embeddingService;
    if (worker != null) {
      unawaited(worker.dispose().whenComplete(() => embeddingService?.close()));
    } else {
      embeddingService?.close();
    }
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
  /// verification (`FaceVerifyScreen`) never calls this, matching the
  /// "enrollment only" requirement for screen illumination.
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
  /// times, including when illumination was never activated (a no-op past
  /// the first two lines) — every exit from the capture phase (finalize,
  /// cancel, backgrounding, dispose) calls this so the device is never left
  /// brighter than the operator had it, matching the "never permanently
  /// modify brightness" requirement.
  ///
  /// Deliberately does not call `setState` itself: [_illuminationActive]
  /// flips synchronously (before the first `await` below), so every
  /// existing `setState` at each call site already picks up the new value
  /// on its next rebuild without this needing its own.
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

      final worker = await FaceEnrollmentWorker.spawn(
        interpreterAddress: embeddingService.address,
        operatorId: widget.operatorId,
        templateRepository: widget.templateRepository,
      );
      if (!mounted) {
        await detectionService.close();
        await worker.dispose();
        embeddingService.close();
        return;
      }

      _detectionService = detectionService;
      _embeddingService = embeddingService;
      _worker = worker;
      _workerSubscription = worker.updates.listen(_onWorkerUpdate);

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

  /// Frame sampler: throttles the raw ~30-60 FPS image-stream callback
  /// down to [_frameSampleInterval] before detection even runs, then
  /// [_busyFrame] guards against overlapping detect-and-dispatch calls in
  /// case one takes longer than the sample interval. This is deliberately
  /// separate from the worker's own "latest wins" mailbox
  /// (`FaceEnrollmentWorker.submitFrame`) — this throttle bounds how often
  /// this isolate even attempts detection; that mailbox separately bounds
  /// how far the worker can fall behind once a frame is handed to it.
  void _onFrame(CameraImage image) {
    if (_busyFrame || _finalizing) return;
    final now = DateTime.now();
    if (_lastFrameSampledAt != null &&
        now.difference(_lastFrameSampledAt!) < _frameSampleInterval) {
      return;
    }
    _lastFrameSampledAt = now;
    _busyFrame = true;
    unawaited(_detectAndDispatch(image).whenComplete(() => _busyFrame = false));
  }

  /// Runs face detection (ML Kit stays on this isolate — see
  /// `FaceDetectionService`'s class doc comment) and hands the raw plane
  /// bytes plus the detected faces off to [_worker]. Everything expensive
  /// (decode, quality/liveness gates, alignment, embedding) happens inside
  /// the worker isolate from here on — see [_onWorkerUpdate].
  Future<void> _detectAndDispatch(CameraImage image) async {
    final controller = _cameraController;
    final detectionService = _detectionService;
    final worker = _worker;
    if (controller == null || detectionService == null || worker == null) {
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

    final plane = image.planes.first;
    worker.submitFrame(
      bytes: plane.bytes,
      bytesPerRow: plane.bytesPerRow,
      width: image.width,
      height: image.height,
      formatGroup: image.format.group,
      rotationDegrees: rotation,
      faces: faces,
      imageSize: imageSize,
    );
  }

  /// Renders whatever the worker reports for one processed frame, and
  /// reacts once to the scan actually completing — mirrors what used to be
  /// the tail of `_processFrame`/`_finalize`, just split across the two
  /// separate updates [FaceEnrollmentWorker] sends for that moment (see
  /// `FaceEnrollmentUpdate.result`'s doc comment).
  void _onWorkerUpdate(FaceEnrollmentUpdate update) {
    if (!mounted) return;
    setState(() {
      _captureState = update.state;
      final diagnostics = update.diagnostics;
      if (diagnostics != null) _diagnostics = diagnostics;
    });

    if (update.state.status == FaceEnrollmentStatus.processing && !_finalizing) {
      _finalizing = true;
      unawaited(_stopImageStream());
    }

    final result = update.result;
    if (result != null) {
      unawaited(_handleFinalizeResult(result));
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller != null && controller.value.isStreamingImages) {
      try {
        await controller.stopImageStream();
      } catch (_) {
        // Ignore — screen is about to show an outcome regardless.
      }
    }
  }

  Future<void> _handleFinalizeResult(FaceEnrollmentResult result) async {
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
    _worker?.reset();
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

  bool get _isGoodFrame =>
      _captureState.status == FaceEnrollmentStatus.livenessChallenge ||
      _captureState.status == FaceEnrollmentStatus.scanning ||
      _captureState.status == FaceEnrollmentStatus.processing ||
      _captureState.status == FaceEnrollmentStatus.complete;

  bool get _isProblem =>
      _captureState.status == FaceEnrollmentStatus.multipleFaces ||
      _captureState.status == FaceEnrollmentStatus.duplicateDetected ||
      _captureState.status == FaceEnrollmentStatus.failed ||
      _captureState.status == FaceEnrollmentStatus.cameraError ||
      _captureState.status == FaceEnrollmentStatus.permissionDenied;

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
            // the camera's native aspect ratio — `CameraPreview` sizes itself
            // via an internal `AspectRatio`, which a bare `Stack.expand`
            // parent would force to stretch non-uniformly instead of
            // respecting it.
            _CoverCameraPreview(controller: controller),
            Container(color: Colors.black.withAlpha(60)),
            // Screen-as-light-source: opaque white outside the guide oval,
            // fully transparent inside it (see the widget's own doc
            // comment). Sits below the guide ring so the ring reads as the
            // seam between "illuminated surround" and "live preview."
            FaceIlluminationOverlay(
              active: _illuminationActive,
              ovalDiameter: guideDiameter,
            ),
            FaceCaptureOverlay(
              caption: _captureState.caption,
              guideColor: _guideColor,
              guideDiameter: guideDiameter,
              scanProgress:
                  (_captureState.status == FaceEnrollmentStatus.scanning ||
                          _captureState.status ==
                              FaceEnrollmentStatus.livenessChallenge)
                      ? _captureState.scanProgress
                      : null,
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
/// of stretching it, and never mirroring. `CameraPreview` sizes itself via
/// an internal `AspectRatio`, but a tight-constraining parent (a plain
/// `Stack.expand` child) forces that `AspectRatio` to just fill the given
/// box, silently ignoring the ratio and stretching the image unevenly.
/// Giving it loose constraints (via [Center]) first lets it size itself
/// correctly, then [Transform.scale] enlarges that correctly-proportioned
/// image just enough to cover the available space, centered, clipped by
/// the parent [Stack]'s default hard-edge clip.
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
