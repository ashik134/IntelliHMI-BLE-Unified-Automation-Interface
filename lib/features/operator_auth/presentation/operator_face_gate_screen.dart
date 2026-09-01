import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/features/operator_auth/application/operator_identification_service.dart';
import 'package:rev_crane_control_ops/features/operator_auth/application/operator_session_controller.dart';
import 'package:rev_crane_control_ops/features/operator_auth/data/operator_repository.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/face/three_divi_face_recognition_engine.dart';
import 'package:rev_crane_control_ops/features/operator_auth/presentation/face_enrollment_screen.dart';

class OperatorFaceGateScreen extends StatefulWidget {
  const OperatorFaceGateScreen({required this.plcConnectionId, super.key});

  final String plcConnectionId;

  @override
  State<OperatorFaceGateScreen> createState() => _OperatorFaceGateScreenState();
}

class _OperatorFaceGateScreenState extends State<OperatorFaceGateScreen> {
  final OperatorRepository _repository = OperatorRepository();
  bool _busy = false;
  OperatorIdentificationResult? _result;

  @override
  void dispose() {
    unawaited(_repository.close());
    super.dispose();
  }

  Future<void> _authenticateFace() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });

    final engine = ThreeDiviFaceRecognitionEngine();
    try {
      final capture = await Navigator.of(context).push<FaceEnrollmentCapture>(
        MaterialPageRoute(
          builder: (_) => FaceEnrollmentScreen(
            engine: engine,
            purpose: FaceCapturePurpose.authentication,
            onEmergencyStop: context.read<CraneController>().triggerEStop,
          ),
        ),
      );
      if (!mounted) return;
      if (capture == null) {
        setState(() {
          _busy = false;
          _result = const OperatorIdentificationResult(
            status: OperatorIdentificationStatus.failed,
            message:
                'Face authentication was cancelled. Control access remains locked.',
          );
        });
        return;
      }

      final identification = OperatorIdentificationService(
        repository: _repository,
        engine: engine,
      );
      final result = await identification.identify(capture);
      if (!mounted) return;

      final crane = context.read<CraneController>();
      final currentConnectionId = crane.connectionState.connectedDevice?.id;
      if (result.isAuthenticated &&
          currentConnectionId == widget.plcConnectionId) {
        context.read<OperatorSessionController>().establish(
          operator: result.operator!,
          plcConnectionId: widget.plcConnectionId,
        );
        return;
      }

      setState(() {
        _busy = false;
        _result = result.isAuthenticated
            ? const OperatorIdentificationResult(
                status: OperatorIdentificationStatus.failed,
                message:
                    'The PLC connection changed during face authentication. Reconnect and try again.',
              )
            : result;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _result = const OperatorIdentificationResult(
            status: OperatorIdentificationStatus.failed,
            message:
                'Face authentication is unavailable. Control access remains locked.',
          );
        });
      }
    } finally {
      await engine.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final crane = context.watch<CraneController>();
    return Scaffold(
      backgroundColor: AppColors.brandBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.brandSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.brandBorder),
                  boxShadow: AppMetrics.shadowMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: AppColors.brandVioletSoft,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.face_retouching_natural_rounded,
                        color: AppColors.brandVioletDeep,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Human identity required',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.brandText,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Identify an active registered operator before entering PLC credentials. Face identity and PLC authentication are separate requirements.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.brandTextSub,
                        fontSize: 13.5,
                        height: 1.45,
                      ),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 18),
                      _IdentificationMessage(result: _result!),
                    ],
                    const SizedBox(height: 22),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandViolet,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(54),
                      ),
                      onPressed: _busy ? null : _authenticateFace,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_front_rounded),
                      label: Text(_busy ? 'AUTHENTICATING...' : 'SCAN FACE'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.brandDanger,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => unawaited(crane.triggerEStop()),
                      icon: const Icon(Icons.emergency_rounded),
                      label: const Text('EMERGENCY STOP'),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _busy ? null : crane.disconnect,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Back to PLC scan'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IdentificationMessage extends StatelessWidget {
  const _IdentificationMessage({required this.result});

  final OperatorIdentificationResult result;

  @override
  Widget build(BuildContext context) {
    final isWarning =
        result.status == OperatorIdentificationStatus.unknown ||
        result.status == OperatorIdentificationStatus.livenessFailed;
    final color = isWarning ? AppColors.brandWarning : AppColors.brandDanger;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gpp_bad_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.message,
              style: const TextStyle(
                color: AppColors.brandTextSub,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
