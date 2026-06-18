import 'dart:math';
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
    this.padding = 0,
    this.startingAngle = -math.pi / 2, //  top (-90°)
    this.arcSize = math.pi * 2, // full circle
    this.gradientColor,
    this.backgroundColor,
    this.strokeCap = StrokeCap.round,
    this.animationDuration = const Duration(milliseconds: 300),
    this.onStepTapped,
    this.isAnimating = false,
    this.rotationDuration = const Duration(milliseconds: 1100),
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

  @override
  Widget build(BuildContext context) {
    final Widget indicator = SizedBox(
      width: widget.width,
      height: widget.height,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: widget.currentStep.toDouble()),
        duration: widget.animationDuration,
        builder: (context, animatedValue, child) {
          return CustomPaint(
            painter: _CircularStepPainter(
              totalSteps: widget.totalSteps,
              currentStep: animatedValue.toInt(),
              stepSize: widget.stepSize,
              selectedColor: widget.selectedColor,
              unselectedColor: widget.unselectedColor,
              padding: widget.padding,
              startingAngle: widget.startingAngle,
              arcSize: widget.arcSize,
              gradientColor: widget.gradientColor,
              backgroundColor: widget.backgroundColor,
              strokeCap: widget.strokeCap,
            ),
            child: GestureDetector(
              onTapDown: (details) => _handleTap(details, context),
              child: const Center(),
            ),
          );
        },
      ),
    );

    if (widget.isAnimating) {
      return RotationTransition(turns: _rotationAnimation, child: indicator);
    }
    return indicator;
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    if (widget.onStepTapped == null) return;

    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset localPosition = box.globalToLocal(details.globalPosition);
    final Size size = box.size;

    // Calculate angle from center
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double dx = localPosition.dx - center.dx;
    final double dy = localPosition.dy - center.dy;
    double angle = math.atan2(dy, dx);

    // Adjust angle based on starting angle
    angle = (angle - widget.startingAngle) % (math.pi * 2);
    if (angle < 0) angle += math.pi * 2;

    // Calculate which step was tapped
    final double stepAngle = widget.arcSize / widget.totalSteps;
    final int step = (angle / stepAngle).floor().clamp(
      0,
      widget.totalSteps - 1,
    );

    widget.onStepTapped!(step + 1);
  }
}

class _CircularStepPainter extends CustomPainter {
  _CircularStepPainter({
    required this.totalSteps,
    required this.currentStep,
    required this.stepSize,
    required this.selectedColor,
    required this.unselectedColor,
    required this.padding,
    required this.startingAngle,
    required this.arcSize,
    this.gradientColor,
    this.backgroundColor,
    this.strokeCap = StrokeCap.round,
  });

  final int totalSteps;
  final int currentStep;
  final double stepSize;
  final Color selectedColor;
  final Color unselectedColor;
  final double padding;
  final double startingAngle;
  final double arcSize;
  final Gradient? gradientColor;
  final Color? backgroundColor;
  final StrokeCap strokeCap;

  late final Paint _backgroundPaint = Paint()
    ..color = backgroundColor ?? Colors.grey.shade200
    ..style = PaintingStyle.stroke
    ..strokeWidth = stepSize
    ..strokeCap = strokeCap;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final Offset center = rect.center;
    final double radius = (min(size.width, size.height) / 2) - (stepSize / 2);

    // Draw background circle
    if (backgroundColor != null) {
      canvas.drawCircle(center, radius + stepSize / 2, _backgroundPaint);
    }

    // Calculate step angle
    final double stepAngle = arcSize / totalSteps;
    final double stepSpacing = padding * 2;
    final double effectiveStepAngle = stepAngle - stepSpacing;

    // Draw each step
    for (int i = 0; i < totalSteps; i++) {
      final bool isSelected = i < currentStep;

      // Calculate start and end angles
      final double startAngle = startingAngle + (i * stepAngle) + padding;
      final double endAngle = startAngle + effectiveStepAngle;

      // Select color
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stepSize
        ..strokeCap = strokeCap;

      if (isSelected && gradientColor != null) {
        final Gradient gradient = gradientColor!;

        final Shader shader = gradient.createShader(
          Rect.fromCircle(center: center, radius: radius),
        );
        paint.shader = shader;
      } else if (isSelected) {
        paint.color = selectedColor;
      } else {
        paint.color = unselectedColor;
      }

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CircularStepPainter oldDelegate) {
    return oldDelegate.currentStep != currentStep ||
        oldDelegate.totalSteps != totalSteps ||
        oldDelegate.selectedColor != selectedColor ||
        oldDelegate.unselectedColor != unselectedColor;
  }
}
