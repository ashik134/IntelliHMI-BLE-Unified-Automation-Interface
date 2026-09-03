import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/face_enrollment_status.dart';

/// Visual guide + status caption for the face-enrollment capture screen.
///
/// Deliberately does NOT draw a box around the live-detected face —
/// doing that correctly means mapping ML-processing image coordinates
/// onto the (mirrored, aspect-fit-scaled) camera preview, which is
/// exactly the kind of transform this feature's own requirements say to
/// keep separate from ML coordinates, and isn't verifiable without a
/// real device. Instead this shows a fixed capture-region guide the
/// operator aligns themselves to, driven only by [state]'s status/
/// progress — simple, and correct by construction regardless of preview
/// scaling.
class FaceCaptureOverlay extends StatelessWidget {
  const FaceCaptureOverlay({super.key, required this.state});

  final FaceEnrollmentState state;

  bool get _isGoodFrame =>
      state.status == FaceEnrollmentStatus.capturing ||
      state.status == FaceEnrollmentStatus.processing ||
      state.status == FaceEnrollmentStatus.complete;

  bool get _isProblem =>
      state.status == FaceEnrollmentStatus.multipleFaces ||
      state.status == FaceEnrollmentStatus.duplicateDetected ||
      state.status == FaceEnrollmentStatus.failed ||
      state.status == FaceEnrollmentStatus.cameraError ||
      state.status == FaceEnrollmentStatus.permissionDenied;

  Color get _guideColor {
    if (_isProblem) return AppColors.brandDanger;
    if (_isGoodFrame) return AppColors.brandSuccess;
    return Colors.white.withAlpha(210);
  }

  bool get _showProgress =>
      state.status == FaceEnrollmentStatus.capturing ||
      state.status == FaceEnrollmentStatus.processing;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Align(
          // Must stay dead-center: `FaceDetectionService.evaluateQuality`'s
          // center-offset acceptance check is measured against the raw
          // frame's true geometric center, which — by construction, this
          // preview fills the same rect this overlay does — maps exactly
          // onto this rect's center regardless of rotation/scaling. Any
          // offset here (e.g. shifting the oval up for a "chin-inclusive"
          // look) desyncs the visible guide from the actual acceptance
          // region: a face centered in the oval would then read as
          // off-center to the quality check, and vice versa.
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 260,
            height: 330,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(160),
              border: Border.all(color: _guideColor, width: 3),
            ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
              if (_showProgress) ...[
                const SizedBox(height: 10),
                Text(
                  'Capturing ${state.samplesCaptured}/${state.samplesRequired}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 180,
                    height: 6,
                    child: LinearProgressIndicator(
                      value: state.samplesRequired == 0
                          ? 0
                          : state.samplesCaptured / state.samplesRequired,
                      backgroundColor: Colors.white24,
                      color: AppColors.brandViolet,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
