import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/three_divi_face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/secure_camera_screen.dart';

class FaceSdkDiagnosticScreen extends StatefulWidget {
  const FaceSdkDiagnosticScreen({super.key});

  @override
  State<FaceSdkDiagnosticScreen> createState() =>
      _FaceSdkDiagnosticScreenState();
}

class _FaceSdkDiagnosticScreenState extends State<FaceSdkDiagnosticScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  FaceRecognitionEngine? _engine;
  FaceFrameAnalysis? _analysis;
  Future<void>? _initialization;
  Future<void>? _activeAnalysis;
  DateTime? _lastSubmittedAt;
  String? _error;
  String _phase = 'Initializing 3DiVi Face SDK';
  int _rotationQuarterTurns = 0;
  bool _isProcessing = false;
  bool _isShuttingDown = false;
  bool _streamRunning = false;

  // A diagnostic does not need video-rate inference. One keep-latest frame per
  // second leaves CPU headroom for BLE, heartbeat, notifications, and E-STOP.
  static const Duration _minimumFrameInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialization = _initialize();
    _initialization = initialization;
    unawaited(initialization);
  }

  Future<void> _initialize() async {
    await SecureCameraScreen.setEnabled(true);

    try {
      final cameras = await availableCameras();
      final frontCameras = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (frontCameras.isEmpty) {
        throw StateError('No front camera is available');
      }

      final frontCamera = frontCameras.first;
      final camera = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _camera = camera;
      await camera.initialize();
      _rotationQuarterTurns = _sdkRotationFor(frontCamera.sensorOrientation);

      if (mounted) {
        setState(() => _phase = 'Camera ready · Initializing biometric blocks');
      }

      final engine = ThreeDiviFaceRecognitionEngine(
        onInitializationStage: (stage) {
          if (mounted && !_isShuttingDown) {
            setState(() => _phase = stage);
          }
        },
      );
      _engine = engine;
      await engine.initialize();

      if (!mounted || _isShuttingDown) return;
      setState(() => _phase = 'Position your face');
      await _startStream();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _phase = 'Diagnostic unavailable';
      });
    }
  }

  int _sdkRotationFor(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return 0;
      case 90:
        return 1;
      case 270:
        return 2;
      case 180:
        return 3;
      default:
        throw StateError('Unsupported camera sensor orientation');
    }
  }

  Future<void> _startStream() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        _streamRunning ||
        _isShuttingDown) {
      return;
    }

    await camera.startImageStream(_onCameraFrame);
    _streamRunning = true;
  }

  void _onCameraFrame(CameraImage image) {
    final now = DateTime.now();
    final previous = _lastSubmittedAt;
    if (_isProcessing ||
        _isShuttingDown ||
        (previous != null &&
            now.difference(previous) < _minimumFrameInterval)) {
      return;
    }

    _lastSubmittedAt = now;
    final analysis = _analyze(image);
    _activeAnalysis = analysis;
    unawaited(analysis);
  }

  Future<void> _analyze(CameraImage image) async {
    final engine = _engine;
    if (engine == null || !engine.isInitialized) return;

    _isProcessing = true;
    try {
      final result = await engine.analyzeCameraFrame(
        image,
        rotationQuarterTurns: _rotationQuarterTurns,
      );
      if (!mounted || _isShuttingDown) return;
      setState(() {
        _analysis = result;
        _error = null;
        _phase = _phaseFor(result);
      });
    } catch (error) {
      if (!mounted || _isShuttingDown) return;
      setState(() {
        _error = error.toString();
        _phase = 'Frame processing failed';
      });
    } finally {
      _isProcessing = false;
    }
  }

  String _phaseFor(FaceFrameAnalysis analysis) {
    if (analysis.faceCount == 0) return 'Position your face';
    if (analysis.faceCount > 1) return 'Multiple faces detected';
    if (analysis.qualityAccepted == false) return analysis.qualityGuidance;
    if (analysis.qualityAccepted != true) return 'Face detected · Hold still';

    switch (analysis.liveness) {
      case FaceLivenessVerdict.real:
        return 'Liveness accepted';
      case FaceLivenessVerdict.fake:
        return 'Spoof detected';
      case FaceLivenessVerdict.inconclusive:
        return 'Liveness inconclusive · Try again';
      case FaceLivenessVerdict.notEvaluated:
        return 'Checking liveness';
    }
  }

  Color get _statusColor {
    final analysis = _analysis;
    if (_error != null || analysis?.liveness == FaceLivenessVerdict.fake) {
      return AppColors.brandDanger;
    }
    if (analysis?.liveness == FaceLivenessVerdict.real) {
      return AppColors.brandSuccess;
    }
    if ((analysis?.faceCount ?? 0) > 1 || analysis?.qualityAccepted == false) {
      return AppColors.brandWarning;
    }
    return AppColors.brandInfo;
  }

  bool get _mirrorPreview => Platform.isAndroid;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_stopStream());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_startStream());
    }
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (!_streamRunning || camera == null) return;
    _streamRunning = false;
    try {
      await camera.stopImageStream();
    } catch (_) {
      // Camera may already be stopped by the platform lifecycle.
    }
  }

  Future<void> _shutdown() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;

    await _stopStream();
    try {
      await _initialization;
    } catch (_) {
      // Initialization failures are already represented in the diagnostic UI.
    }
    try {
      await _activeAnalysis;
    } catch (_) {
      // The diagnostic is leaving; resource disposal still has to continue.
    }
    await _engine?.dispose();
    await _camera?.dispose();
    await SecureCameraScreen.setEnabled(false);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_shutdown());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return Scaffold(
      backgroundColor: AppColors.brandInk,
      appBar: AppBar(
        backgroundColor: AppColors.brandInk,
        foregroundColor: AppColors.brandOnDark,
        title: const Text('3DiVi Face SDK diagnostic'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: camera != null && camera.value.isInitialized
                  ? _CameraViewport(
                      camera: camera,
                      analysis: _analysis,
                      mirror: _mirrorPreview,
                      statusColor: _statusColor,
                    )
                  : const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.brandViolet,
                      ),
                    ),
            ),
            _DiagnosticStatusPanel(
              phase: _phase,
              statusColor: _statusColor,
              error: _error,
              sdkVersion: _engine?.sdkVersion,
              camera: camera,
              analysis: _analysis,
              rotationQuarterTurns: _rotationQuarterTurns,
              mirrored: _mirrorPreview,
            ),
          ],
        ),
      ),
    );
  }
}

class _CameraViewport extends StatelessWidget {
  const _CameraViewport({
    required this.camera,
    required this.analysis,
    required this.mirror,
    required this.statusColor,
  });

  final CameraController camera;
  final FaceFrameAnalysis? analysis;
  final bool mirror;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final previewSize = camera.value.previewSize;
    if (previewSize == null) return const SizedBox.shrink();

    final deviceOrientation = MediaQuery.orientationOf(context);
    final logicalWidth = deviceOrientation == Orientation.portrait
        ? previewSize.height
        : previewSize.width;
    final logicalHeight = deviceOrientation == Orientation.portrait
        ? previewSize.width
        : previewSize.height;

    return ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: logicalWidth,
              height: logicalHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(
                      mirror ? -1.0 : 1.0,
                      1.0,
                      1.0,
                    ),
                    child: CameraPreview(camera),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _FaceBoundsPainter(
                        faces: analysis?.faces ?? const [],
                        mirror: mirror,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FaceBoundsPainter extends CustomPainter {
  const _FaceBoundsPainter({
    required this.faces,
    required this.mirror,
    required this.color,
  });

  final List<NormalizedFaceBounds> faces;
  final bool mirror;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (final face in faces) {
      final left = mirror ? 1 - face.right : face.left;
      final right = mirror ? 1 - face.left : face.right;
      final rect = Rect.fromLTRB(
        left * size.width,
        face.top * size.height,
        right * size.width,
        face.bottom * size.height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(16)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _FaceBoundsPainter oldDelegate) =>
      oldDelegate.faces != faces ||
      oldDelegate.mirror != mirror ||
      oldDelegate.color != color;
}

class _DiagnosticStatusPanel extends StatelessWidget {
  const _DiagnosticStatusPanel({
    required this.phase,
    required this.statusColor,
    required this.error,
    required this.sdkVersion,
    required this.camera,
    required this.analysis,
    required this.rotationQuarterTurns,
    required this.mirrored,
  });

  final String phase;
  final Color statusColor;
  final String? error;
  final String? sdkVersion;
  final CameraController? camera;
  final FaceFrameAnalysis? analysis;
  final int rotationQuarterTurns;
  final bool mirrored;

  @override
  Widget build(BuildContext context) {
    final confidence = analysis?.livenessConfidence;
    final previewSize = camera?.value.previewSize;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      decoration: const BoxDecoration(
        color: AppColors.brandInkAlt,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  phase,
                  style: const TextStyle(
                    color: AppColors.brandOnDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.brandDanger,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DiagnosticChip(label: 'SDK ${sdkVersion ?? 'initializing'}'),
              _DiagnosticChip(label: 'Faces ${analysis?.faceCount ?? 0}'),
              _DiagnosticChip(
                label: analysis?.qualityAccepted == true
                    ? 'Quality PASS'
                    : analysis?.qualityAccepted == false
                    ? 'Quality FAIL'
                    : 'Quality pending',
              ),
              _DiagnosticChip(
                label: confidence == null
                    ? 'PAD pending'
                    : 'PAD ${(confidence * 100).toStringAsFixed(1)}%',
              ),
              _DiagnosticChip(
                label: previewSize == null
                    ? 'Camera initializing'
                    : '${previewSize.width.toInt()}×${previewSize.height.toInt()}',
              ),
              _DiagnosticChip(label: 'Rotation ${rotationQuarterTurns * 90}°'),
              _DiagnosticChip(
                label: mirrored
                    ? 'Front preview · intentionally mirrored'
                    : 'Preview · not mirrored',
              ),
              if (analysis != null)
                _DiagnosticChip(
                  label: '${analysis!.processingTime.inMilliseconds} ms/frame',
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Diagnostic only · no enrollment, face photo, or biometric template is saved.',
            style: TextStyle(
              color: AppColors.brandOnDarkSub,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticChip extends StatelessWidget {
  const _DiagnosticChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.darkBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.brandOnDarkSub,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
