import 'dart:async';
import 'dart:math' show Random;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/detected_face.dart';
import 'package:rev_crane_control_ops/models/face_quality_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/models/liveness_challenge.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_liveness_service.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';
import 'package:rev_crane_control_ops/services/face_verification_service.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

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

enum _ScanState { waitingForFace, stabilizing, livenessCheck, verifying }

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
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

  static const int _requiredStableFrames = 10;

  static const int _requiredVerificationSamples = 5;

  static const int _maxBadFrameStreak = 6;

  int _stableGoodFrames = 0;
  int _badFrameStreak = 0;

  static const Duration _pixelCheckInterval = Duration(milliseconds: 200);
  DateTime? _lastPixelCheckAt;
  FaceQualityIssue? _cachedPixelIssue;

  LivenessSession? _livenessSession;
  double _livenessProgress = 0.0;
  static const List<LivenessChallengeType> _livenessChallengePool = [
    LivenessChallengeType.blink,
    LivenessChallengeType.lookStraight,
  ];

  final List<List<double>> _verificationEmbeddings = [];

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
    unawaited(DeviceType.restoreDefaultOrientations());
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
    _lastPixelCheckAt = null;
    _cachedPixelIssue = null;
    _livenessSession = null;
    _livenessProgress = 0.0;
    _verificationEmbeddings.clear();
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

    if (_scanState == _ScanState.livenessCheck && faces.length != 1) {
      await _handleLivenessFrame(faceCount: faces.length, face: null);
      return;
    }

    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotation,
    );

    String? framingIssueMessage;
    var isGoodFrame = quality.passed;
    img.Image? decodedFrame;
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

      if (isGoodFrame) {
        final now = DateTime.now();
        final dueForCheck =
            _scanState == _ScanState.verifying ||
            _lastPixelCheckAt == null ||
            now.difference(_lastPixelCheckAt!) >= _pixelCheckInterval;

        var pixelIssue = _cachedPixelIssue;
        if (dueForCheck) {
          decodedFrame = CameraFrameConverter.toRgbImage(image);
          pixelIssue = FrameQualityAnalyzer.evaluate(
            decodedFrame,
            face.boundingBox,
          );
          _cachedPixelIssue = pixelIssue;
          _lastPixelCheckAt = now;
        }
        if (pixelIssue != null) {
          isGoodFrame = false;
          framingIssueMessage = pixelIssue.guidance;
        }
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
      case _ScanState.livenessCheck:
        await _handleLivenessFrame(faceCount: 1, face: faces.single);
        return;
      case _ScanState.verifying:
        await _collectVerificationSample(
          decodedFrame!,
          faces.single,
          verificationService,
        );
        return;
    }
  }

  Future<void> _handleBadFrame(String message) async {
    _badFrameStreak++;
    if (_badFrameStreak < _maxBadFrameStreak) {
      if (_scanState == _ScanState.waitingForFace) {
        if (!mounted) return;
        setState(() => _statusMessage = message);
      }
      return;
    }

    _badFrameStreak = 0;
    _stableGoodFrames = 0;
    _livenessSession = null;
    _livenessProgress = 0.0;
    _verificationEmbeddings.clear();
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

    // Stabilization complete — run one randomly-chosen liveness challenge
    // before VERIFYING starts, so a static photo/screen replay that
    // cleared framing can't proceed any further.
    final challenge =
        _livenessChallengePool[Random().nextInt(_livenessChallengePool.length)];
    _livenessSession = LivenessSession(
      challenge,
      timeout: const Duration(seconds: 10),
    );
    _livenessProgress = 0.0;
    if (!mounted) return;
    setState(() {
      _scanState = _ScanState.livenessCheck;
      _statusMessage = challenge.instruction;
    });
  }

  Future<void> _handleLivenessFrame({
    required int faceCount,
    DetectedFace? face,
  }) async {
    final session = _livenessSession;
    if (session == null) return;

    final state = session.processFrame(
      faceCount: faceCount,
      face: face,
      now: DateTime.now(),
    );
    if (!mounted) return;

    if (state.completed) {
      _livenessSession = null;
      _livenessProgress = 0.0;
      _verificationEmbeddings.clear();
      setState(() {
        _scanState = _ScanState.verifying;
        _statusMessage = 'Verifying your identity…';
      });
      return;
    }

    if (state.failed || state.timedOut) {
      _livenessSession = null;
      _livenessProgress = 0.0;
      await _handleFailedAttempt(
        detailCode: state.timedOut
            ? 'face_liveness_timed_out'
            : 'face_liveness_failed',
        failureReason: state.failureReason,
        onFailed: () {
          _stableGoodFrames = 0;
          _verificationEmbeddings.clear();
          if (!mounted) return;
          setState(() {
            _scanState = _ScanState.waitingForFace;
            _statusMessage = "Let's try that again";
          });
        },
      );
      return;
    }

    setState(() {
      _statusMessage = state.challenge.instruction;
      _livenessProgress = state.progress;
    });
  }

  Future<void> _handleFailedAttempt({
    required String detailCode,
    String? failureReason,
    required VoidCallback onFailed,
  }) async {
    if (!mounted) return;
    context.read<CraneController>().recordFaceVerificationFailed(
      detailCode: detailCode,
      failureReason: failureReason,
    );
    onFailed();
  }

  Future<void> _collectVerificationSample(
    img.Image frame,
    DetectedFace face,
    FaceVerificationService verificationService,
  ) async {
    final embedding = await verificationService.embed(frame: frame, face: face);
    if (!mounted) return;

    _verificationEmbeddings.add(embedding);

    if (_verificationEmbeddings.length < _requiredVerificationSamples) {
      return;
    }

    await _finalizeVerification(verificationService);
  }

  Future<void> _finalizeVerification(
    FaceVerificationService verificationService,
  ) async {
    final pooled = FaceEmbeddingService.averageEmbeddings(
      _verificationEmbeddings,
    );
    final result = verificationService.match(
      embedding: pooled,
      candidates: _templates,
    );
    _verificationEmbeddings.clear();

    if (kDebugMode) {
      final bestName = result.bestCandidateOperatorId != null
          ? (_operatorsById[result.bestCandidateOperatorId]?.name ??
                result.bestCandidateOperatorId)
          : 'none';
      final outcome = result.isMatch
          ? 'MATCH'
          : result.ambiguous
          ? 'REJECT (ambiguous)'
          : 'REJECT (below threshold)';
      debugPrint(
        '[FaceVerify] pooled $_requiredVerificationSamples frames — '
        'best=$bestName score=${result.bestScore.toStringAsFixed(4)} '
        'threshold=${FaceMatchingService.defaultThreshold.toStringAsFixed(4)} '
        'result=$outcome',
      );
    }

    final winnerId = result.matchedOperatorId;
    if (winnerId == null) {
      _stableGoodFrames = 0;
      unawaited(_disposeCamera());
      await _handleFailedAttempt(
        detailCode: 'face_no_match',
        failureReason: result.ambiguous
            ? 'Pooled verification match was ambiguous between candidates.'
            : 'Pooled verification score did not clear the match threshold.',
        onFailed: () {
          if (!mounted) return;
          setState(() => _phase = _Phase.notRecognized);
        },
      );
      return;
    }

    final operator = _operatorsById[winnerId];
    if (operator == null) {
      _stableGoodFrames = 0;
      unawaited(_disposeCamera());
      await _handleFailedAttempt(
        detailCode: 'face_no_match',
        failureReason:
            'Matched template has no corresponding operator profile.',
        onFailed: () {
          if (!mounted) return;
          setState(() => _phase = _Phase.notRecognized);
        },
      );
      return;
    }

    unawaited(_disposeCamera());

    if (!operator.enabled) {
      setState(() {
        _phase = _Phase.blocked;
        _matchedOperator = operator;
      });
      context.read<CraneController>().recordFaceVerificationDenied(operator);
      return;
    }

    if (!mounted) return;
    setState(() {
      _phase = _Phase.verified;
      _matchedOperator = operator;
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      context.read<CraneController>().completeFaceVerification(operator);
    });
  }

  Future<void> _retryScanning() async {
    setState(() {
      _phase = _Phase.initializing;
      _statusMessage = 'Starting camera…';
    });
    await _initializeCamera();
  }

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

  void _useAnotherMethod() {
    unawaited(_disposeCamera());
    context.read<CraneController>().skipFaceVerification();
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
    final isLivenessCheck = _scanState == _ScanState.livenessCheck;
    final guideColor = (isVerifying || isLivenessCheck)
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
                  ? (_verificationEmbeddings.length /
                            _requiredVerificationSamples)
                        .clamp(0.0, 1.0)
                  : isLivenessCheck
                  ? _livenessProgress.clamp(0.0, 1.0)
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

            if (context.read<CraneController>().isFaceVerificationOptional)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: TextButton.icon(
                    onPressed: _useAnotherMethod,
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: const Text(
                      'Enter credentials instead',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVerified(BuildContext context) {
    final operator = _matchedOperator;

    final isDirectToControl = context
        .read<CraneController>()
        .isDeviceConfigured;
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
            Text(
              isDirectToControl
                  ? 'Opening your control session…'
                  : 'Continuing to sign in…',
              style: const TextStyle(color: Colors.white54, fontSize: 12.5),
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
            BrandSecondaryButton(
              label: 'Use Another Method',
              icon: Icons.swap_horiz_rounded,
              onPressed: _useAnotherMethod,
            ),
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
            BrandSecondaryButton(
              label: 'Use Another Method',
              icon: Icons.swap_horiz_rounded,
              onPressed: _useAnotherMethod,
            ),
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
