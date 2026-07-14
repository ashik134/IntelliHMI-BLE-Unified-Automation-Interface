import 'dart:math' as math;

import 'package:flutter/material.dart';

class CustomCircularStepProgressIndicator extends StatefulWidget {
  const CustomCircularStepProgressIndicator({
    super.key,
    required this.totalSteps,
    required this.currentStep,
    required this.stepSize,
    required this.selectedColor,
    required this.unselectedColor,
    required this.width,
    required this.height,
    this.padding = 0.025,
    this.startingAngle = -math.pi / 2,
    this.arcSize = math.pi * 2,
    this.gradientColor,
    this.backgroundColor,
    this.strokeCap = StrokeCap.round,
    this.animationDuration = const Duration(milliseconds: 450),
    this.onStepTapped,
    this.isAnimating = false,
    this.rotationDuration = const Duration(milliseconds: 1100),
    this.showCenterText = true,
    this.showStepDots = true,
    this.showGlow = true,
    this.centerTitle,
    this.centerSubtitle,
  });

  final int totalSteps;
  final int currentStep;
  final double stepSize;
  final Color selectedColor;
  final Color unselectedColor;
  final double width;
  final double height;
  final double padding;
  final double startingAngle;
  final double arcSize;
  final Gradient? gradientColor;
  final Color? backgroundColor;
  final StrokeCap strokeCap;
  final Duration animationDuration;
  final void Function(int step)? onStepTapped;

  final bool isAnimating;
  final Duration rotationDuration;

  final bool showCenterText;
  final bool showStepDots;
  final bool showGlow;
  final String? centerTitle;
  final String? centerSubtitle;

  @override
  State<CustomCircularStepProgressIndicator> createState() =>
      _CustomCircularStepProgressIndicatorState();
}

class _CustomCircularStepProgressIndicatorState
    extends State<CustomCircularStepProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  late final Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: widget.rotationDuration,
    );

    _rotationAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );

    if (widget.isAnimating) {
      _rotationController.repeat();
    }
  }

  @override
  void didUpdateWidget(CustomCircularStepProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.rotationDuration != oldWidget.rotationDuration) {
      _rotationController.duration = widget.rotationDuration;
    }

    if (widget.isAnimating != oldWidget.isAnimating) {
      if (widget.isAnimating) {
        _rotationController.repeat();
      } else {
        _rotationController
          ..stop()
          ..reset();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  int get _safeTotalSteps => math.max(widget.totalSteps, 1);

  int get _safeCurrentStep =>
      widget.currentStep.clamp(0, _safeTotalSteps).toInt();

  // double get _progressPercent => _safeCurrentStep / _safeTotalSteps;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: widget.width,
      height: widget.height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _safeCurrentStep.toDouble()),
        duration: widget.animationDuration,
        curve: Curves.easeOutCubic,
        builder: (context, animatedStep, _) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.onStepTapped == null
                ? null
                : (details) => _handleTap(details, context),
            child: CustomPaint(
              painter: _CircularStepPainter(
                totalSteps: _safeTotalSteps,
                currentStep: animatedStep,
                stepSize: widget.stepSize,
                selectedColor: widget.selectedColor,
                unselectedColor: widget.unselectedColor,
                padding: widget.padding,
                startingAngle: widget.startingAngle,
                arcSize: widget.arcSize,
                gradientColor: widget.gradientColor,
                backgroundColor: widget.backgroundColor,
                strokeCap: widget.strokeCap,
                showStepDots: widget.showStepDots,
                showGlow: widget.showGlow,
              ),
              child: const SizedBox.expand(),
            ),
          );
        },
      ),
    );

    if (!widget.isAnimating) return indicator;

    return RotationTransition(turns: _rotationAnimation, child: indicator);
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final callback = widget.onStepTapped;
    if (callback == null) return;

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final size = renderBox.size;
    final center = Offset(size.width / 2, size.height / 2);

    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);

    final radius = math.min(size.width, size.height) / 2;
    final touchMin = radius - widget.stepSize * 2.2;
    final touchMax = radius + widget.stepSize * 0.8;

    if (distance < touchMin || distance > touchMax) return;

    double angle = math.atan2(dy, dx);
    angle = (angle - widget.startingAngle) % (math.pi * 2);
    if (angle < 0) angle += math.pi * 2;

    if (angle > widget.arcSize) return;

    final stepAngle = widget.arcSize / _safeTotalSteps;
    final step = (angle / stepAngle).floor().clamp(0, _safeTotalSteps - 1);

    callback(step + 1);
  }
}

class _CircularStepPainter extends CustomPainter {
  const _CircularStepPainter({
    required this.totalSteps,
    required this.currentStep,
    required this.stepSize,
    required this.selectedColor,
    required this.unselectedColor,
    required this.padding,
    required this.startingAngle,
    required this.arcSize,
    required this.gradientColor,
    required this.backgroundColor,
    required this.strokeCap,
    required this.showStepDots,
    required this.showGlow,
  });

  final int totalSteps;
  final double currentStep;
  final double stepSize;
  final Color selectedColor;
  final Color unselectedColor;
  final double padding;
  final double startingAngle;
  final double arcSize;
  final Gradient? gradientColor;
  final Color? backgroundColor;
  final StrokeCap strokeCap;
  final bool showStepDots;
  final bool showGlow;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || totalSteps <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final shortestSide = math.min(size.width, size.height);

    final radius = (shortestSide / 2) - (stepSize / 2) - 4;
    if (radius <= 0) return;

    final circleRect = Rect.fromCircle(center: center, radius: radius);
    final stepAngle = arcSize / totalSteps;
    final gap = padding.clamp(0.0, stepAngle * 0.35);
    final sweepAngle = math.max(0.0, stepAngle - gap * 2);

    // _drawSoftOuterShadow(canvas, center, radius);
    _drawInnerPanel(canvas, center, radius);

    // if (backgroundColor != null) {
    //   _drawBackgroundRing(canvas, circleRect);
    // }

    for (int i = 0; i < totalSteps; i++) {
      final stepProgress = (currentStep - i).clamp(0.0, 1.0);
      final isSelected = stepProgress > 0;

      final start = startingAngle + (i * stepAngle) + gap;
      final sweep = sweepAngle * stepProgress;

      // _drawStepBackground(canvas, circleRect, start, sweepAngle);

      if (isSelected && sweep > 0) {
        _drawSelectedStep(canvas, circleRect, start, sweep);
      }

      if (showStepDots) {
        _drawStepDot(
          canvas: canvas,
          center: center,
          radius: radius,
          angle: start + sweepAngle / 2,
          isSelected: isSelected,
          progress: stepProgress,
        );
      }
    }
  }

  // void _drawSoftOuterShadow(Canvas canvas, Offset center, double radius) {
  //   if (!showGlow) return;

  //   // final shadowPaint = Paint()
  //   //   ..color = selectedColor.withAlpha(28)
  //   //   ..style = PaintingStyle.stroke
  //   //   ..strokeWidth = stepSize + 10
  //   //   ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);

  //   // canvas.drawCircle(center, radius, shadowPaint);
  // }

  void _drawInnerPanel(Canvas canvas, Offset center, double radius) {
    final panelRadius = radius - stepSize * 1.3;
    if (panelRadius <= 0) return;

    final panelPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withAlpha(26), Colors.black.withAlpha(18)],
      ).createShader(Rect.fromCircle(center: center, radius: panelRadius));

    canvas.drawCircle(center, panelRadius, panelPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withAlpha(22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, panelRadius, borderPaint);
  }

  // void _drawBackgroundRing(Canvas canvas, Rect rect) {
  //   final paint = Paint()
  //     ..color = backgroundColor!
  //     ..style = PaintingStyle.stroke
  //     ..strokeWidth = stepSize + 2
  //     ..strokeCap = strokeCap;

  //   canvas.drawArc(rect, startingAngle, arcSize, false, paint);
  // }

  // void _drawStepBackground(
  //   Canvas canvas,
  //   Rect rect,
  //   double start,
  //   double sweep,
  // ) {
  //   final paint = Paint()
  //     ..color = unselectedColor
  //     ..style = PaintingStyle.stroke
  //     ..strokeWidth = stepSize
  //     ..strokeCap = strokeCap;

  //   canvas.drawArc(rect, start, sweep, false, paint);
  // // }

  void _drawSelectedStep(Canvas canvas, Rect rect, double start, double sweep) {
    // if (showGlow) {
    //   final glowPaint = Paint()
    //     ..color = selectedColor.withAlpha(75)
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = stepSize + 4
    //     ..strokeCap = strokeCap
    //     ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    //   canvas.drawArc(rect, start, sweep, false, glowPaint);
    // }

    final selectedPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stepSize
      ..strokeCap = strokeCap;

    if (gradientColor != null) {
      selectedPaint.shader = gradientColor!.createShader(rect);
    } else {
      selectedPaint.color = selectedColor;
    }

    canvas.drawArc(rect, start, sweep, false, selectedPaint);

    final highlightPaint = Paint()
      ..color = Colors.white.withAlpha(55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, stepSize * 0.16)
      ..strokeCap = strokeCap;

    final highlightRect = Rect.fromCircle(
      center: rect.center,
      radius: rect.width / 2 - stepSize * 0.22,
    );

    canvas.drawArc(highlightRect, start, sweep, false, highlightPaint);
  }

  void _drawStepDot({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double angle,
    required bool isSelected,
    required double progress,
  }) {
    final dotRadius = isSelected
        ? (stepSize * 0.15 + progress * stepSize * 0.10)
        : stepSize * 0.12;

    final dotCenter = Offset(
      center.dx + math.cos(angle) * radius,
      center.dy + math.sin(angle) * radius,
    );

    final dotPaint = Paint()
      ..color = isSelected
          ? Colors.white.withAlpha(210)
          : Colors.white.withAlpha(70);

    canvas.drawCircle(dotCenter, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(_CircularStepPainter oldDelegate) {
    return oldDelegate.totalSteps != totalSteps ||
        oldDelegate.currentStep != currentStep ||
        oldDelegate.stepSize != stepSize ||
        oldDelegate.selectedColor != selectedColor ||
        oldDelegate.unselectedColor != unselectedColor ||
        oldDelegate.padding != padding ||
        oldDelegate.startingAngle != startingAngle ||
        oldDelegate.arcSize != arcSize ||
        oldDelegate.gradientColor != gradientColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.strokeCap != strokeCap ||
        oldDelegate.showStepDots != showStepDots ||
        oldDelegate.showGlow != showGlow;
  }
}

// class _CenterContent extends StatelessWidget {
//   const _CenterContent({
//     required this.title,
//     required this.subtitle,
//     required this.color,
//   });

//   final String title;
//   final String subtitle;
//   final Color color;

//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: FittedBox(
//         fit: BoxFit.scaleDown,
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(
//               title,
//               style: TextStyle(
//                 fontSize: 28,
//                 fontWeight: FontWeight.w900,
//                 color: color,
//                 letterSpacing: -0.8,
//               ),
//             ),
//             const SizedBox(height: 3),
//             Text(
//               subtitle.toUpperCase(),
//               style: TextStyle(
//                 fontSize: 10,
//                 fontWeight: FontWeight.w700,
//                 color: Colors.white.withAlpha(150),
//                 letterSpacing: 1.1,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
