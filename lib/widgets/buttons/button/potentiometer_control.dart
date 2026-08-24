import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

const double _kStartAngle = math.pi * 0.75;
const double _kSweepAngle = math.pi * 1.5;

// Mechanical "give" on release/settle — slightly underdamped so the knob
// eases in with a hint of physical momentum instead of snapping flat.
const SpringDescription _kKnobSpring = SpringDescription(
  mass: 0.5,
  stiffness: 280.0,
  damping: 20.0,
);

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
    extends State<IndustrialPotentiometerControl>
    with TickerProviderStateMixin {
  late double _value;

  /// Rendered pointer/arc position in [0, 1]. Tracks [_value] 1:1 while the
  /// user is actively dragging (so the knob stays exactly under the finger —
  /// "stable value tracking"), but is eased toward its target by
  /// [_settleCtrl] whenever the value changes any other way (spring-return,
  /// nudge, external config change), giving the knob a damped, weighted
  /// feel without touching the drag-to-value math itself.
  late double _displayNormalized;

  double? _dragStartAngle;
  double? _dragLastAngle;
  double _dragAccumulatedAngle = 0.0;
  double? _dragStartValue;
  bool _isDragging = false;

  late final AnimationController _settleCtrl;
  bool _settleDrivesValue = false;
  double? _settleHapticTarget;
  bool _settleHapticFired = false;

  /// Smoothly animates the "pressed" look (knob depth, glow, shadow) in and
  /// out instead of switching it abruptly on drag start/end.
  late final AnimationController _pressCtrl;

  PotentiometerConfig get _config => widget.config.normalized();

  @override
  void initState() {
    super.initState();
    _value = _config.defaultValue;
    _displayNormalized = _config.normalizedValueFor(_value);
    _settleCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(_onSettleTick);
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _settleCtrl.dispose();
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IndustrialPotentiometerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _settleCtrl.stop();
      _value = _config.clampAndSnap(_value);
      _displayNormalized = _config.normalizedValueFor(_value);
    }
    if (!widget.enabled && oldWidget.enabled) {
      _settleCtrl.stop();
      _pressCtrl.reverse();
      _resetDrag();
    }
  }

  void _setValue(double next, {bool haptic = false}) {
    final snapped = _config.clampAndSnap(next);
    if (snapped == _value) return;
    setState(() {
      _value = snapped;
      _displayNormalized = _config.normalizedValueFor(snapped);
    });
    if (haptic) HapticFeedback.selectionClick();
    widget.onChanged(snapped);
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (!widget.enabled) return;
    if (!_isGripHit(details.localPosition, size)) {
      _resetDrag();
      return;
    }

    _settleCtrl.stop();
    final angle = _angleForPosition(details.localPosition, size);
    setState(() {
      _isDragging = true;
      _dragStartAngle = angle;
      _dragLastAngle = angle;
      _dragAccumulatedAngle = 0.0;
      _dragStartValue = _value;
    });
    _pressCtrl.forward();
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
    _pressCtrl.reverse();
    if (wasDragging) {
      HapticFeedback.lightImpact();
      if (_config.springReturnEnabled) _springReturnToNeutral();
    }
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

  /// Springs the knob back to [PotentiometerConfig.neutralValue] on release
  /// — only armed when the operator has opted into spring-return mode.
  /// Continuously reports the intermediate value via [widget.onChanged] as
  /// it travels, exactly like a physical spring-loaded pot would.
  void _springReturnToNeutral() {
    final target = _config.normalizedValueFor(_config.neutralValue);
    _settleDrivesValue = true;
    _settleHapticTarget = target;
    _settleHapticFired = false;
    if ((_displayNormalized - target).abs() < 0.0015) return;
    _settleCtrl.animateWith(
      SpringSimulation(_kKnobSpring, _displayNormalized, target, 0.0),
    );
  }

  /// Purely cosmetic damped ease of the pointer toward [target] — used for
  /// keyboard nudges, where the value has already landed instantly and only
  /// the needle should settle into place.
  void _animateDisplayTo(double target) {
    _settleDrivesValue = false;
    _settleHapticTarget = null;
    if ((_displayNormalized - target).abs() < 0.0015) {
      setState(() => _displayNormalized = target);
      return;
    }
    _settleCtrl.animateWith(
      SpringSimulation(_kKnobSpring, _displayNormalized, target, 0.0),
    );
  }

  void _onSettleTick() {
    if (_isDragging) return;
    final clamped = _settleCtrl.value.clamp(0.0, 1.0).toDouble();

    if (_settleDrivesValue) {
      final value = _config.valueForNormalized(clamped);
      final changed = value != _value;
      setState(() {
        _displayNormalized = clamped;
        _value = value;
      });
      if (changed) widget.onChanged(value);

      final target = _settleHapticTarget;
      if (target != null &&
          !_settleHapticFired &&
          (clamped - target).abs() < 0.01) {
        _settleHapticFired = true;
        HapticFeedback.lightImpact();
      }
    } else {
      setState(() => _displayNormalized = clamped);
    }
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
    final target = _config.clampAndSnap(_value + _config.stepSize * direction);
    if (target == _value) return;
    setState(() => _value = target);
    HapticFeedback.selectionClick();
    widget.onChanged(target);
    _animateDisplayTo(_config.normalizedValueFor(target));
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final normalized = _displayNormalized.clamp(0.0, 1.0).toDouble();
    final valueText = config.formatValue(_value);
    final trimmedLabel = widget.label.trim();

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

            // A label/icon footer is only worth reserving space for when
            // there's genuinely room for BOTH it and the dial's 72px
            // usability floor (see `side` below) — otherwise it would either
            // overflow the cell or force the dial smaller than that floor,
            // so it simply doesn't render instead, exactly like
            // ControlButtonLabelIcon already does at the label-text level.
            const footerHeight = 6.0 + ControlButtonVisualMetrics.rowHeight;
            final wantsFooter = trimmedLabel.isNotEmpty || widget.icon != null;
            final showFooter = wantsFooter && maxH >= 72.0 + footerHeight;
            final dialHeight = showFooter ? maxH - footerHeight : maxH;
            final side = math.max(72.0, math.min(maxW, dialHeight));

            final dial = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled
                  ? (details) =>
                        _handlePanStart(details, Size(maxW, dialHeight))
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) =>
                        _handlePanUpdate(details, Size(maxW, dialHeight))
                  : null,
              onPanEnd: widget.enabled ? (_) => _handlePanEnd() : null,
              onPanCancel: widget.enabled ? _handlePanEnd : null,
              child: SizedBox(
                width: maxW,
                height: dialHeight,
                child: Center(
                  child: SizedBox(
                    width: side,
                    height: side,
                    child: CustomPaint(
                      painter: _PotentiometerPainter(
                        normalizedValue: normalized,
                        neutralNormalized: config.springReturnEnabled
                            ? config.normalizedValueFor(config.neutralValue)
                            : null,
                        valueText: valueText,
                        minLabel: config.formatValue(config.minValue),
                        maxLabel: config.formatValue(config.maxValue),
                        showValue: config.showValue,
                        enabled: widget.enabled,
                        activeColor: widget.activeColor,
                        activeColorLight: widget.activeColorLight,
                        isDragging: _isDragging,
                        pressAmount: _pressCtrl.value,
                      ),
                    ),
                  ),
                ),
              ),
            );

            if (!showFooter) return dial;

            return SizedBox(
              width: maxW,
              height: maxH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  dial,
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: SizedBox(
                      height: ControlButtonVisualMetrics.rowHeight,
                      child: ControlButtonLabelIcon(
                        label: widget.label,
                        icon: widget.icon,
                        color: widget.enabled
                            ? AppColors.darkText
                            : AppColors.darkBorder,
                        iconColor: widget.activeColorLight,
                      ),
                    ),
                  ),
                ],
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
    required this.neutralNormalized,
    required this.valueText,
    required this.minLabel,
    required this.maxLabel,
    required this.showValue,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.isDragging,
    required this.pressAmount,
  });

  final double normalizedValue;
  final double? neutralNormalized;
  final String valueText;
  final String minLabel;
  final String maxLabel;
  final bool showValue;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final bool isDragging;

  /// 0..1 eased "pressed" amount driving the depth/glow/shadow changes while
  /// the knob is being turned.
  final double pressAmount;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.48;
    final bezelR = side * 0.43;
    final baseKnobR = side * 0.33;
    // Subtle "pressed into the panel" effect while actively turning.
    final knobR = baseKnobR * (1.0 - 0.035 * pressAmount);

    _drawHousingShadow(canvas, center, side, outerR);
    _drawHousing(canvas, center, outerR);
    _drawKnurl(canvas, center, outerR);
    _drawTicks(canvas, center, side, outerR);
    _drawArc(canvas, center, bezelR);
    _drawKnobShadow(canvas, center, side, knobR);
    _drawKnobBody(canvas, center, knobR);
    _drawPointer(canvas, center, knobR);
    _drawCenterCap(canvas, center, knobR);

    if (pressAmount > 0.01 && enabled) {
      canvas.drawCircle(
        center,
        outerR - 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, side * 0.016)
          ..color = activeColorLight.withAlpha((120 * pressAmount).round()),
      );
    }

    if (showValue) _paintValueAndRange(canvas, center, side);
  }

  void _drawHousingShadow(
    Canvas canvas,
    Offset center,
    double side,
    double outerR,
  ) {
    canvas.drawCircle(
      center + Offset(0, side * (0.035 - 0.012 * pressAmount)),
      outerR,
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 - 3 * pressAmount),
    );
  }

  void _drawHousing(Canvas canvas, Offset center, double outerR) {
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
        ..strokeWidth = math.max(1.0, outerR * 0.025)
        ..color = Colors.white.withAlpha(enabled ? 34 : 16),
    );
  }

  /// Fine machined-edge knurling on the housing rim, just outside the value
  /// scale — purely decorative texture that sells the "metal" read.
  void _drawKnurl(Canvas canvas, Offset center, double outerR) {
    const count = 72;
    final startR = outerR * 0.965;
    final endR = outerR * 0.99;
    final paint = Paint()
      ..strokeWidth = 1.0
      ..color = Colors.white.withAlpha(enabled ? 20 : 8);
    for (var i = 0; i < count; i++) {
      final angle = (math.pi * 2 / count) * i;
      canvas.drawLine(
        center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),
        center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),
        paint,
      );
    }
  }

  void _drawTicks(Canvas canvas, Offset center, double side, double radius) {
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 10; i++) {
      final t = i / 10.0;
      final angle = _kStartAngle + _kSweepAngle * t;
      final isEndpoint = i == 0 || i == 10;
      final isMajor = isEndpoint || i == 5;
      final startR = radius * (isMajor ? 0.80 : 0.86);
      final endR = radius * (isEndpoint ? 0.945 : 0.93);

      tickPaint.strokeWidth = math.max(
        1.0,
        side * (isEndpoint ? 0.016 : (isMajor ? 0.013 : 0.010)),
      );
      tickPaint.color = isEndpoint
          ? (enabled ? activeColorLight : AppColors.disabled).withAlpha(210)
          : Colors.white.withAlpha(enabled ? (isMajor ? 132 : 68) : 34);
      canvas.drawLine(
        center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),
        center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),
        tickPaint,
      );
    }

    final neutral = neutralNormalized;
    if (neutral != null) {
      final angle = _kStartAngle + _kSweepAngle * neutral.clamp(0.0, 1.0);
      final startR = radius * 0.78;
      final endR = radius * 0.95;
      canvas.drawLine(
        center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),
        center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(1.2, side * 0.014)
          ..color = activeColorLight.withAlpha(enabled ? 200 : 90),
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
        ..strokeWidth = radius * (0.075 + 0.012 * pressAmount)
        ..color = enabled
            ? Color.lerp(activeColor, activeColorLight, pressAmount * 0.5)!
            : AppColors.disabled.withAlpha(110),
    );
  }

  void _drawKnobShadow(
    Canvas canvas,
    Offset center,
    double side,
    double knobR,
  ) {
    canvas.drawCircle(
      center + Offset(0, side * (0.028 - 0.014 * pressAmount)),
      knobR,
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 - 2.5 * pressAmount),
    );
  }

  void _drawKnobBody(Canvas canvas, Offset center, double knobR) {
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
        ..strokeWidth = math.max(1.0, knobR * 0.055)
        ..color = Colors.black.withAlpha(125),
    );
    // Thin bright rim catch-light — reads as a machined bevel edge.
    canvas.drawCircle(
      center,
      knobR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withAlpha(enabled ? 46 : 18),
    );
  }

  void _drawPointer(Canvas canvas, Offset center, double knobR) {
    final angle = _kStartAngle + _kSweepAngle * normalizedValue;
    final dir = Offset(math.cos(angle), math.sin(angle));
    final perp = Offset(-dir.dy, dir.dx);

    final tip = center + dir * knobR * 0.82;
    final baseCenter = center + dir * knobR * 0.16;
    final baseHalfWidth = knobR * 0.075;
    final baseLeft = baseCenter + perp * baseHalfWidth;
    final baseRight = baseCenter - perp * baseHalfWidth;

    final needleColor = enabled ? activeColorLight : AppColors.disabled;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(baseLeft.dx, baseLeft.dy)
      ..lineTo(baseRight.dx, baseRight.dy)
      ..close();

    if (isDragging && enabled) {
      canvas.drawPath(
        path,
        Paint()
          ..color = needleColor.withAlpha(140)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = needleColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.black.withAlpha(90),
    );

    canvas.drawCircle(
      tip,
      math.max(1.2, knobR * 0.045),
      Paint()..color = needleColor.withAlpha(enabled ? 255 : 160),
    );
  }

  void _drawCenterCap(Canvas canvas, Offset center, double knobR) {
    final capR = knobR * 0.4;
    canvas.drawCircle(
      center,
      capR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          colors: [
            Colors.white.withAlpha(
              enabled ? (104 + (60 * pressAmount).round()) : 46,
            ),
            Colors.black.withAlpha(42),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: capR)),
    );
    canvas.drawCircle(
      center,
      capR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.black.withAlpha(80),
    );
  }

  void _paintValueAndRange(Canvas canvas, Offset center, double side) {
    final valueStyle = TextStyle(
      color: enabled ? AppColors.darkBg : AppColors.darkBorder,
      fontSize: (side * 0.095).clamp(10.0, 18.0).toDouble(),
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );
    final valueTP = TextPainter(
      text: TextSpan(text: valueText, style: valueStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: side * 0.46);
    final valueTop = center.dy - side * 0.12;
    valueTP.paint(canvas, Offset(center.dx - valueTP.width / 2, valueTop));

    // Compact min–max range caption, only drawn when it provably fits in
    // the gap between the value readout and the label/icon footer row —
    // keeps this correct at any widget size instead of guessing offsets.
    // final rangeText = '$minLabel  ↔  $maxLabel';
    // final rangeTP = TextPainter(
    //   text: TextSpan(
    //     text: rangeText,
    //     style: TextStyle(
    //       color: (enabled ? AppColors.darkBg : AppColors.darkBorder).withAlpha(
    //         150,
    //       ),
    //       fontSize: (side * 0.05).clamp(7.0, 10.0).toDouble(),
    //       fontWeight: FontWeight.w700,
    //       letterSpacing: 0.2,
    //     ),
    //   ),
    //   textAlign: TextAlign.center,
    //   textDirection: TextDirection.ltr,
    //   maxLines: 1,
    //   ellipsis: '…',
    // )..layout(maxWidth: side * 0.5);

    // final rangeTop = valueTop + valueTP.height + side * 0.02;
    //   final footerTop =
    //       center.dy + side * 0.23 - ControlButtonVisualMetrics.rowHeight / 2;
    //   if (rangeTop + rangeTP.height + side * 0.02 <= footerTop) {
    //     rangeTP.paint(canvas, Offset(center.dx - rangeTP.width / 2, rangeTop));
    //   }
    //
  }

  @override
  bool shouldRepaint(covariant _PotentiometerPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.neutralNormalized != neutralNormalized ||
        oldDelegate.valueText != valueText ||
        oldDelegate.minLabel != minLabel ||
        oldDelegate.maxLabel != maxLabel ||
        oldDelegate.showValue != showValue ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.pressAmount != pressAmount;
  }
}
