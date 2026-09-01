import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/secure_camera_screen.dart';

enum FaceCapturePurpose { enrollment, authentication }

class FaceEnrollmentScreen extends StatefulWidget {
  const FaceEnrollmentScreen({
    required this.engine,
    this.purpose = FaceCapturePurpose.enrollment,
    this.onEmergencyStop,
    super.key,
  });

  final FaceRecognitionEngine engine;
  final FaceCapturePurpose purpose;
  final Future<void> Function()? onEmergencyStop;

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with WidgetsBindingObserver {
  static const Duration _minimumFrameInterval = Duration(seconds: 1);
  static const int _requiredStableFrames = 2;

  CameraController? _camera;
  FaceRecognitionEngine? _engine;
  FaceFrameAnalysis? _analysis;
  Future<void>? _initialization;
  Future<void>? _activeWork;
  DateTime? _lastSubmittedAt;
  String _phase = 'Preparing secure face enrollment';
  String? _error;
  int _rotationQuarterTurns = 0;
  int _stableFrames = 0;
  bool _streamRunning = false;
  bool _processing = false;
  bool _captureNextAcceptedFrame = false;
  bool _shuttingDown = false;
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialization = _initialize();
    unawaited(_initialization);
  }

  Future<void> _initialize() async {
    await SecureCameraScreen.setEnabled(true);
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) throw StateError('No front camera is available.');

      final description = front.first;
      final camera = CameraController(
        description,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );
      _camera = camera;
      await camera.initialize();
      _rotationQuarterTurns = _sdkRotationFor(description.sensorOrientation);
      if (mounted) {
        setState(() => _phase = 'Initializing 3DiVi security checks');
      }

      final engine = widget.engine;
      _engine = engine;
      await engine.initialize();
      if (!mounted || _shuttingDown) return;
      setState(() => _phase = 'Position your face');
      await _startStream();
    } catch (error) {
      if (!mounted || _shuttingDown) return;
      setState(() {
        _phase = 'Enrollment unavailable';
        _error = error.toString();
      });
    }
  }

  int _sdkRotationFor(int sensorOrientation) => switch (sensorOrientation) {
    0 => 0,
    90 => 1,
    270 => 2,
    180 => 3,
    _ => throw StateError('Unsupported camera sensor orientation.'),
  };

  Future<void> _startStream() async {
    final camera = _camera;
    if (_shuttingDown ||
        _completed ||
        _streamRunning ||
        camera == null ||
        !camera.value.isInitialized) {
      return;
    }
    await camera.startImageStream(_onCameraFrame);
    _streamRunning = true;
  }

  void _onCameraFrame(CameraImage image) {
    final now = DateTime.now();
    if (_processing ||
        _shuttingDown ||
        _completed ||
        (_lastSubmittedAt != null &&
            now.difference(_lastSubmittedAt!) < _minimumFrameInterval)) {
      return;
    }
    _lastSubmittedAt = now;
    final work = _captureNextAcceptedFrame ? _capture(image) : _analyze(image);
    _activeWork = work;
    unawaited(work);
  }

  Future<void> _analyze(CameraImage image) async {
    final engine = _engine;
    if (engine == null || !engine.isInitialized) return;
    _processing = true;
    try {
      final result = await engine.analyzeCameraFrame(
        image,
        rotationQuarterTurns: _rotationQuarterTurns,
      );
      if (!mounted || _shuttingDown) return;
      final accepted =
          result.qualityAccepted == true &&
          result.liveness == FaceLivenessVerdict.real;
      _stableFrames = accepted ? _stableFrames + 1 : 0;
      _captureNextAcceptedFrame = _stableFrames >= _requiredStableFrames;
      setState(() {
        _analysis = result;
        _error = null;
        _phase = _captureNextAcceptedFrame
            ? 'Hold still · Capturing biometric data'
            : _phaseFor(result);
      });
      if (widget.purpose == FaceCapturePurpose.authentication &&
          result.liveness == FaceLivenessVerdict.fake) {
        await _returnRejectedCapture(result);
      }
    } catch (error) {
      if (!mounted || _shuttingDown) return;
      _stableFrames = 0;
      _captureNextAcceptedFrame = false;
      setState(() {
        _phase = 'Enrollment check failed · Try again';
        _error = error.toString();
      });
    } finally {
      _processing = false;
    }
  }

  Future<void> _capture(CameraImage image) async {
    final engine = _engine;
    if (engine == null || !engine.isInitialized) return;
    _processing = true;
    if (mounted) setState(() => _phase = 'Capturing biometric data');
    try {
      final capture = await engine.createEnrollmentTemplate(
        image,
        rotationQuarterTurns: _rotationQuarterTurns,
      );
      if (!mounted || _shuttingDown) return;
      _analysis = capture.analysis;
      if (!capture.succeeded) {
        if (widget.purpose == FaceCapturePurpose.authentication &&
            capture.analysis.liveness == FaceLivenessVerdict.fake) {
          await _returnRejectedCapture(capture.analysis);
          return;
        }
        _stableFrames = 0;
        _captureNextAcceptedFrame = false;
        setState(() => _phase = _phaseFor(capture.analysis));
        return;
      }

      _completed = true;
      await _stopStream();
      if (!mounted || _shuttingDown) return;
      setState(
        () => _phase = widget.purpose == FaceCapturePurpose.enrollment
            ? 'Enrollment successful'
            : 'Biometric captured · Identifying operator',
      );
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (mounted && !_shuttingDown) Navigator.of(context).pop(capture);
    } catch (error) {
      if (!mounted || _shuttingDown) return;
      _stableFrames = 0;
      _captureNextAcceptedFrame = false;
      setState(() {
        _phase = 'Enrollment failed · Try again';
        _error = error.toString();
      });
    } finally {
      _processing = false;
    }
  }

  Future<void> _returnRejectedCapture(FaceFrameAnalysis analysis) async {
    if (_completed) return;
    _completed = true;
    await _stopStream();
    if (!mounted || _shuttingDown) return;
    setState(() {
      _analysis = analysis;
      _phase = 'Spoof detected · Access rejected';
    });
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted && !_shuttingDown) {
      Navigator.of(context).pop(FaceEnrollmentCapture(analysis: analysis));
    }
  }

  String _phaseFor(FaceFrameAnalysis analysis) {
    if (analysis.faceCount == 0) return 'Position your face';
    if (analysis.faceCount > 1) return 'Multiple faces detected';
    if (analysis.qualityAccepted == false) return analysis.qualityGuidance;
    if (analysis.qualityAccepted != true) return 'Face detected · Hold still';
    return switch (analysis.liveness) {
      FaceLivenessVerdict.real => 'Liveness accepted · Hold still',
      FaceLivenessVerdict.fake => 'Spoof detected · Access rejected',
      FaceLivenessVerdict.inconclusive => 'Checking liveness · Hold still',
      FaceLivenessVerdict.notEvaluated => 'Checking liveness',
    };
  }

  Color get _statusColor {
    if (_error != null || _analysis?.liveness == FaceLivenessVerdict.fake) {
      return AppColors.brandDanger;
    }
    if (_completed) return AppColors.brandSuccess;
    if (_analysis?.qualityAccepted == false ||
        (_analysis?.faceCount ?? 0) > 1) {
      return AppColors.brandWarning;
    }
    return AppColors.brandInfo;
  }

  bool get _mirrorPreview => Platform.isAndroid;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_startStream());
    } else {
      unawaited(_stopStream());
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
    if (_shuttingDown) return;
    _shuttingDown = true;
    await _stopStream();
    try {
      await _initialization;
      await _activeWork;
    } catch (_) {
      // UI already reports initialization/capture errors.
    }
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
    return PopScope(
      canPop: !_processing,
      child: Scaffold(
        backgroundColor: AppColors.brandInk,
        appBar: AppBar(
          backgroundColor: AppColors.brandInk,
          foregroundColor: AppColors.brandOnDark,
          title: Text(
            widget.purpose == FaceCapturePurpose.enrollment
                ? 'Face Enrollment'
                : 'Face Authentication',
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: camera != null && camera.value.isInitialized
                    ? _EnrollmentCameraViewport(
                        camera: camera,
                        analysis: _analysis,
                        mirror: _mirrorPreview,
                        color: _statusColor,
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.brandViolet,
                        ),
                      ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
                color: AppColors.brandInkAlt,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.face_rounded, color: _statusColor),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _phase,
                            style: const TextStyle(
                              color: AppColors.brandOnDark,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.brandDanger,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    const Text(
                      'Use one person only. Look directly at the camera and keep your face evenly lit. No photograph is saved.',
                      style: TextStyle(
                        color: AppColors.brandOnDarkSub,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (widget.purpose == FaceCapturePurpose.authentication &&
                        widget.onEmergencyStop != null) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.brandDanger,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: () =>
                              unawaited(widget.onEmergencyStop!.call()),
                          icon: const Icon(Icons.emergency_rounded),
                          label: const Text('EMERGENCY STOP'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnrollmentCameraViewport extends StatelessWidget {
  const _EnrollmentCameraViewport({
    required this.camera,
    required this.analysis,
    required this.mirror,
    required this.color,
  });

  final CameraController camera;
  final FaceFrameAnalysis? analysis;
  final bool mirror;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = camera.value.previewSize;
    if (size == null) return const SizedBox.shrink();
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final width = portrait ? size.height : size.width;
    final height = portrait ? size.width : size.height;
    return ClipRect(
      child: ColoredBox(
        color: Colors.black,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: width,
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(mirror ? -1 : 1, 1, 1),
                    child: CameraPreview(camera),
                  ),
                  CustomPaint(
                    painter: _EnrollmentBoundsPainter(
                      faces: analysis?.faces ?? const [],
                      mirror: mirror,
                      color: color,
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

class _EnrollmentBoundsPainter extends CustomPainter {
  const _EnrollmentBoundsPainter({
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
  bool shouldRepaint(covariant _EnrollmentBoundsPainter oldDelegate) =>
      oldDelegate.faces != faces ||
      oldDelegate.mirror != mirror ||
      oldDelegate.color != color;
}
