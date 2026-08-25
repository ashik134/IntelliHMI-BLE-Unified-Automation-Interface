import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter/physics.dart';

import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

import 'package:rev_crane_control_ops/models/potentiometer_config.dart';

import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

const double _kStartAngle = math.pi * 0.75;

const double _kSweepAngle = math.pi * 1.5;

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

           painter: _GaugePotentiometerPainter(

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

            label: trimmedLabel,

            icon: widget.icon,

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

class _GaugePotentiometerPainter extends CustomPainter {

 const _GaugePotentiometerPainter({

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

  required this.label,

  required this.icon,

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

 final double pressAmount;

 final String label;

 final IconData? icon;

 @override

 void paint(Canvas canvas, Size size) {

  final side = math.min(size.width, size.height);

  final center = Offset(size.width / 2, size.height / 2);

  final outerR = side * 0.48;

  final bezelR = side * 0.43;

  final baseKnobR = side * 0.30;

  final knobR = baseKnobR * (1.0 - 0.035 * pressAmount);

  _drawGaugeBackground(canvas, center, side, outerR);

  _drawFaceTexture(canvas, center, side, outerR);

  _drawGaugeBezel(canvas, center, outerR);

  _drawTickMarks(canvas, center, side, outerR);

  _drawArcTrack(canvas, center, bezelR);

  _drawGaugeLabels(canvas, center, side);

  _drawKnobShadow(canvas, center, side, knobR);

  _drawKnobBody(canvas, center, knobR);

  _drawKnurling(canvas, center, knobR);

  _drawPointer(canvas, center, knobR);

  _drawCenterCap(canvas, center, knobR);

  _drawValueDisplay(canvas, center, side);

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

 }

 void _drawGaugeBackground(

  Canvas canvas,

  Offset center,

  double side,

  double outerR,

 ) {

//  Outer shadow

  canvas.drawCircle(

   center + Offset(0, side * 0.035),

   outerR,

   Paint()

    ..color = Colors.black.withAlpha(180)

    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 16),

  );

//  Main gauge face - dark brushed metal look

  final rect = Rect.fromCircle(center: center, radius: outerR);

  canvas.drawCircle(

   center,

   outerR,

   Paint()

    ..shader = const RadialGradient(

     center: Alignment(-0.3, -0.4),

     radius: 1.3,

     colors: [

      Color(0xFF2C3E50),

      Color(0xFF1A2634),

      Color(0xFF0D1520),

     ],

     stops: [0.0, 0.5, 1.0],

    ).createShader(rect),

  );

//  Subtle inner glow ring

  canvas.drawCircle(

   center,

   outerR * 0.92,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = 1.5

    ..color = Colors.white.withAlpha(enabled ? 20 : 10),

  );

 }

 void _drawFaceTexture(
  Canvas canvas,
  Offset center,
  double side,
  double outerR,
 ) {
  // Concentric machining marks are kept faint so labels remain readable.
  final grain = Paint()
   ..style = PaintingStyle.stroke
   ..strokeWidth = math.max(0.35, side * 0.0022)
   ..color = Colors.white.withAlpha(enabled ? 8 : 4);
  for (var i = 0; i < 12; i++) {
   canvas.drawCircle(center, outerR * (0.35 + i * 0.045), grain);
  }

  // Split lighting makes the face read as a recessed physical cavity.
  final faceRect = Rect.fromCircle(center: center, radius: outerR * 0.91);
  canvas.drawArc(
   faceRect,
   math.pi * 1.08,
   math.pi * 0.78,
   false,
   Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, side * 0.009)
    ..color = Colors.white.withAlpha(enabled ? 22 : 10),
  );
  canvas.drawArc(
   faceRect,
   math.pi * 0.08,
   math.pi * 0.78,
   false,
   Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.0, side * 0.012)
    ..color = Colors.black.withAlpha(115),
  );
 }

 void _drawGaugeBezel(Canvas canvas, Offset center, double outerR) {

//  Chrome bezel ring

  final bezelPaint = Paint()

   ..style = PaintingStyle.stroke

   ..strokeWidth = outerR * 0.08;

  final bezelRect = Rect.fromCircle(center: center, radius: outerR * 0.96);

  canvas.drawArc(

   bezelRect,

   0,

   math.pi * 2,

   false,

   bezelPaint

    ..shader = const SweepGradient(

     colors: [

      Color(0xFF4A5A6A),

      Color(0xFF8A9AAA),

      Color(0xFF2A3A4A),

      Color(0xFF6A7A8A),

      Color(0xFF4A5A6A),

     ],

     stops: [0.0, 0.25, 0.5, 0.75, 1.0],

    ).createShader(bezelRect),

  );

//  Inner bezel highlight

  canvas.drawCircle(

   center,

   outerR * 0.92,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = 1.0

    ..color = Colors.white.withAlpha(enabled ? 30 : 15),

  );

 }

 void _drawTickMarks(

  Canvas canvas,

  Offset center,

  double side,

  double outerR,

 ) {

  final tickPaint = Paint()..strokeCap = StrokeCap.round;

//  Major ticks (every 10 units)

  for (var i = 0; i <= 10; i++) {

   final t = i / 10.0;

   final angle = _kStartAngle + _kSweepAngle * t;

   final isEndpoint = i == 0 || i == 10;

   final isCenter = i == 5;

   final isMajor = isEndpoint || isCenter;

   final startR = outerR * (isMajor ? 0.72 : 0.78);

   final endR = outerR * (isEndpoint ? 0.94 : 0.90);

   tickPaint.strokeWidth = math.max(

    1.5,

    side * (isEndpoint ? 0.018 : (isMajor ? 0.014 : 0.010)),

   );

   tickPaint.color = isEndpoint

     ? (enabled ? activeColorLight : AppColors.disabled).withAlpha(220)

     : Colors.white.withAlpha(enabled ? (isMajor ? 160 : 80) : 40);

   canvas.drawLine(

    center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),

    center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),

    tickPaint,

   );

  }

//  Minor ticks (every 5 units)

  for (var i = 0; i <= 20; i++) {

   if (i % 2 == 0) continue;

   final t = i / 20.0;

   final angle = _kStartAngle + _kSweepAngle * t;

   final startR = outerR * 0.80;

   final endR = outerR * 0.87;

   tickPaint.strokeWidth = math.max(0.8, side * 0.007);

   tickPaint.color = Colors.white.withAlpha(enabled ? 50 : 25);

   canvas.drawLine(

    center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),

    center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),

    tickPaint,

   );

  }

//  Neutral position marker

  final neutral = neutralNormalized;

  if (neutral != null) {

   final angle = _kStartAngle + _kSweepAngle * neutral.clamp(0.0, 1.0);

   final startR = outerR * 0.68;

   final endR = outerR * 0.94;

   canvas.drawLine(

    center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),

    center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),

    Paint()

     ..strokeCap = StrokeCap.round

     ..strokeWidth = math.max(2.0, side * 0.016)

     ..color = activeColorLight.withAlpha(enabled ? 180 : 80),

   );

  }

 }

 void _drawArcTrack(Canvas canvas, Offset center, double radius) {

//  Background track

  final rect = Rect.fromCircle(center: center, radius: radius);

  canvas.drawArc(

   rect,

   _kStartAngle,

   _kSweepAngle,

   false,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeCap = StrokeCap.round

    ..strokeWidth = radius * 0.08

    ..color = const Color(0xFF1A2634).withAlpha(200),

  );

//  Glowing track background

  canvas.drawArc(

   rect,

   _kStartAngle,

   _kSweepAngle * 0.05,

   false,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeCap = StrokeCap.round

    ..strokeWidth = radius * 0.09

    ..color = activeColorLight.withAlpha(20),

  );

//  Active arc with gradient

  final activePaint = Paint()

   ..style = PaintingStyle.stroke

   ..strokeCap = StrokeCap.round

   ..strokeWidth = radius * (0.085 + 0.01 * pressAmount);

  if (enabled && normalizedValue > 0.001) {

//  Create a gradient along the arc

   final shader = SweepGradient(

    startAngle: _kStartAngle,

    endAngle: _kStartAngle + _kSweepAngle * normalizedValue,

    colors: [

     activeColor.withAlpha(180),

     activeColorLight,

     activeColorLight.withAlpha(200),

    ],

    stops: const [0.0, 0.6, 1.0],

   ).createShader(rect);

   canvas.drawArc(

    rect,

    _kStartAngle,

    _kSweepAngle * normalizedValue,

    false,

    activePaint..shader = shader,

   );

  } else if (!enabled) {

   canvas.drawArc(

    rect,

    _kStartAngle,

    _kSweepAngle * normalizedValue,

    false,

    activePaint..color = AppColors.disabled.withAlpha(80),

   );

  }

//  Glow effect on the active arc

  if (enabled && normalizedValue > 0.01) {

   canvas.drawArc(

    rect,

    _kStartAngle,

    _kSweepAngle * normalizedValue,

    false,

    Paint()

     ..style = PaintingStyle.stroke

     ..strokeCap = StrokeCap.round

     ..strokeWidth = radius * 0.15

     ..color = activeColorLight.withAlpha((15 + 10 * pressAmount).round())

     ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6),

   );

  }

 }

 void _drawGaugeLabels(Canvas canvas, Offset center, double side) {

  final labelStyle = TextStyle(

   color: Colors.white.withAlpha(enabled ? 140 : 70),

   fontSize: (side * 0.055).clamp(8.0, 12.0).toDouble(),

   fontWeight: FontWeight.w600,

   letterSpacing: 0.5,

  );

//  Min label

  final minTP = TextPainter(

   text: TextSpan(text: minLabel, style: labelStyle),

   textDirection: TextDirection.ltr,

  )..layout();

  final minAngle = _kStartAngle;

  final minPos = center +

    Offset(

     math.cos(minAngle) * side * 0.38,

     math.sin(minAngle) * side * 0.38,

    );

  minTP.paint(

   canvas,

   Offset(minPos.dx - minTP.width / 2, minPos.dy - minTP.height / 2),

  );

//  Max label

  final maxTP = TextPainter(

   text: TextSpan(text: maxLabel, style: labelStyle),

   textDirection: TextDirection.ltr,

  )..layout();

  final maxAngle = _kStartAngle + _kSweepAngle;

  final maxPos = center +

    Offset(

     math.cos(maxAngle) * side * 0.38,

     math.sin(maxAngle) * side * 0.38,

    );

  maxTP.paint(

   canvas,

   Offset(maxPos.dx - maxTP.width / 2, maxPos.dy - maxTP.height / 2),

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

    ..color = Colors.black.withAlpha(180)

    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 - 3 * pressAmount),

  );

 }

 void _drawKnobBody(Canvas canvas, Offset center, double knobR) {

//  Main knob body - brushed aluminum look

  final knobRect = Rect.fromCircle(center: center, radius: knobR);

  canvas.drawCircle(

   center,

   knobR,

   Paint()

    ..shader = const RadialGradient(

     center: Alignment(-0.35, -0.45),

     radius: 1.2,

     colors: [

      Color(0xFFD0D8E0),

      Color(0xFF8090A0),

      Color(0xFF304050),

      Color(0xFF1A2838),

     ],

     stops: [0.0, 0.35, 0.7, 1.0],

    ).createShader(knobRect),

  );

//  Knob edge bevel

  canvas.drawCircle(

   center,

   knobR,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = math.max(2.0, knobR * 0.07)

    ..color = Colors.black.withAlpha(150),

  );

//  Bright edge highlight

  canvas.drawCircle(

   center,

   knobR - 1.5,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = 1.5

    ..color = Colors.white.withAlpha(enabled ? 50 : 20),

  );

//  Knob grip texture - subtle concentric rings

  for (var i = 0; i < 3; i++) {

   final ringR = knobR * (0.55 + i * 0.12);

   canvas.drawCircle(

    center,

    ringR,

    Paint()

     ..style = PaintingStyle.stroke

     ..strokeWidth = 0.5

     ..color = Colors.white.withAlpha(15),

   );

  }

//  Knob grip dots

  for (var i = 0; i < 12; i++) {

   final angle = (math.pi * 2 / 12) * i;

   final dotR = knobR * 0.7;

   canvas.drawCircle(

    center +

      Offset(

       math.cos(angle) * dotR,

       math.sin(angle) * dotR,

      ),

    knobR * 0.025,

    Paint()..color = Colors.white.withAlpha(20),

   );

  }

 }

 void _drawKnurling(Canvas canvas, Offset center, double knobR) {
  final dark = Paint()
   ..strokeCap = StrokeCap.round
   ..strokeWidth = math.max(0.65, knobR * 0.018)
   ..color = Colors.black.withAlpha(115);
  final light = Paint()
   ..strokeCap = StrokeCap.round
   ..strokeWidth = math.max(0.65, knobR * 0.018)
   ..color = Colors.white.withAlpha(enabled ? 70 : 28);

  for (var i = 0; i < 40; i++) {
   final angle = math.pi * 2 * i / 40;
   final direction = Offset(math.cos(angle), math.sin(angle));
   final start = center + direction * knobR * 0.84;
   final end = center + direction * knobR * 0.97;
   canvas.drawLine(start, end, dark);
   canvas.drawLine(
    start + const Offset(-0.35, -0.35),
    end + const Offset(-0.35, -0.35),
    light,
   );
  }

  // Fine brushing on the aluminium top surface.
  final brush = Paint()
   ..style = PaintingStyle.stroke
   ..strokeWidth = math.max(0.25, knobR * 0.008)
   ..color = Colors.white.withAlpha(enabled ? 20 : 8);
  for (var i = 0; i < 8; i++) {
   canvas.drawCircle(center, knobR * (0.25 + i * 0.068), brush);
  }
 }

 void _drawPointer(Canvas canvas, Offset center, double knobR) {

  final angle = _kStartAngle + _kSweepAngle * normalizedValue;

  final dir = Offset(math.cos(angle), math.sin(angle));

  final perp = Offset(-dir.dy, dir.dx);

  final tip = center + dir * knobR * 0.82;

  final baseCenter = center + dir * knobR * 0.15;

  final baseHalfWidth = knobR * 0.065;

  final baseLeft = baseCenter + perp * baseHalfWidth;

  final baseRight = baseCenter - perp * baseHalfWidth;

  final needleColor = enabled ? activeColorLight : AppColors.disabled;

//  Pointer shadow

  canvas.drawPath(

   Path()

    ..moveTo(tip.dx + 2, tip.dy + 2)

    ..lineTo(baseLeft.dx + 1, baseLeft.dy + 1)

    ..lineTo(baseRight.dx + 1, baseRight.dy + 1)

    ..close(),

   Paint()

    ..color = Colors.black.withAlpha(100)

    ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3),

  );

//  Pointer body

  final pointerPath = Path()

   ..moveTo(tip.dx, tip.dy)

   ..lineTo(baseLeft.dx, baseLeft.dy)

   ..lineTo(baseRight.dx, baseRight.dy)

   ..close();

  canvas.drawPath(

   pointerPath,

   Paint()

    ..color = needleColor

    ..style = PaintingStyle.fill,

  );

  canvas.drawPath(

   pointerPath,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = 1.0

    ..color = Colors.black.withAlpha(80),

  );

//  Pointer tip dot

  canvas.drawCircle(

   tip,

   math.max(1.5, knobR * 0.055),

   Paint()

    ..color = needleColor.withAlpha(enabled ? 255 : 160)

    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),

  );

 }

 void _drawCenterCap(Canvas canvas, Offset center, double knobR) {

  final capR = knobR * 0.32;

//  Center cap

  canvas.drawCircle(

   center,

   capR,

   Paint()

    ..shader = RadialGradient(

     center: const Alignment(-0.3, -0.4),

     colors: [

      Colors.white.withAlpha(enabled ? 120 : 60),

      Colors.black.withAlpha(80),

     ],

    ).createShader(Rect.fromCircle(center: center, radius: capR)),

  );

//  Cap edge

  canvas.drawCircle(

   center,

   capR,

   Paint()

    ..style = PaintingStyle.stroke

    ..strokeWidth = 1.0

    ..color = Colors.black.withAlpha(120),

  );

//  Small highlight dot

  canvas.drawCircle(

   center + Offset(-capR * 0.25, -capR * 0.3),

   capR * 0.15,

   Paint()..color = Colors.white.withAlpha(enabled ? 80 : 30),

  );

 }

 void _drawValueDisplay(Canvas canvas, Offset center, double side) {

  if (!showValue) return;

  final valueStyle = TextStyle(

   color: enabled ? Colors.white : AppColors.darkBorder,

   fontSize: (side * 0.11).clamp(14.0, 22.0).toDouble(),

   fontWeight: FontWeight.w800,

   letterSpacing: 0.5,

   shadows: [

    Shadow(

     color: Colors.black.withAlpha(150),

     blurRadius: 4,

     offset: const Offset(0, 1),

    ),

   ],

  );

  final valueTP = TextPainter(

   text: TextSpan(text: valueText, style: valueStyle),

   textAlign: TextAlign.center,

   textDirection: TextDirection.ltr,

   maxLines: 1,

   ellipsis: '...',

  )..layout(maxWidth: side * 0.5);

  final valueY = center.dy + side * 0.32;

  valueTP.paint(

   canvas,

   Offset(center.dx - valueTP.width / 2, valueY),

  );

  // Display the configured engineering range; never assume the unit is %.
  if (side >= 112) {
   final rangeTP = TextPainter(
    text: TextSpan(
     text: '$minLabel  ↔  $maxLabel',
     style: TextStyle(
      color: Colors.white.withAlpha(enabled ? 92 : 42),
      fontSize: (side * 0.043).clamp(7.0, 9.5).toDouble(),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.35,
     ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
    maxLines: 1,
   )..layout(maxWidth: side * 0.58);
   rangeTP.paint(
    canvas,
    Offset(
     center.dx - rangeTP.width / 2,
     valueY + valueTP.height - side * 0.005,
    ),
   );
  }

 }

 @override

 bool shouldRepaint(covariant _GaugePotentiometerPainter oldDelegate) {

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

    oldDelegate.pressAmount != pressAmount ||

    oldDelegate.label != label ||

    oldDelegate.icon != icon;

 }

}