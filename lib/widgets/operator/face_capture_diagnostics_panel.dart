import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/face_capture_diagnostics.dart';
import 'package:rev_crane_control_ops/services/face_detection_service.dart';
import 'package:rev_crane_control_ops/services/frame_quality_analyzer.dart';

/// Debug-only readout of the live per-frame quality metrics driving
/// capture decisions — face count, pose angle, framing size, lighting,
/// sharpness. Only ever constructed behind `kDebugMode` by the screen
/// that owns it (see `FaceEnrollmentScreen`); never shows an embedding or
/// any biometric payload, only derived scalar metrics.
class FaceCaptureDiagnosticsPanel extends StatelessWidget {
  const FaceCaptureDiagnosticsPanel({super.key, required this.diagnostics});

  final FaceCaptureDiagnostics diagnostics;

  String _fmt(double? value, {int decimals = 1, String suffix = ''}) {
    if (value == null) return '—';
    return '${value.toStringAsFixed(decimals)}$suffix';
  }

  String _pass(bool? value) {
    if (value == null) return '—';
    return value ? 'OK' : 'FAIL';
  }

  @override
  Widget build(BuildContext context) {
    final d = diagnostics;
    final lines = [
      'DEBUG  faces: ${d.faceCount}  ready: ${d.readyForCapture ? 'YES' : 'no'}',
      'yaw: ${_fmt(d.yawDegrees, suffix: '°')} (${_pass(d.posePassed)})  '
          'pitch: ${_fmt(d.pitchDegrees, suffix: '°')}',
      'size: ${_fmt(d.faceWidthFraction == null ? null : d.faceWidthFraction! * 100, suffix: '%')} '
          '(${(FaceDetectionService.minFaceWidthFraction * 100).toStringAsFixed(0)}-'
          '${(FaceDetectionService.maxFaceWidthFraction * 100).toStringAsFixed(0)}) '
          '(${_pass(d.sizePassed)})',
      'offset: ${_fmt(d.centerOffsetFraction == null ? null : d.centerOffsetFraction! * 100, suffix: '%')} '
          '(max ${(FaceDetectionService.maxCenterOffsetFraction * 100).toStringAsFixed(0)}) '
          '(${_pass(d.centerPassed)})',
      'eyes: ${_pass(d.eyesPassed)}',
      'bright: ${_fmt(d.brightness, decimals: 0)} '
          '(${FrameQualityAnalyzer.minBrightness.toStringAsFixed(0)}-'
          '${FrameQualityAnalyzer.maxBrightness.toStringAsFixed(0)}) '
          '(${_pass(d.brightnessPassed)})',
      'sharp: ${_fmt(d.sharpness, decimals: 0)} '
          '(min ${FrameQualityAnalyzer.minSharpness.toStringAsFixed(0)}) '
          '(${_pass(d.sharpnessPassed)})',
      if (d.currentPoseLabel != null)
        'pose: ${d.currentPoseLabel}  matched: ${_pass(d.poseMatched)}',
      'landmarks: present ${_pass(d.landmarksPresent)}  '
          'contained ${_pass(d.landmarksContained)}',
      if (d.scanning)
        'CAPTURING ${((d.scanProgress ?? 0) * 100).toStringAsFixed(0)}%  '
            'anchor: ${d.identityLocked ? 'YES' : 'no'}  '
            'samples: ${d.samplesAccepted ?? 0}'
      else if (d.stableProgress != null)
        'stable: ${((d.stableProgress ?? 0) * 100).toStringAsFixed(0)}%',
      if (d.failedReason != null) 'blocked by: ${d.failedReason}',
    ];

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(160),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              Text(
                line,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 10.5,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
