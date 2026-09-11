import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/face_match_result.dart';
import 'package:rev_crane_control_ops/models/face_template.dart';
import 'package:rev_crane_control_ops/repositories/face_template_repository.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/services/camera_frame_converter.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/face_embedding_service.dart';
import 'package:rev_crane_control_ops/services/face_matching_service.dart';
import 'package:rev_crane_control_ops/services/face_verification_service.dart';
import 'package:rev_crane_control_ops/services/front_camera_session.dart';
import 'package:rev_crane_control_ops/utils/device_type.dart';
import 'package:rev_crane_control_ops/widgets/operator/face_capture_overlay.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

enum _ScreenPhase { initializing, permissionDenied, cameraError, running }

/// Debug-only (`kDebugMode`-gated entry point — see
/// `OperatorManagementScreen`) live face-verification test tool: points
/// the front camera at whoever's there and continuously shows whether
/// they match any enrolled operator, with the raw similarity scores. This
/// is the direct, end-to-end way to confirm enrollment actually captured
/// a matchable face, without building a full login flow first.
///
/// Read-only by design: never writes to any repository and never records
/// an audit-log entry. Whether a "verify" attempt here should count as a
/// real authentication event for the permanent audit trail is a decision
/// for an eventual face-login feature — deliberately not made by this
/// debug tool.
///
/// Never displays or logs the embedding vector itself — only the derived
/// similarity scores and operator names.
class FaceVerifyScreen extends StatefulWidget {
  const FaceVerifyScreen({
    super.key,
    required this.operatorRepository,
    required this.templateRepository,
  });

  final OperatorRepository operatorRepository;
  final FaceTemplateRepository templateRepository;

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  FaceDetectionService? _detectionService;
  FaceEmbeddingService? _embeddingService;
  FaceVerificationService? _verificationService;

  List<FaceTemplate> _templates = const [];
  Map<String, String> _operatorNames = const {};

  _ScreenPhase _phase = _ScreenPhase.initializing;
  String _statusMessage = 'Starting camera…';
  FaceMatchResult? _lastResult;
  bool _busyFrame = false;

  /// Consecutive good frames required before running a verification
  /// attempt — the same anti-flicker rationale as
  /// `FaceEnrollmentService`'s stability gate, so a single lucky/unlucky
  /// frame can't decide the outcome. Reset whenever the readiness gate
  /// stops passing.
  static const int _requiredStableFrames = 3;
  int _stableGoodFrames = 0;

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
        _phase == _ScreenPhase.running) {
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
      final operators = await widget.operatorRepository.getAll();
      final templates = await widget.templateRepository.getAll();
      if (!mounted) return;
      _templates = templates;
      _operatorNames = {for (final o in operators) o.operatorId: o.name};

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
      setState(() => _phase = _ScreenPhase.running);
      await controller.startImageStream(_onFrame);
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _ScreenPhase.cameraError);
    }
  }

  void _onFrame(CameraImage image) {
    if (_busyFrame) return;
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

    // Same readiness gate enrollment uses — a frame reaches the
    // verification embedder only once it clears the identical
    // face-count/size/center/pose/eyes checks a sample would need to
    // clear to be accepted during enrollment. Previously this screen ran
    // `verify()` on the very first single-face frame regardless of
    // position, size, or pose, which made a good match depend on
    // recreating enrollment's incidental framing rather than on identity.
    final quality = FaceDetectionService.evaluateQuality(
      faces,
      imageSize,
      rotationDegrees: rotation,
    );
    if (!quality.passed) {
      _stableGoodFrames = 0;
      if (!mounted) return;
      setState(() {
        _statusMessage = quality.primaryMessage ?? 'Position your face';
        _lastResult = null;
      });
      return;
    }

    if (_templates.isEmpty) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'No enrolled operators to match against';
        _lastResult = null;
      });
      return;
    }

    _stableGoodFrames++;
    if (_stableGoodFrames < _requiredStableFrames) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Hold still';
        _lastResult = null;
      });
      return;
    }

    final frame = CameraFrameConverter.toRgbImage(image);
    final result = await verificationService.verify(
      frame: frame,
      face: faces.single,
      candidates: _templates,
    );
    if (!mounted) return;
    setState(() {
      _statusMessage = '';
      _lastResult = result;
    });
  }

  String? _nameFor(String? operatorId) {
    if (operatorId == null) return null;
    return _operatorNames[operatorId] ?? 'Unknown operator';
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
      case _ScreenPhase.initializing:
        return const Center(
          child: CircularProgressIndicator(color: AppColors.brandViolet),
        );
      case _ScreenPhase.permissionDenied:
        return _MessageState(
          icon: Icons.no_photography_outlined,
          title: 'Camera permission required',
          message: 'Grant camera access in system settings, then try again.',
          primaryLabel: 'Open Settings',
          onPrimary: () => unawaited(openAppSettings()),
          onCancel: () => Navigator.of(context).pop(),
        );
      case _ScreenPhase.cameraError:
        return _MessageState(
          icon: Icons.videocam_off_outlined,
          title: 'Camera unavailable',
          message: 'The camera could not be started.',
          primaryLabel: 'Retry',
          onPrimary: () {
            setState(() => _phase = _ScreenPhase.initializing);
            unawaited(_initialize());
          },
          onCancel: () => Navigator.of(context).pop(),
        );
      case _ScreenPhase.running:
        return _buildLive(context);
    }
  }

  Color get _guideColor {
    final result = _lastResult;
    if (result != null) {
      return result.isMatch ? AppColors.brandSuccess : AppColors.brandDanger;
    }
    return Colors.white.withAlpha(210);
  }

  Widget _buildLive(BuildContext context) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brandViolet),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Same geometry-derived guide as enrollment — see
        // `FaceEnrollmentScreen._buildCapture`'s identical computation and
        // `FaceDetectionService.centerToleranceRadiusPx`'s doc comment.
        // Using the exact same helper here (rather than a screen-local
        // guess) is what keeps enrollment and verification presenting the
        // same acceptance region for the same underlying check.
        final guideDiameter =
            2 *
            FaceDetectionService.centerToleranceRadiusPx(
              screenSize: constraints.biggest,
              cameraAspectRatio: controller.value.aspectRatio,
            );

        return Stack(
          fit: StackFit.expand,
          children: [
            // True (non-mirrored) orientation, scaled to cover without
            // distorting the camera's aspect ratio — see
            // `FaceEnrollmentScreen`'s `_CoverCameraPreview` for why a plain
            // `Stack.expand` child would otherwise stretch it unevenly.
            _CoverCameraPreview(controller: controller),
            Container(color: Colors.black.withAlpha(60)),
            FaceCaptureOverlay(
              // Blank once a result has landed — the banner below takes
              // over at that instant (`_statusMessage` is cleared in
              // `_processFrame` exactly when `_lastResult` is set), so
              // the two never show conflicting text at once.
              caption: _lastResult == null
                  ? (_statusMessage.isEmpty ? 'Scanning…' : _statusMessage)
                  : '',
              guideColor: _guideColor,
              guideDiameter: guideDiameter,
            ),
            const Positioned(
              top: 8,
              right: 8,
              child: _DebugBadge(),
            ),
            if (_lastResult != null)
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: _ResultBanner(result: _lastResult!, nameFor: _nameFor),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: BrandIconButton(
                icon: Icons.close_rounded,
                dark: true,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// See `FaceEnrollmentScreen`'s identical `_CoverCameraPreview`: covers
/// the parent's bounds without stretching or mirroring the preview.
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

class _DebugBadge extends StatelessWidget {
  const _DebugBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(160),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'VERIFY (DEBUG)',
        style: TextStyle(
          color: Colors.amberAccent,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Only ever built once a verification attempt has actually run (see its
/// call site — the caller checks `_lastResult != null` first); the
/// "scanning/positioning" state is shown by `FaceCaptureOverlay`'s
/// caption instead, so there is exactly one place on screen showing
/// guidance text at any moment.
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result, required this.nameFor});

  final FaceMatchResult result;
  final String? Function(String?) nameFor;

  @override
  Widget build(BuildContext context) {
    final r = result;
    // Similarity is a raw cosine score in [-1, 1] compared against a
    // calibrated threshold — never presented as an "accuracy" percentage,
    // since it isn't one (see `FaceMatchingService`'s doc comment).
    final thresholdLabel =
        'threshold ${FaceMatchingService.defaultThreshold.toStringAsFixed(3)}';

    if (r.isMatch) {
      return _panel(
        icon: Icons.check_circle_rounded,
        color: AppColors.brandSuccess,
        title: 'MATCHED: ${nameFor(r.matchedOperatorId)}',
        subtitle:
            'similarity ${r.bestScore.toStringAsFixed(3)}   ·   $thresholdLabel',
      );
    }

    final bestName = nameFor(r.bestCandidateOperatorId);
    final secondName = nameFor(r.secondBestCandidateOperatorId);
    final subtitleParts = [
      if (bestName != null)
        'best: $bestName (${r.bestScore.toStringAsFixed(3)})',
      if (secondName != null && r.secondBestScore != null)
        'second: $secondName (${r.secondBestScore!.toStringAsFixed(3)})',
      thresholdLabel,
    ];

    return _panel(
      icon: Icons.person_off_outlined,
      color: AppColors.brandDanger,
      title: r.ambiguous ? 'AMBIGUOUS — no confident match' : 'NO MATCH',
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join('   ·   '),
    );
  }

  Widget _panel({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(190),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(140)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
  });

  final IconData icon;
  final String title;
  final String message;
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
              BrandSecondaryButton(label: 'Cancel', onPressed: onCancel),
            ],
          ],
        ),
      ),
    );
  }
}
