import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_verification_service.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

/// Screen-level phase — each one owns a full-screen UI and, for
/// [verified]/[blocked]/[notRecognized], a stopped camera. [scanning]
/// covers the entire live-camera experience; what it shows moment to
/// moment is driven by the finer-grained [_ScanState] below, not by a
/// new top-level phase, so a flickering per-frame signal never has the
/// power to swap the whole screen out from under itself.
enum _Phase {
  initializing,
  permissionDenied,
  cameraError,
  noOperators,
  scanning,
  verified,
  blocked,
  notRecognized,
}

/// Sub-state of [_Phase.scanning] — the state machine this screen was
/// flickering without: `waitingForFace → stabilizing → verifying`, ending
/// in either a match (→ [_Phase.verified]/[_Phase.blocked]) or a *final*
/// [_Phase.notRecognized], never a per-frame flip back and forth between
/// "Hold still" and "Face not recognized".
enum _ScanState { waitingForFace, stabilizing, verifying }

/// Identity gate shown after a BLE connection is established and before the
/// PLC credential (Authentication) screen — see [CraneController.
/// currentScreen] and [CraneController.completeFaceVerification]. Matches
/// live camera frames against enrolled operator face templates using the
/// same detection/embedding/matching pipeline as enrollment and the debug
/// `FaceVerifyScreen`; never modifies that pipeline — this screen only
/// decides *when* to call it and how to combine repeated results.
///
/// Never logs or displays face images, embeddings, or raw similarity
/// scores — only the resolved operator identity is ever surfaced, via
/// [CraneController.completeFaceVerification]/[CraneController.
/// recordFaceVerificationDenied].
class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() =>
      _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  FaceDetectionService? _detectionService;
  FaceEmbeddingService? _embeddingService;
  FaceVerificationService? _verificationService;

  List<FaceTemplate> _templates = const [];
  Map<String, OperatorProfile> _operatorsById = const {};

  _Phase _phase = _Phase.initializing;
  _ScanState _scanState = _ScanState.waitingForFace;
  String _statusMessage = 'Starting camera…';
  OperatorProfile? _matchedOperator;
  bool _busyFrame = false;

  /// Consecutive good frames required before a verification attempt
  /// starts — the "stabilizing" dwell (roughly the ~500-800ms hysteresis
  /// window this state machine is built around; actual wall-clock time
  /// depends on device frame-processing speed).
  static const int _requiredStableFrames = 10;

  /// Verification samples collected (once stabilized) before combining
  /// them into one final decision — a single frame's match/no-match never
  /// decides the outcome on its own.
  static const int _requiredVerificationSamples = 5;

  /// At least this many of [_requiredVerificationSamples] must agree on
  /// the same operator for that operator to be accepted as the result —
  /// a simple majority. Everything else (no agreement, or agreement below
  /// this bar) finalizes as "not recognized".
  static const int _consensusSamplesRequired = 3;

  /// How many *consecutive* bad frames (no face / poor quality / partially
  /// out of frame) are tolerated before the state machine actually resets
  /// progress. Without this, a single blink, a hand passing through frame,
  /// or one bad ML Kit read would instantly throw away a stabilizing or
  /// in-progress verification attempt — which is exactly what produced the
  /// "Hold still" / "Face not recognized" flicker this replaces.
  static const int _maxBadFrameStreak = 6;

  int _stableGoodFrames = 0;
  int _badFrameStreak = 0;

  /// Matched operator id per verification sample collected during
  /// [_ScanState.verifying]; null entries are samples that ran but found
  /// no confident match. Combined into one decision once it reaches
  /// [_requiredVerificationSamples] — see [_finalizeVerification].
  final List<String?> _verificationSamples = [];

  /// Minimum fraction of the (upright) frame's shorter side a face's
  /// bounding box must stay clear of every edge by. Verification-only
  /// guard, not part of the shared `FaceDetectionService.evaluateQuality`
  /// gate: a face cropped by the frame edge (half a face held too close,
  /// or off to one side) can still be large/centered/eyes-open enough to
  /// pass every check in that shared gate, since none of them look at
  /// whether the box touches the frame boundary.
  static const double _edgeMarginFraction = 0.02;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        _phase == _Phase.scanning) {
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
      setState(() => _phase = _Phase.permissionDenied);
      return;
    }

    try {
      final operatorRepository = await OperatorRepository.open();
      final templateRepository = await FaceTemplateRepository.open();
      final operators = await operatorRepository.getAll();
      final templates = await templateRepository.getAll();
      if (!mounted) return;

      _templates = templates;
      _operatorsById = {for (final o in operators) o.operatorId: o};

      if (_templates.isEmpty) {
        setState(() => _phase = _Phase.noOperators);
        return;
      }

      final detectionService = FaceDetectionService();
      final embeddingService = await FaceEmbeddingService.load();
      if (!mounted) {
        await detectionService.close();
        embeddingService.close();
        return;
      }

      _detectionService = detectionService;
      _embeddingService = embeddingService;
      _verificationService = FaceVerificationService(
        embeddingService: embeddingService,
      );

      await _initializeCamera();
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.cameraError);
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
      _resetScanState();
      setState(() => _phase = _Phase.scanning);
      await controller.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.cameraError);
    }
  }

  void _resetScanState() {
    _scanState = _ScanState.waitingForFace;
    _stableGoodFrames = 0;
    _badFrameStreak = 0;
    _verificationSamples.clear();
    _matchedOperator = null;
    _statusMessage = 'Position your face inside the guide';
  }

  void _onFrame(CameraImage image) {
    if (_busyFrame || _phase != _Phase.scanning) return;
    _busyFrame = true;
    unawaited(_processFrame(image).whenComplete(() => _busyFrame = false));
  }

  Future<void> _processFrame(CameraImage image) async {
    final controller = _cameraController;
    final detectionService = _detectionService;
    final verificationService = _verificationService;
    if (controller == null ||
        detectionService == null ||
        verificationService == null) {
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

    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotation,
    );

    String? framingIssueMessage;
    var isGoodFrame = quality.passed;
    if (isGoodFrame) {
      final face = faces.single;
      final uprightImageSize = FaceDetectionService.uprightSize(
        imageSize,
        rotation,
      );
      final uprightBox = FaceDetectionService.uprightRect(
        face.boundingBox,
        imageSize,
        rotation,
      );
      final edgeMargin = _edgeMarginFraction * uprightImageSize.shortestSide;
      final fullyInFrame =
          uprightBox.left > edgeMargin &&
          uprightBox.top > edgeMargin &&
          uprightBox.right < uprightImageSize.width - edgeMargin &&
          uprightBox.bottom < uprightImageSize.height - edgeMargin;
      final bothEyesLocated =
          face.leftEyePosition != null && face.rightEyePosition != null;

      if (!fullyInFrame || !bothEyesLocated) {
        isGoodFrame = false;
        framingIssueMessage = 'Keep your whole face inside the frame';
      }
    }

    if (!isGoodFrame) {
      await _handleBadFrame(
        quality.primaryMessage ?? framingIssueMessage ?? 'Position your face',
      );
      return;
    }

    // Good frame — a face/quality hiccup streak in progress is over.
    _badFrameStreak = 0;

    switch (_scanState) {
      case _ScanState.waitingForFace:
      case _ScanState.stabilizing:
        await _advanceStabilizing();
        return;
      case _ScanState.verifying:
        await _collectVerificationSample(image, faces.single, verificationService);
        return;
    }
  }

  /// A single bad frame (no face, poor quality, or partially cropped)
  /// never immediately resets progress — only [_maxBadFrameStreak]
  /// *consecutive* bad frames do. This is what stops brief detector
  /// hiccups from bouncing the UI back to "Position your face" mid
  /// stabilization or mid verification.
  Future<void> _handleBadFrame(String message) async {
    _badFrameStreak++;
    if (_badFrameStreak < _maxBadFrameStreak) {
      // Tolerated — keep whatever progress has been made so far and just
      // surface the guidance message if we're still in the early state;
      // once stabilizing/verifying has started, stay on its own caption
      // rather than flashing positioning guidance for one bad frame.
      if (_scanState == _ScanState.waitingForFace) {
        if (!mounted) return;
        setState(() => _statusMessage = message);
      }
      return;
    }

    // Streak exceeded tolerance — the operator has actually moved away or
    // lost framing. Reset back to the start of the state machine.
    _badFrameStreak = 0;
    _stableGoodFrames = 0;
    _verificationSamples.clear();
    if (!mounted) return;
    setState(() {
      _scanState = _ScanState.waitingForFace;
      _statusMessage = message;
    });
  }

  Future<void> _advanceStabilizing() async {
    _stableGoodFrames++;
    if (_stableGoodFrames < _requiredStableFrames) {
      if (!mounted) return;
      setState(() {
        _scanState = _ScanState.stabilizing;
        _statusMessage = 'Hold still';
      });
      return;
    }

    // Stabilization complete — enter VERIFYING and stay there,
    // uninterrupted by individual sample outcomes, until a final decision
    // is reached in `_finalizeVerification`.
    _verificationSamples.clear();
    if (!mounted) return;
    setState(() {
      _scanState = _ScanState.verifying;
      _statusMessage = 'Verifying your identity…';
    });
  }

  Future<void> _collectVerificationSample(
    CameraImage image,
    DetectedFace face,
    FaceVerificationService verificationService,
  ) async {
    final frame = CameraFrameConverter.toRgbImage(image);
    final result = await verificationService.verify(
      frame: frame,
      face: face,
      candidates: _templates,
    );
    if (!mounted) return;

    _verificationSamples.add(result.matchedOperatorId);

    if (_verificationSamples.length < _requiredVerificationSamples) {
      // Still accumulating — caption stays exactly as-is (no flicker):
      // never react to a single sample's outcome here.
      return;
    }

    await _finalizeVerification();
  }

  /// Combines every collected sample into one final decision — the actual
  /// anti-flicker payoff. A single frame's mismatch (or a single frame's
  /// stray match) can never flip the result on its own; only a majority
  /// across [_requiredVerificationSamples] samples can.
  Future<void> _finalizeVerification() async {
    final counts = <String, int>{};
    for (final id in _verificationSamples) {
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }

    String? winnerId;
    var winnerCount = 0;
    counts.forEach((id, count) {
      if (count > winnerCount) {
        winnerId = id;
        winnerCount = count;
      }
    });

    _verificationSamples.clear();

    if (winnerId == null || winnerCount < _consensusSamplesRequired) {
      _stableGoodFrames = 0;
      unawaited(_disposeCamera());
      if (!mounted) return;
      setState(() => _phase = _Phase.notRecognized);
      return;
    }

    final operator = _operatorsById[winnerId];
    if (operator == null) {
      // Matched a template with no corresponding operator profile (e.g.
      // deleted after enrollment) — final result is still "not
      // recognized", not a retry loop.
      _stableGoodFrames = 0;
      unawaited(_disposeCamera());
      if (!mounted) return;
      setState(() => _phase = _Phase.notRecognized);
      return;
    }
    // Full dispose rather than just `stopImageStream()` — matches this
    // screen's own pause/resume convention in
    // `didChangeAppLifecycleState`/`_retryScanning`, which always reopens
    // a fresh `CameraController` rather than restarting the stream on a
    // held one.
    unawaited(_disposeCamera());

    if (!operator.enabled) {
      setState(() {
        _phase = _Phase.blocked;
        _matchedOperator = operator;
      });
      context.read<CraneController>().recordFaceVerificationDenied(operator);
      return;
    }

    setState(() {
      _phase = _Phase.verified;
      _matchedOperator = operator;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      context.read<CraneController>().completeFaceVerification(operator);
    });
  }

  /// Resumes scanning after a terminal outcome (blocked or not-recognized)
  /// — the detection/embedding/verification services and loaded templates
  /// are already in memory, only the camera (fully disposed on reaching
  /// that outcome) needs reopening.
  Future<void> _retryScanning() async {
    setState(() {
      _phase = _Phase.initializing;
      _statusMessage = 'Starting camera…';
    });
    await _initializeCamera();
  }

  /// Full re-init for the permission-denied/camera-error/no-operators
  /// states, where the services/templates/camera may never have been set
  /// up successfully in the first place.
  Future<void> _retryFromScratch() async {
    setState(() {
      _phase = _Phase.initializing;
      _statusMessage = 'Starting camera…';
    });
    await _initialize();
  }

  void _backToScan() {
    context.read<CraneController>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_phase) {
      case _Phase.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandViolet),
        );
      case _Phase.permissionDenied:
        return _MessageState(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission required',
          message:
              'Face verification needs camera access to identify the '
              'operator. Grant camera access in system settings, then try '
              'again.',
          primaryLabel: 'Open Settings',
          onPrimary: () => unawaited(openAppSettings()),
          onCancel: _backToScan,
          cancelLabel: 'Back to Scan',
        );
      case _Phase.cameraError:
        return _MessageState(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          message: 'The camera could not be started.',
          primaryLabel: 'Retry',
          onPrimary: () => unawaited(_retryFromScratch()),
          onCancel: _backToScan,
          cancelLabel: 'Back to Scan',
        );
      case _Phase.noOperators:
        return _MessageState(
          icon: Icons.group_off_outlined,
          title: 'No enrolled operators',
          message:
              'No registered operators were found on this device. Contact '
              'an administrator to enroll an operator before connecting.',
          onCancel: _backToScan,
          cancelLabel: 'Back to Scan',
        );
      case _Phase.scanning:
        return _buildLive(context);
      case _Phase.verified:
        return _buildVerified(context);
      case _Phase.blocked:
        return _buildBlocked(context);
      case _Phase.notRecognized:
        return _buildNotRecognized(context);
    }
  }

  Widget _buildLive(BuildContext context) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandViolet),
      );
    }

    final isVerifying = _scanState == _ScanState.verifying;
    final guideColor = isVerifying
        ? AppColors.brandViolet
        : Colors.white.withAlpha(210);

    return LayoutBuilder(
      builder: (context, constraints) {
        final guideDiameter =
            2 *
            FaceDetectionService.centerToleranceRadiusPx(
              screenSize: constraints.biggest,
              cameraAspectRatio: controller.value.aspectRatio,
            );

        return Stack(
          fit: StackFit.expand,
          children: [
            _CoverCameraPreview(controller: controller),
            Container(color: Colors.black.withAlpha(60)),
            FaceCaptureOverlay(
              caption: _statusMessage,
              guideColor: guideColor,
              guideDiameter: guideDiameter,
              scanProgress: isVerifying
                  ? (_verificationSamples.length / _requiredVerificationSamples)
                        .clamp(0.0, 1.0)
                  : null,
            ),
            const Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: _HeaderBanner(
                title: 'Face Verification',
                subtitle: 'Look at the camera to verify your identity',
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: BrandIconButton(
                icon: Icons.close_rounded,
                dark: true,
                tooltip: 'Back to Scan',
                onTap: _backToScan,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVerified(BuildContext context) {
    final operator = _matchedOperator;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.brandSuccess.withAlpha(40),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.brandSuccess,
                size: 56,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Verified ✓',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (operator != null) ...[
              const SizedBox(height: 8),
              Text(
                'Welcome, ${operator.name}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.brandSuccess,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Continuing to PLC authentication…',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlocked(BuildContext context) {
    final operator = _matchedOperator;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandStatusBanner(
              icon: Icons.block_rounded,
              title: 'Operator not authorized',
              message: operator != null
                  ? '${operator.name}\'s access has been disabled. Contact '
                        'your administrator to restore access.'
                  : 'This operator\'s access has been disabled. Contact '
                        'your administrator.',
              tone: BrandTone.danger,
            ),
            const SizedBox(height: 20),
            BrandPrimaryButton(label: 'Try Again', onPressed: _retryScanning),
            const SizedBox(height: 12),
            BrandSecondaryButton(label: 'Back to Scan', onPressed: _backToScan),
          ],
        ),
      ),
    );
  }

  Widget _buildNotRecognized(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandStatusBanner(
              icon: Icons.person_off_outlined,
              title: 'Face not recognized',
              message:
                  'We could not confidently match your face to a registered '
                  'operator. Make sure your whole face is visible in good '
                  'lighting, then try again.',
              tone: BrandTone.danger,
            ),
            const SizedBox(height: 20),
            BrandPrimaryButton(label: 'Try Again', onPressed: _retryScanning),
            const SizedBox(height: 12),
            BrandSecondaryButton(label: 'Back to Scan', onPressed: _backToScan),
          ],
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12.5,
            shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// See `FaceVerifyScreen`/`FaceEnrollmentScreen`'s identical
/// `_CoverCameraPreview`: covers the parent's bounds without stretching or
/// mirroring the preview.
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
    this.primaryLabel,
    this.onPrimary,
    this.onCancel,
    this.cancelLabel = 'Cancel',
  });

  final IconData icon;
  final String title;
  final String message;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onCancel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandStatusBanner(
              icon: icon,
              title: title,
              message: message,
              tone: BrandTone.info,
            ),
            if (primaryLabel != null) ...[
              const SizedBox(height: 20),
              BrandPrimaryButton(label: primaryLabel!, onPressed: onPrimary),
            ],
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              BrandSecondaryButton(label: cancelLabel, onPressed: onCancel),
            ],
          ],
        ),
      ),
    );
  }
}
