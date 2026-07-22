import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

const double _kDefaultStartAngle = math.pi * 0.75;
const double _kDefaultSweepAngle = math.pi * 1.5;
const double _kDefaultGaugeSide = 260.0;

@immutable
class RadialGaugeRange {
  const RadialGaugeRange({
    required this.startValue,
    required this.endValue,
    required this.color,
    this.label,
  });

  const RadialGaugeRange.normal({
    required this.startValue,
    required this.endValue,
    this.label = 'Normal',
  }) : color = AppColors.darkSuccess;

  const RadialGaugeRange.warning({
    required this.startValue,
    required this.endValue,
    this.label = 'Warning',
  }) : color = AppColors.fastColorLight;

  const RadialGaugeRange.danger({
    required this.startValue,
    required this.endValue,
    this.label = 'Danger',
  }) : color = AppColors.eStopColorLight;

  final double startValue;
  final double endValue;
  final Color color;
  final String? label;
}

class IndustrialRadialGaugeIndicator extends StatelessWidget {
  const IndustrialRadialGaugeIndicator({
    super.key,
    required this.value,
    this.minValue = 0,
    this.maxValue = 100,
    this.label = '',
    this.unit = '',
    this.majorTickInterval,
    this.minorTicksPerMajor = 4,
    this.ranges = const <RadialGaugeRange>[],
    this.showScaleLabels = true,
    this.showDigitalValue = true,
    this.showUnit = true,
    this.showActiveGlow = true,
    this.startAngle = _kDefaultStartAngle,
    this.sweepAngle = _kDefaultSweepAngle,
    this.animationDuration = const Duration(milliseconds: 650),
    this.animationCurve = Curves.easeOutCubic,
    this.size,
    this.accentColor = AppColors.darkInfo,
    this.needleColor = AppColors.eStopColorLight,
    this.panelColor = AppColors.panel,
    this.faceColor = const Color(0xFF121D26),
    this.valueFormatter,
    this.scaleLabelFormatter,
  });

  final double value;
  final double minValue;
  final double maxValue;
  final String label;
  final String unit;
  final double? majorTickInterval;
  final int minorTicksPerMajor;
  final List<RadialGaugeRange> ranges;
  final bool showScaleLabels;
  final bool showDigitalValue;
  final bool showUnit;
  final bool showActiveGlow;
  final double startAngle;
  final double sweepAngle;
  final Duration animationDuration;
  final Curve animationCurve;
  final double? size;
  final Color accentColor;
  final Color needleColor;
  final Color panelColor;
  final Color faceColor;
  final String Function(double value)? valueFormatter;
  final String Function(double value)? scaleLabelFormatter;

  @override
  Widget build(BuildContext context) {
    final safeMin = _finiteOr(minValue, 0);
    final safeMax = _safeMaxValue(safeMin, maxValue);
    final clampedValue = _clampDouble(
      _finiteOr(value, safeMin),
      safeMin,
      safeMax,
    );
    final displayValue = _formatValue(clampedValue, valueFormatter);
    final semanticValue = unit.trim().isEmpty || !showUnit
        ? displayValue
        : '$displayValue ${unit.trim()}';

    return Semantics(
      label: label.trim().isEmpty ? 'Radial gauge' : label.trim(),
      value: semanticValue,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = _resolveSide(constraints, size);

          return RepaintBoundary(
            child: SizedBox.square(
              dimension: side,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: clampedValue),
                duration: animationDuration,
                curve: animationCurve,
                builder: (context, animatedValue, _) {
                  final animatedDisplay = _formatValue(
                    animatedValue,
                    valueFormatter,
                  );

                  return CustomPaint(
                    painter: _IndustrialRadialGaugePainter(
                      value: animatedValue,
                      minValue: safeMin,
                      maxValue: safeMax,
                      displayValue: animatedDisplay,
                      label: label.trim(),
                      unit: showUnit ? unit.trim() : '',
                      majorTickInterval: majorTickInterval,
                      minorTicksPerMajor: minorTicksPerMajor,
                      ranges: ranges,
                      showScaleLabels: showScaleLabels,
                      showDigitalValue: showDigitalValue,
                      showActiveGlow: showActiveGlow,
                      startAngle: _finiteOr(startAngle, _kDefaultStartAngle),
                      sweepAngle: _safeSweepAngle(sweepAngle),
                      accentColor: accentColor,
                      needleColor: needleColor,
                      panelColor: panelColor,
                      faceColor: faceColor,
                      scaleLabelFormatter: scaleLabelFormatter,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IndustrialRadialGaugePainter extends CustomPainter {
  const _IndustrialRadialGaugePainter({
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.displayValue,
    required this.label,
    required this.unit,
    required this.majorTickInterval,
    required this.minorTicksPerMajor,
    required this.ranges,
    required this.showScaleLabels,
    required this.showDigitalValue,
    required this.showActiveGlow,
    required this.startAngle,
    required this.sweepAngle,
    required this.accentColor,
    required this.needleColor,
    required this.panelColor,
    required this.faceColor,
    required this.scaleLabelFormatter,
  });

  final double value;
  final double minValue;
  final double maxValue;
  final String displayValue;
  final String label;
  final String unit;
  final double? majorTickInterval;
  final int minorTicksPerMajor;
  final List<RadialGaugeRange> ranges;
  final bool showScaleLabels;
  final bool showDigitalValue;
  final bool showActiveGlow;
  final double startAngle;
  final double sweepAngle;
  final Color accentColor;
  final Color needleColor;
  final Color panelColor;
  final Color faceColor;
  final String Function(double value)? scaleLabelFormatter;

  double get _range => maxValue - minValue;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || _range <= 0) return;

    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = side * 0.475;
    final faceRadius = side * 0.392;
    final arcRadius = side * 0.336;
    final tickOuterRadius = side * 0.368;
    final activeColor = _activeColorFor(value);
    final normalizedValue = _normalizedFor(value);

    _drawPanelShadow(canvas, center, side, outerRadius);
    _drawOuterBezel(canvas, center, side, outerRadius);
    _drawDialFace(canvas, center, side, faceRadius);
    _drawSweepTrack(
      canvas,
      center,
      side,
      arcRadius,
      normalizedValue,
      activeColor,
    );
    _drawTicksAndLabels(canvas, center, side, tickOuterRadius);
    _drawTitle(canvas, center, side);
    if (showDigitalValue) {
      _drawDigitalReadout(canvas, center, side, activeColor);
    }
    _drawNeedle(canvas, center, side, normalizedValue, activeColor);
    _drawCenterHub(canvas, center, side);
    _drawGlassHighlight(canvas, center, faceRadius);
  }

  void _drawPanelShadow(
    Canvas canvas,
    Offset center,
    double side,
    double outerRadius,
  ) {
    canvas.drawCircle(
      center + Offset(0, side * 0.034),
      outerRadius * 0.985,
      Paint()
        ..color = Colors.black.withAlpha(145)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.042),
    );

    canvas.drawCircle(
      center,
      outerRadius,
      Paint()..color = panelColor.withAlpha(220),
    );
  }

  void _drawOuterBezel(
    Canvas canvas,
    Offset center,
    double side,
    double outerRadius,
  ) {
    final outerRect = Rect.fromCircle(center: center, radius: outerRadius);
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.36, -0.42),
          radius: 1.18,
          colors: [
            Color(0xFF8A98A3),
            Color(0xFF31414D),
            Color(0xFF131D25),
            Color(0xFF05080C),
          ],
          stops: [0.0, 0.34, 0.68, 1.0],
        ).createShader(outerRect),
    );

    canvas.drawCircle(
      center,
      outerRadius - side * 0.011,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.012)
        ..color = Colors.white.withAlpha(38),
    );

    canvas.drawCircle(
      center,
      outerRadius - side * 0.038,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.012)
        ..color = Colors.black.withAlpha(115),
    );
  }

  void _drawDialFace(
    Canvas canvas,
    Offset center,
    double side,
    double faceRadius,
  ) {
    final faceRect = Rect.fromCircle(center: center, radius: faceRadius);
    canvas.drawCircle(
      center,
      faceRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.46),
          radius: 1.2,
          colors: [
            Color.alphaBlend(Colors.white.withAlpha(18), faceColor),
            faceColor,
            const Color(0xFF071018),
          ],
          stops: const [0.0, 0.58, 1.0],
        ).createShader(faceRect),
    );

    canvas.drawCircle(
      center,
      faceRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.007)
        ..color = Colors.white.withAlpha(24),
    );

    canvas.drawCircle(
      center,
      faceRadius * 0.77,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.004)
        ..color = Colors.white.withAlpha(11),
    );
  }

  void _drawSweepTrack(
    Canvas canvas,
    Offset center,
    double side,
    double arcRadius,
    double normalizedValue,
    Color activeColor,
  ) {
    final rect = Rect.fromCircle(center: center, radius: arcRadius);
    final trackWidth = math.max(5.0, side * 0.032);

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = trackWidth
        ..color = Colors.black.withAlpha(140),
    );

    for (final range in ranges) {
      final rangeStart = _normalizedFor(range.startValue);
      final rangeEnd = _normalizedFor(range.endValue);
      final start = math.min(rangeStart, rangeEnd);
      final end = math.max(rangeStart, rangeEnd);
      if (end <= start) continue;

      canvas.drawArc(
        rect,
        startAngle + sweepAngle * start,
        sweepAngle * (end - start),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.butt
          ..strokeWidth = trackWidth
          ..color = range.color.withAlpha(178),
      );
    }

    if (ranges.isEmpty) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = trackWidth
          ..color = accentColor.withAlpha(92),
      );
    }

    if (showActiveGlow && normalizedValue > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * normalizedValue,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = trackWidth + side * 0.016
          ..color = activeColor.withAlpha(44)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.018),
      );
    }

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle * normalizedValue,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(2.0, side * 0.011)
        ..color = Color.alphaBlend(Colors.white.withAlpha(84), activeColor),
    );
  }

  void _drawTicksAndLabels(
    Canvas canvas,
    Offset center,
    double side,
    double tickOuterRadius,
  ) {
    final majorValues = _majorTickValues();
    if (majorValues.length < 2) return;

    final majorPaint = Paint()
      ..strokeCap = StrokeCap.square
      ..strokeWidth = math.max(1.3, side * 0.008)
      ..color = Colors.white.withAlpha(185);
    final minorPaint = Paint()
      ..strokeCap = StrokeCap.square
      ..strokeWidth = math.max(0.8, side * 0.004)
      ..color = Colors.white.withAlpha(82);

    for (var i = 0; i < majorValues.length; i++) {
      final tickValue = majorValues[i];
      final angle = startAngle + sweepAngle * _normalizedFor(tickValue);
      final start = _pointAt(center, angle, tickOuterRadius - side * 0.044);
      final end = _pointAt(center, angle, tickOuterRadius);
      canvas.drawLine(start, end, majorPaint);

      if (showScaleLabels) {
        _paintText(
          canvas,
          text: _formatValue(tickValue, scaleLabelFormatter),
          center: _pointAt(center, angle, side * 0.252),
          maxWidth: side * 0.16,
          style: TextStyle(
            color: AppColors.darkText.withAlpha(205),
            fontSize: (side * 0.038).clamp(8.0, 13.0).toDouble(),
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        );
      }

      if (i == majorValues.length - 1) continue;

      final minorCount = minorTicksPerMajor.clamp(0, 12).toInt();
      if (minorCount == 0) continue;

      final nextValue = majorValues[i + 1];
      for (var minor = 1; minor <= minorCount; minor++) {
        final t = minor / (minorCount + 1);
        final minorValue = tickValue + (nextValue - tickValue) * t;
        final minorAngle = startAngle + sweepAngle * _normalizedFor(minorValue);
        canvas.drawLine(
          _pointAt(center, minorAngle, tickOuterRadius - side * 0.025),
          _pointAt(center, minorAngle, tickOuterRadius),
          minorPaint,
        );
      }
    }
  }

  void _drawTitle(Canvas canvas, Offset center, double side) {
    if (label.isEmpty) return;

    _paintText(
      canvas,
      text: label.toUpperCase(),
      center: Offset(center.dx, center.dy - side * 0.17),
      maxWidth: side * 0.62,
      style: TextStyle(
        color: AppColors.darkText.withAlpha(190),
        fontSize: (side * 0.044).clamp(9.0, 15.0).toDouble(),
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
    );
  }

  void _drawDigitalReadout(
    Canvas canvas,
    Offset center,
    double side,
    Color activeColor,
  ) {
    final readoutRect = Rect.fromCenter(
      center: Offset(center.dx, center.dy + side * 0.2),
      width: side * 0.43,
      height: side * 0.112,
    );
    final readoutRRect = RRect.fromRectAndRadius(
      readoutRect,
      Radius.circular(math.min(8.0, side * 0.026)),
    );

    canvas.drawRRect(
      readoutRRect.shift(Offset(0, side * 0.007)),
      Paint()
        ..color = Colors.black.withAlpha(120)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.012),
    );
    canvas.drawRRect(
      readoutRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111C24), Color(0xFF071017)],
        ).createShader(readoutRect),
    );
    canvas.drawRRect(
      readoutRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.004)
        ..color = activeColor.withAlpha(116),
    );

    final valueText = unit.isEmpty ? displayValue : '$displayValue $unit';
    _paintText(
      canvas,
      text: valueText,
      center: readoutRect.center,
      maxWidth: readoutRect.width - side * 0.035,
      style: TextStyle(
        color: AppColors.darkText,
        fontSize: (side * 0.057).clamp(12.0, 20.0).toDouble(),
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }

  void _drawNeedle(
    Canvas canvas,
    Offset center,
    double side,
    double normalizedValue,
    Color activeColor,
  ) {
    final angle = startAngle + sweepAngle * normalizedValue;
    final direction = Offset(math.cos(angle), math.sin(angle));
    final perpendicular = Offset(-direction.dy, direction.dx);
    final needleLength = side * 0.285;
    final tailLength = side * 0.065;
    final halfWidth = math.max(3.0, side * 0.012);
    final tip = center + direction * needleLength;
    final tail = center - direction * tailLength;

    final needlePath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tail.dx + perpendicular.dx * halfWidth,
        tail.dy + perpendicular.dy * halfWidth,
      )
      ..lineTo(center.dx, center.dy)
      ..lineTo(
        tail.dx - perpendicular.dx * halfWidth,
        tail.dy - perpendicular.dy * halfWidth,
      )
      ..close();

    canvas.drawPath(
      needlePath.shift(Offset(side * 0.006, side * 0.008)),
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.01),
    );
    canvas.drawPath(
      needlePath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(Colors.white.withAlpha(40), needleColor),
            needleColor,
            activeColor.withAlpha(230),
          ],
        ).createShader(needlePath.getBounds()),
    );
    canvas.drawLine(
      center + direction * side * 0.03,
      tip - direction * side * 0.025,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, side * 0.004)
        ..color = Colors.white.withAlpha(116),
    );
  }

  void _drawCenterHub(Canvas canvas, Offset center, double side) {
    final hubRadius = side * 0.058;
    final hubRect = Rect.fromCircle(center: center, radius: hubRadius);

    canvas.drawCircle(
      center + Offset(0, side * 0.008),
      hubRadius * 1.05,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, side * 0.012),
    );
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.36, -0.42),
          radius: 1.12,
          colors: [Color(0xFFE8EEF2), Color(0xFF8795A1), Color(0xFF27323A)],
          stops: [0.0, 0.48, 1.0],
        ).createShader(hubRect),
    );
    canvas.drawCircle(
      center,
      hubRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, side * 0.006)
        ..color = Colors.black.withAlpha(150),
    );
    canvas.drawCircle(
      center + Offset(-hubRadius * 0.22, -hubRadius * 0.25),
      hubRadius * 0.22,
      Paint()..color = Colors.white.withAlpha(92),
    );
  }

  void _drawGlassHighlight(Canvas canvas, Offset center, double faceRadius) {
    final facePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: faceRadius));
    final highlightRect = Rect.fromCenter(
      center: center + Offset(-faceRadius * 0.12, -faceRadius * 0.36),
      width: faceRadius * 1.34,
      height: faceRadius * 0.52,
    );

    canvas.save();
    canvas.clipPath(facePath);
    canvas.drawOval(
      highlightRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withAlpha(36), Colors.white.withAlpha(0)],
        ).createShader(highlightRect),
    );
    canvas.restore();
  }

  List<double> _majorTickValues() {
    final interval = _resolvedMajorInterval();
    final values = <double>[minValue];
    var next = minValue + interval;

    while (next < maxValue && values.length < 48) {
      values.add(next);
      next += interval;
    }

    if ((values.last - maxValue).abs() > 0.0001) {
      values.add(maxValue);
    }

    return values;
  }

  double _resolvedMajorInterval() {
    final requested = majorTickInterval;
    if (requested != null && requested.isFinite && requested > 0) {
      return requested;
    }

    final target = _range / 5.0;
    final exponent = math.pow(10, (math.log(target) / math.ln10).floor());
    final fraction = target / exponent;
    final niceFraction = fraction <= 1
        ? 1
        : fraction <= 2
        ? 2
        : fraction <= 5
        ? 5
        : 10;
    return (niceFraction * exponent).toDouble();
  }

  Color _activeColorFor(double rawValue) {
    final clampedValue = _clampDouble(rawValue, minValue, maxValue);
    for (final range in ranges) {
      final start = math.min(range.startValue, range.endValue);
      final end = math.max(range.startValue, range.endValue);
      if (clampedValue >= start && clampedValue <= end) {
        return range.color;
      }
    }
    return accentColor;
  }

  double _normalizedFor(double rawValue) {
    return _clampDouble((rawValue - minValue) / _range, 0, 1);
  }

  Offset _pointAt(Offset center, double angle, double radius) {
    return center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }

  void _paintText(
    Canvas canvas, {
    required String text,
    required Offset center,
    required double maxWidth,
    required TextStyle style,
  }) {
    if (text.trim().isEmpty || maxWidth <= 0) return;

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: maxWidth);

    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _IndustrialRadialGaugePainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.minValue != minValue ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.displayValue != displayValue ||
        oldDelegate.label != label ||
        oldDelegate.unit != unit ||
        oldDelegate.majorTickInterval != majorTickInterval ||
        oldDelegate.minorTicksPerMajor != minorTicksPerMajor ||
        oldDelegate.ranges != ranges ||
        oldDelegate.showScaleLabels != showScaleLabels ||
        oldDelegate.showDigitalValue != showDigitalValue ||
        oldDelegate.showActiveGlow != showActiveGlow ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.sweepAngle != sweepAngle ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.needleColor != needleColor ||
        oldDelegate.panelColor != panelColor ||
        oldDelegate.faceColor != faceColor ||
        oldDelegate.scaleLabelFormatter != scaleLabelFormatter;
  }
}

double _resolveSide(BoxConstraints constraints, double? requestedSize) {
  final boundedWidth = constraints.maxWidth.isFinite;
  final boundedHeight = constraints.maxHeight.isFinite;
  final maxWidth = boundedWidth ? constraints.maxWidth : double.infinity;
  final maxHeight = boundedHeight ? constraints.maxHeight : double.infinity;

  if (requestedSize != null && requestedSize.isFinite && requestedSize > 0) {
    return math.min(requestedSize, math.min(maxWidth, maxHeight));
  }

  if (boundedWidth && boundedHeight) {
    return math.max(1.0, math.min(maxWidth, maxHeight));
  }
  if (boundedWidth) return math.max(1.0, maxWidth);
  if (boundedHeight) return math.max(1.0, maxHeight);
  return _kDefaultGaugeSide;
}

double _safeMaxValue(double minValue, double rawMaxValue) {
  final maxValue = _finiteOr(rawMaxValue, minValue + 100);
  return maxValue > minValue ? maxValue : minValue + 1;
}

double _safeSweepAngle(double rawSweepAngle) {
  final sweep = _finiteOr(rawSweepAngle, _kDefaultSweepAngle).abs();
  return _clampDouble(sweep, math.pi / 6, math.pi * 2);
}

double _finiteOr(double value, double fallback) {
  return value.isFinite ? value : fallback;
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

String _formatValue(double value, String Function(double value)? formatter) {
  if (formatter != null) return formatter(value);
  if ((value - value.roundToDouble()).abs() < 0.0001) {
    return value.toStringAsFixed(0);
  }

  final decimals = value.abs() >= 100 ? 1 : 2;
  return value
      .toStringAsFixed(decimals)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
