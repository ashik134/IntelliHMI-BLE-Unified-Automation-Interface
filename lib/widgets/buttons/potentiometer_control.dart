import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

const double _kStartAngle = math.pi * 0.75;
const double _kSweepAngle = math.pi * 1.5;

class IndustrialPotentiometerControl extends StatefulWidget {
  const IndustrialPotentiometerControl({
    super.key,
    required this.config,
    required this.label,
    required this.activeColor,
    required this.activeColorLight,
    required this.enabled,
    required this.onChanged,
    this.icon,
  });

  final PotentiometerConfig config;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<IndustrialPotentiometerControl> createState() =>
      _IndustrialPotentiometerControlState();
}

class _IndustrialPotentiometerControlState
    extends State<IndustrialPotentiometerControl> {
  late double _value;
  double? _dragStartAngle;
  double? _dragLastAngle;
  double _dragAccumulatedAngle = 0.0;
  double? _dragStartValue;
  bool _isDragging = false;

  PotentiometerConfig get _config => widget.config.normalized();

  @override
  void initState() {
    super.initState();
    _value = _config.defaultValue;
  }

  @override
  void didUpdateWidget(covariant IndustrialPotentiometerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _value = _config.clampAndSnap(_value);
    }
  }

  void _setValue(double next, {bool haptic = false}) {
    final snapped = _config.clampAndSnap(next);
    if (snapped == _value) return;
    setState(() => _value = snapped);
    if (haptic) HapticFeedback.selectionClick();
    widget.onChanged(snapped);
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (!widget.enabled) return;
    if (!_isGripHit(details.localPosition, size)) {
      _resetDrag();
      return;
    }

    final angle = _angleForPosition(details.localPosition, size);
    setState(() {
      _isDragging = true;
      _dragStartAngle = angle;
      _dragLastAngle = angle;
      _dragAccumulatedAngle = 0.0;
      _dragStartValue = _value;
    });
    HapticFeedback.selectionClick();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (!widget.enabled || !_isDragging) return;
    final angle = _angleForPosition(details.localPosition, size);
    if (angle == null) return;

    final lastAngle = _dragLastAngle ?? _dragStartAngle;
    if (lastAngle == null) {
      _dragStartAngle = angle;
      _dragLastAngle = angle;
      _dragAccumulatedAngle = 0.0;
      _dragStartValue = _value;
      return;
    }

    _dragAccumulatedAngle += _signedAngleDelta(angle, lastAngle);
    _dragLastAngle = angle;

    final valueDelta = (_dragAccumulatedAngle / _kSweepAngle) * _config.range;
    _setValue((_dragStartValue ?? _value) + valueDelta, haptic: true);
  }

  void _handlePanEnd() {
    if (!widget.enabled) return;
    final wasDragging = _isDragging;
    _resetDrag();
    if (wasDragging) HapticFeedback.lightImpact();
  }

  void _resetDrag() {
    final needsRepaint =
        _isDragging ||
        _dragStartAngle != null ||
        _dragLastAngle != null ||
        _dragAccumulatedAngle != 0.0 ||
        _dragStartValue != null;
    if (!needsRepaint) return;

    setState(() {
      _isDragging = false;
      _dragStartAngle = null;
      _dragLastAngle = null;
      _dragAccumulatedAngle = 0.0;
      _dragStartValue = null;
    });
  }

  double? _angleForPosition(Offset localPosition, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = localPosition - center;
    if (delta.distance < math.min(size.width, size.height) * 0.08) return null;

    return math.atan2(delta.dy, delta.dx);
  }

  bool _isGripHit(Offset localPosition, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final delta = localPosition - center;
    final knobRadius = side * 0.33;

    if (delta.distance <= knobRadius * 1.15) return true;

    final normalized = _config.normalizedValueFor(_value);
    final indicatorAngle = _kStartAngle + _kSweepAngle * normalized;
    final indicatorEnd =
        center +
        Offset(
          math.cos(indicatorAngle) * knobRadius * 0.78,
          math.sin(indicatorAngle) * knobRadius * 0.78,
        );
    return (localPosition - indicatorEnd).distance <= side * 0.16;
  }

  double _signedAngleDelta(double current, double previous) {
    var delta = current - previous;
    while (delta > math.pi) {
      delta -= math.pi * 2;
    }
    while (delta < -math.pi) {
      delta += math.pi * 2;
    }
    return delta;
  }

  void _nudge(int direction) {
    if (!widget.enabled) return;
    _setValue(_value + _config.stepSize * direction, haptic: true);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final normalized = config.normalizedValueFor(_value);
    final valueText = config.formatValue(_value);

    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: widget.label,
      value: valueText,
      increasedValue: config.formatValue(_value + config.stepSize),
      decreasedValue: config.formatValue(_value - config.stepSize),
      onIncrease: widget.enabled ? () => _nudge(1) : null,
      onDecrease: widget.enabled ? () => _nudge(-1) : null,
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.52,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 180.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 180.0;
            final side = math.max(72.0, math.min(maxW, maxH));

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled
                  ? (details) => _handlePanStart(details, Size(maxW, maxH))
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => _handlePanUpdate(details, Size(maxW, maxH))
                  : null,
              onPanEnd: widget.enabled ? (_) => _handlePanEnd() : null,
              onPanCancel: widget.enabled ? _handlePanEnd : null,
              child: SizedBox(
                width: maxW,
                height: maxH,
                child: Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: CustomPaint(
                      painter: _PotentiometerPainter(
                        normalizedValue: normalized,
                        valueText: valueText,
                        showValue: config.showValue,
                        label: widget.label,
                        icon: widget.icon,
                        enabled: widget.enabled,
                        activeColor: widget.activeColor,
                        activeColorLight: widget.activeColorLight,
                        isDragging: _isDragging,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PotentiometerPainter extends CustomPainter {
  const _PotentiometerPainter({
    required this.normalizedValue,
    required this.valueText,
    required this.showValue,
    required this.label,
    required this.icon,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.isDragging,
  });

  final double normalizedValue;
  final String valueText;
  final bool showValue;
  final String label;
  final IconData? icon;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final bool isDragging;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.48;
    final bezelR = side * 0.43;
    final knobR = side * 0.33;

    canvas.drawCircle(
      center + Offset(0, side * 0.035),
      outerR,
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    final outerRect = Rect.fromCircle(center: center, radius: outerR);
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.32, -0.42),
          radius: 1.2,
          colors: [Color(0xFF394A59), Color(0xFF17232D), Color(0xFF071018)],
          stops: [0.0, 0.58, 1.0],
        ).createShader(outerRect),
    );
    canvas.drawCircle(
      center,
      outerR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.012)
        ..color = Colors.white.withAlpha(enabled ? 34 : 16),
    );

    _drawTicks(canvas, center, side, outerR);
    _drawArc(canvas, center, bezelR);

    final knobRect = Rect.fromCircle(center: center, radius: knobR);
    canvas.drawCircle(
      center,
      knobR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.38, -0.48),
          radius: 1.1,
          colors: [Color(0xFFE5EBF0), Color(0xFF7E8B96), Color(0xFF2A333B)],
          stops: [0.0, 0.48, 1.0],
        ).createShader(knobRect),
    );
    canvas.drawCircle(
      center,
      knobR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.018)
        ..color = Colors.black.withAlpha(125),
    );

    final indicatorAngle = _kStartAngle + _kSweepAngle * normalizedValue;
    final indicatorStart =
        center +
        Offset(
          math.cos(indicatorAngle) * knobR * 0.15,
          math.sin(indicatorAngle) * knobR * 0.15,
        );
    final indicatorEnd =
        center +
        Offset(
          math.cos(indicatorAngle) * knobR * 0.78,
          math.sin(indicatorAngle) * knobR * 0.78,
        );
    canvas.drawLine(
      indicatorStart,
      indicatorEnd,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(3.0, side * 0.045)
        ..strokeCap = StrokeCap.round
        ..color = enabled ? activeColorLight : AppColors.disabled,
    );

    canvas.drawCircle(
      center,
      knobR * 0.38,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [
            Colors.white.withAlpha(enabled ? 104 : 46),
            Colors.black.withAlpha(42),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: knobR * 0.38)),
    );

    if (isDragging && enabled) {
      canvas.drawCircle(
        center,
        outerR - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, side * 0.016)
          ..color = activeColorLight.withAlpha(120),
      );
    }

    if (showValue) _paintValue(canvas, center, side);
    _paintLabel(canvas, center, side);
  }

  void _drawTicks(Canvas canvas, Offset center, double side, double radius) {
    final tickPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.0, side * 0.012);
    for (var i = 0; i <= 10; i++) {
      final t = i / 10.0;
      final angle = _kStartAngle + _kSweepAngle * t;
      final isMajor = i == 0 || i == 5 || i == 10;
      final startR = radius * (isMajor ? 0.82 : 0.86);
      final endR = radius * 0.93;
      tickPaint.color = Colors.white.withAlpha(
        enabled ? (isMajor ? 132 : 72) : 38,
      );
      canvas.drawLine(
        center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),
        center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),
        tickPaint,
      );
    }
  }

  void _drawArc(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      rect,
      _kStartAngle,
      _kSweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.075
        ..color = AppColors.darkBg.withAlpha(205),
    );
    canvas.drawArc(
      rect,
      _kStartAngle,
      _kSweepAngle * normalizedValue,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.075
        ..color = enabled ? activeColor : AppColors.disabled.withAlpha(110),
    );
  }

  void _paintValue(Canvas canvas, Offset center, double side) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: valueText,
        style: TextStyle(
          color: enabled ? AppColors.darkBg : AppColors.darkBorder,
          fontSize: (side * 0.095).clamp(10.0, 18.0).toDouble(),
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: side * 0.46);
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - side * 0.12),
    );
  }

  void _paintLabel(Canvas canvas, Offset center, double side) {
    final bounds = Rect.fromCenter(
      center: Offset(center.dx, center.dy + side * 0.23),
      width: side * 0.58,
      height: ControlButtonVisualMetrics.rowHeight,
    );
    ControlButtonVisualMetrics.paintLabelIcon(
      canvas,
      bounds: bounds,
      label: label,
      icon: icon,
      color: AppColors.darkText.withAlpha(enabled ? 230 : 118),
      iconColor: activeColorLight.withAlpha(enabled ? 230 : 100),
    );
  }

  @override
  bool shouldRepaint(covariant _PotentiometerPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.valueText != valueText ||
        oldDelegate.showValue != showValue ||
        oldDelegate.label != label ||
        oldDelegate.icon != icon ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isDragging != isDragging;
  }
}
