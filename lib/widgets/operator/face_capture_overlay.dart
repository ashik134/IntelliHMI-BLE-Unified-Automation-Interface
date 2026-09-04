import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    this.scanProgress,
  });

  final String caption;
  final Color guideColor;
  final double guideDiameter;

  /// Fraction (0.0..1.0) of the continuous face scan elapsed. Non-null
  /// only while actively scanning — draws a rotating/filling ring around
  /// the guide instead of the plain static circle, so the operator sees
  /// one continuous "Scanning your face…" motion rather than a
  /// sample-by-sample counter (see `FaceEnrollmentStatus`'s doc comment
  /// on why there's deliberately no "N of M" label here).
  final double? scanProgress;

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
          child: SizedBox(
            width: guideDiameter,
            height: guideDiameter,
            child: scanProgress != null
                ? _ScanRing(progress: scanProgress!, color: guideColor)
                : AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: guideColor, width: 3),
                    ),
                  ),
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 56,
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
            ),
          ),
        ),
      ],
    );
  }
}

/// The guide oval's appearance while a continuous scan is in progress: a
/// static base ring plus a brand-colored arc that sweeps clockwise from
/// the top as [progress] advances (the "pie timer" look from this
/// feature's spec — 0%/25%/50%/75%/100% reading as ◔◑◕●), overlaid with a
/// smaller continuously-rotating dash so the guide always reads as
/// "actively scanning," not just "waiting," even during the instants
/// [progress] itself barely advances between camera frames.
///
/// Both arcs are driven by their own [AnimationController]s rather than
/// solely by [progress] jumping straight to each new value on `setState` —
/// camera-frame-driven updates land at a real but uneven cadence (ML
/// inference time varies frame to frame), and animating between them
/// keeps the ring's motion visually smooth regardless of that jitter.
class _ScanRing extends StatefulWidget {
  const _ScanRing({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  State<_ScanRing> createState() => _ScanRingState();
}

class _ScanRingState extends State<_ScanRing>
    with TickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: widget.progress),
      duration: const Duration(milliseconds: 180),
      builder: (context, animatedProgress, _) {
        return AnimatedBuilder(
          animation: _rotationController,
          builder: (context, _) {
            return CustomPaint(
              painter: _ScanRingPainter(
                progress: animatedProgress.clamp(0.0, 1.0),
                rotationTurns: _rotationController.value,
                color: widget.color,
              ),
            );
          },
        );
      },
    );
  }
}

class _ScanRingPainter extends CustomPainter {
  _ScanRingPainter({
    required this.progress,
    required this.rotationTurns,
    required this.color,
  });

  final double progress;
  final double rotationTurns;
  final Color color;

  static const double _strokeWidth = 3.5;
  static const double _dashSweepRadians = math.pi / 6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = rect.deflate(_strokeWidth / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..color = color.withAlpha(70);
    canvas.drawOval(inset, track);

    // Progress arc: starts at 12 o'clock, sweeps clockwise.
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      inset,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );

    // Small rotating dash layered on top, purely decorative motion so the
    // guide never looks static between progress updates.
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withAlpha(230);
    final dashStart = 2 * math.pi * rotationTurns;
    canvas.drawArc(inset, dashStart, _dashSweepRadians, false, dashPaint);
  }

  @override
  bool shouldRepaint(covariant _ScanRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.rotationTurns != rotationTurns ||
        oldDelegate.color != color;
  }
}
