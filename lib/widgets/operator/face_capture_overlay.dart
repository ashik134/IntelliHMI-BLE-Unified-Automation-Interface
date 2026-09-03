import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

/// Visual guide + status caption shared by the enrollment and
/// verification capture screens, so both present identical acquisition
/// guidance for the identical underlying readiness pipeline
/// (`FaceDetectionService.evaluateQuality`).
///
/// Deliberately does NOT draw a box around the live-detected face —
/// doing that correctly means mapping ML-processing image coordinates
/// onto the (aspect-fit-scaled) camera preview on every frame, which is
/// exactly the kind of transform this feature's own requirements say to
/// keep separate from ML coordinates, and isn't verifiable without a
/// real device. Instead this shows a fixed capture-region guide the
/// operator aligns themselves to.
///
/// [guideDiameter] is the caller's responsibility to size correctly —
/// see `FaceDetectionService.centerToleranceRadiusPx`, which derives it
/// from the exact same [FaceDetectionService.maxCenterOffsetFraction]
/// threshold `evaluateQuality` gates on, mapped through the real
/// on-screen preview scale. Passing an arbitrary constant here would
/// silently desync the drawn guide from the actual acceptance region —
/// the caller is expected not to.
class FaceCaptureOverlay extends StatelessWidget {
  const FaceCaptureOverlay({
    super.key,
    required this.caption,
    required this.guideColor,
    required this.guideDiameter,
    this.progressLabel,
    this.progressValue,
  });

  final String caption;
  final Color guideColor;
  final double guideDiameter;

  /// Non-null together: shown as a label + bar under the caption (e.g.
  /// enrollment's sample progress). Null on screens with nothing to
  /// track toward (e.g. verification).
  final String? progressLabel;
  final double? progressValue;

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
          // offset here (e.g. shifting the guide up for a "chin-inclusive"
          // look) desyncs the visible guide from the actual acceptance
          // region: a face centered in the guide would then read as
          // off-center to the quality check, and vice versa.
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: guideDiameter,
            height: guideDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: guideColor, width: 3),
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
                caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
              if (progressLabel != null && progressValue != null) ...[
                const SizedBox(height: 10),
                Text(
                  progressLabel!,
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
                      value: progressValue,
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
