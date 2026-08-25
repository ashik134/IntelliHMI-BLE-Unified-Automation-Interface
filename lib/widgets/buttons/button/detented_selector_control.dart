import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/detented_selector_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialDetentedSelectorControl
//
// A rotary selector switch with a fixed, operator-configured number of hard
// detent positions (see DetentedSelectorConfig) — mechanically distinct from
// IndustrialPotentiometerControl/IndustrialCenterOffPotentiometerControl
// (both continuous analog values): this control's committed state is always
// exactly one of N discrete positions, never a value in between. It never
// touches the analog-output pipeline at all; [onPositionSelected] reports
// the selected SelectorPosition.id, which the caller (DetentedSelectorStrategy)
// dispatches via onStateIdCommand exactly like the multi-zone slider does
// with its own raw zone id — this widget owns presentation, drag gesture
// handling, detent snapping, spring physics, and haptics only, and never
// decides what a position MEANS (entirely up to ButtonConfig.stateMappings).
//
// Drag math (angle-delta accumulation, not absolute-angle-to-value) mirrors
// IndustrialPotentiometerControl exactly — see its own doc comments — with
// the accumulated angle then quantized to the nearest detent index instead
// of a continuous value. The live pointer tracks the raw drag angle 1:1
// while dragging (real tactile "travel" between clicks, matching a physical
// detent switch's spring-loaded ball catch), but only ever RESTS exactly on
// a detent angle: every release/settle is a spring animation onto the
// current index's exact angle (see _settleToCurrentIndex), so the knob can
// never be left visually between two positions.
// ─────────────────────────────────────────────────────────────────────────────

const SpringDescription _kKnobSpring = SpringDescription(
  mass: 0.5,
  stiffness: 280.0,
  damping: 20.0,
);

class IndustrialDetentedSelectorControl extends StatefulWidget {
  const IndustrialDetentedSelectorControl({
    super.key,
    required this.config,
    required this.label,
    required this.activeColor,
    required this.activeColorLight,
    required this.enabled,
    required this.onPositionSelected,
    this.icon,
  });

  final DetentedSelectorConfig config;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool enabled;

  /// Fires with the newly-selected SelectorPosition.id whenever the
  /// committed detent changes (drag snap, spring-return, or keyboard nudge).
  final ValueChanged<String> onPositionSelected;

  @override
  State<IndustrialDetentedSelectorControl> createState() =>
      _IndustrialDetentedSelectorControlState();
}

class _IndustrialDetentedSelectorControlState
    extends State<IndustrialDetentedSelectorControl>
    with TickerProviderStateMixin {
  late int _index;

  /// Rendered pointer angle, radians — tracks the raw drag angle 1:1 while
  /// dragging (see file doc comment), spring-eased toward the current
  /// index's exact angle at every other transition.
  late double _displayAngle;

  double? _dragStartAngle;
  double? _dragLastAngle;
  double _dragAccumulatedAngle = 0.0;
  int? _dragStartIndex;
  bool _isDragging = false;

  late final AnimationController _settleCtrl;
  late final AnimationController _pressCtrl;

  DetentedSelectorConfig get _config => widget.config.normalized();
  int get _count => _config.positions.length;
  double get _startAngle => _config.startAngleDegrees * math.pi / 180.0;
  double get _sweepAngle => _config.sweepDegrees * math.pi / 180.0;
  double get _stepAngle => _count > 1 ? _sweepAngle / (_count - 1) : 0.0;

  double _angleForIndex(int i) => _startAngle + _stepAngle * i;

  @override
  void initState() {
    super.initState();
    _index = _config.initialPositionIndex.clamp(0, _count - 1);
    _displayAngle = _angleForIndex(_index);
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
  void didUpdateWidget(covariant IndustrialDetentedSelectorControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _settleCtrl.stop();
      final lastIndex = _count - 1;
      if (_index > lastIndex) _index = lastIndex;
      if (_index < 0) _index = 0;
      _displayAngle = _angleForIndex(_index);
    }
    if (!widget.enabled && oldWidget.enabled) {
      // A retained selector switch stays exactly where it is when disabled
      // (E-STOP/disconnect) — unlike a momentary lever/slider, there is no
      // "idle" position to fall back to, so only in-flight gesture state is
      // cancelled, never the committed index.
      _settleCtrl.stop();
      _pressCtrl.reverse();
      _resetDrag();
    }
  }

  void _resetDrag() {
    final needsRepaint =
        _isDragging ||
        _dragStartAngle != null ||
        _dragLastAngle != null ||
        _dragAccumulatedAngle != 0.0 ||
        _dragStartIndex != null;
    if (!needsRepaint) return;
    setState(() {
      _isDragging = false;
      _dragStartAngle = null;
      _dragLastAngle = null;
      _dragAccumulatedAngle = 0.0;
      _dragStartIndex = null;
    });
  }

  void _commitIndex(int newIndex) {
    if (newIndex == _index) return;
    setState(() => _index = newIndex);
    HapticFeedback.mediumImpact();
    widget.onPositionSelected(_config.positions[newIndex].id);
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
      _dragStartIndex = _index;
    });
    _pressCtrl.forward();
    HapticFeedback.selectionClick();
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (!widget.enabled || !_isDragging || _stepAngle <= 0) return;
    final angle = _angleForPosition(details.localPosition, size);
    if (angle == null) return;

    final lastAngle = _dragLastAngle ?? _dragStartAngle;
    if (lastAngle == null) {
      _dragStartAngle = angle;
      _dragLastAngle = angle;
      _dragAccumulatedAngle = 0.0;
      _dragStartIndex = _index;
      return;
    }

    _dragAccumulatedAngle += _signedAngleDelta(angle, lastAngle);
    _dragLastAngle = angle;

    final startIndex = _dragStartIndex ?? _index;
    // Hard end stops: a real selector switch physically can't rotate past
    // its first/last position, so the accumulated angle itself is clamped
    // into range rather than letting it run away and requiring an
    // equal-and-opposite rotation back before the knob responds again.
    final maxDelta = (_count - 1 - startIndex) * _stepAngle;
    final minDelta = (0 - startIndex) * _stepAngle;
    _dragAccumulatedAngle = _dragAccumulatedAngle.clamp(minDelta, maxDelta);

    setState(() {
      _displayAngle = _angleForIndex(startIndex) + _dragAccumulatedAngle;
    });

    final rawOffset = _dragAccumulatedAngle / _stepAngle;
    final targetIndex = (startIndex + rawOffset).round().clamp(0, _count - 1);
    _commitIndex(targetIndex);
  }

  void _handlePanEnd() {
    if (!widget.enabled) return;
    final wasDragging = _isDragging;
    _resetDrag();
    _pressCtrl.reverse();
    if (wasDragging) {
      HapticFeedback.lightImpact();
      if (_config.springReturnEnabled) {
        _commitIndex(_config.neutralPositionIndex.clamp(0, _count - 1));
      }
      _settleToCurrentIndex();
    }
  }

  void _settleToCurrentIndex() {
    final target = _angleForIndex(_index);
    if ((_displayAngle - target).abs() < 0.001) {
      setState(() => _displayAngle = target);
      return;
    }
    _settleCtrl.animateWith(
      SpringSimulation(_kKnobSpring, _displayAngle, target, 0.0),
    );
  }

  void _onSettleTick() {
    if (_isDragging) return;
    setState(() => _displayAngle = _settleCtrl.value);
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

    final indicatorEnd =
        center +
        Offset(
          math.cos(_displayAngle) * knobRadius * 0.82,
          math.sin(_displayAngle) * knobRadius * 0.82,
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
    final target = (_index + direction).clamp(0, _count - 1);
    if (target == _index) return;
    _commitIndex(target);
    _settleToCurrentIndex();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final positions = config.positions;
    final current = positions[_index];
    final currentLabel = (current.label?.trim().isNotEmpty ?? false)
        ? current.label!.trim()
        : current.id;
    final trimmedLabel = widget.label.trim();

    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: widget.label,
      value: currentLabel,
      increasedValue: _index < positions.length - 1
          ? positions[_index + 1].label ?? positions[_index + 1].id
          : currentLabel,
      decreasedValue: _index > 0
          ? positions[_index - 1].label ?? positions[_index - 1].id
          : currentLabel,
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
                  ? (details) => _handlePanStart(details, Size(side, side))
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => _handlePanUpdate(details, Size(side, side))
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
                      painter: _DetentedSelectorPainter(
                        positionCount: _count,
                        currentIndex: _index,
                        startAngle: _startAngle,
                        stepAngle: _stepAngle,
                        displayAngle: _displayAngle,
                        positionLabels: [
                          for (final p in positions) p.label?.trim() ?? '',
                        ],
                        currentLabel: currentLabel,
                        showReadout: config.showReadout,
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

class _DetentedSelectorPainter extends CustomPainter {
  const _DetentedSelectorPainter({
    required this.positionCount,
    required this.currentIndex,
    required this.startAngle,
    required this.stepAngle,
    required this.displayAngle,
    required this.positionLabels,
    required this.currentLabel,
    required this.showReadout,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.isDragging,
    required this.pressAmount,
  });

  final int positionCount;
  final int currentIndex;
  final double startAngle;
  final double stepAngle;
  final double displayAngle;
  final List<String> positionLabels;
  final String currentLabel;
  final bool showReadout;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final bool isDragging;
  final double pressAmount;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.48;
    final bezelR = side * 0.43;
    final baseKnobR = side * 0.33;
    final knobR = baseKnobR * (1.0 - 0.035 * pressAmount);

    _drawHousingShadow(canvas, center, side, outerR);
    _drawHousing(canvas, center, outerR);
    _drawKnurl(canvas, center, outerR);
    _drawPositionTicks(canvas, center, side, outerR);
    _drawArc(canvas, center, bezelR);
    _drawPositionCaptions(canvas, center, side, (bezelR + knobR) / 2);
    _drawKnobShadow(canvas, center, side, knobR);
    _drawKnobBody(canvas, center, knobR);
    _drawPointer(canvas, center, knobR);

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

    if (showReadout) _paintReadout(canvas, center, side);
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

  /// One tick per configured position — never a fixed 10-division scale like
  /// the continuous potentiometer's, since what matters here is exactly
  /// where each real detent sits. The current position's tick is drawn
  /// longer/brighter with an accent-colored glow so it reads as clearly
  /// selected at a glance (the brief's "highlight the currently selected
  /// position clearly").
  void _drawPositionTicks(
    Canvas canvas,
    Offset center,
    double side,
    double radius,
  ) {
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < positionCount; i++) {
      final angle = startAngle + stepAngle * i;
      final isCurrent = i == currentIndex;
      final startR = radius * (isCurrent ? 0.76 : 0.82);
      final endR = radius * (isCurrent ? 0.965 : 0.93);
      final dir = Offset(math.cos(angle), math.sin(angle));

      if (isCurrent && enabled) {
        canvas.drawLine(
          center + dir * startR,
          center + dir * endR,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(2.4, side * 0.026)
            ..color = activeColorLight.withAlpha(110)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
      }

      tickPaint.strokeWidth = math.max(
        1.0,
        side * (isCurrent ? 0.020 : 0.011),
      );
      tickPaint.color = isCurrent
          ? (enabled ? activeColorLight : AppColors.disabled).withAlpha(235)
          : Colors.white.withAlpha(enabled ? 120 : 40);
      canvas.drawLine(center + dir * startR, center + dir * endR, tickPaint);
    }
  }

  /// Background sweep plus a filled arc from the first position out to the
  /// current one, giving a "how far turned" read at a glance — matching
  /// IndustrialPotentiometerControl's own progress arc, but driven by
  /// discrete index rather than a continuous value.
  void _drawArc(Canvas canvas, Offset center, double radius) {
    if (positionCount < 2) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = stepAngle * (positionCount - 1);
    canvas.drawArc(
      rect,
      startAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = radius * 0.075
        ..color = AppColors.darkBg.withAlpha(205),
    );
    final fillSweep = stepAngle * currentIndex;
    if (fillSweep.abs() > 0.002) {
      canvas.drawArc(
        rect,
        startAngle,
        fillSweep,
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
  }

  /// Short per-position captions printed on the dial FACE, in the annular
  /// gap between the tick ring and the knob — like the printed position
  /// numbers on a real industrial selector switch's faceplate. Drawn inside
  /// the widget's own square footprint (rather than flanking it, like the
  /// center-off potentiometer's min/max labels) so this never depends on
  /// leftover grid-cell width and always fits at any grid size.
  void _drawPositionCaptions(
    Canvas canvas,
    Offset center,
    double side,
    double radius,
  ) {
    if (side < 96.0) return; // too small for legible per-position captions
    final fontSize = (side * 0.052).clamp(7.0, 11.0).toDouble();
    for (var i = 0; i < positionCount; i++) {
      final angle = startAngle + stepAngle * i;
      final isCurrent = i == currentIndex;
      final raw = positionLabels[i];
      final text = raw.isNotEmpty
          ? (raw.length > 3 ? raw.substring(0, 3).toUpperCase() : raw.toUpperCase())
          : '${i + 1}';
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: isCurrent
                ? (enabled ? activeColorLight : AppColors.disabled)
                : Colors.white.withAlpha(enabled ? 130 : 50),
            fontSize: fontSize,
            fontWeight: isCurrent ? FontWeight.w900 : FontWeight.w700,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: side * 0.3);
      final pos =
          center +
          Offset(math.cos(angle) * radius, math.sin(angle) * radius) -
          Offset(tp.width / 2, tp.height / 2);
      tp.paint(canvas, pos);
    }
  }

  void _drawKnobShadow(Canvas canvas, Offset center, double side, double knobR) {
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
    final dir = Offset(math.cos(displayAngle), math.sin(displayAngle));
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

    canvas.drawPath(path, Paint()..color = needleColor);
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

  /// Selected position's label plus a "DETENT i / N-1" caption, mirroring
  /// IndustrialCenterOffPotentiometerControl's inside-the-knob value text.
  void _paintReadout(Canvas canvas, Offset center, double side) {
    final labelStyle = TextStyle(
      color: enabled ? AppColors.darkBg : AppColors.darkBorder,
      fontSize: (side * 0.085).clamp(9.0, 15.0).toDouble(),
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    );
    final labelTP = TextPainter(
      text: TextSpan(text: currentLabel, style: labelStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: side * 0.5);

    final captionStyle = TextStyle(
      color: (enabled ? AppColors.darkBg : AppColors.darkBorder).withAlpha(170),
      fontSize: (side * 0.045).clamp(7.0, 10.0).toDouble(),
      fontWeight: FontWeight.w700,
      letterSpacing: 0.4,
    );
    final captionTP = TextPainter(
      text: TextSpan(
        text: 'DETENT $currentIndex / ${positionCount - 1}',
        style: captionStyle,
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: side * 0.55);

    final totalHeight = labelTP.height + 2 + captionTP.height;
    final top = center.dy - totalHeight / 2;
    labelTP.paint(canvas, Offset(center.dx - labelTP.width / 2, top));
    captionTP.paint(
      canvas,
      Offset(center.dx - captionTP.width / 2, top + labelTP.height + 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DetentedSelectorPainter oldDelegate) {
    return oldDelegate.positionCount != positionCount ||
        oldDelegate.currentIndex != currentIndex ||
        oldDelegate.startAngle != startAngle ||
        oldDelegate.stepAngle != stepAngle ||
        oldDelegate.displayAngle != displayAngle ||
        oldDelegate.currentLabel != currentLabel ||
        oldDelegate.showReadout != showReadout ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.pressAmount != pressAmount ||
        !_listEquals(oldDelegate.positionLabels, positionLabels);
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
