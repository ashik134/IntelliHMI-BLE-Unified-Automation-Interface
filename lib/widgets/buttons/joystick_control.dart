import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/joystick_config.dart';

const double _kJoystickSlotPadding = 10.0;
const double _kSingleAxisVisualScale = 0.94;
const double _kDualAxisVisualScale = 0.90;
const double _kAnalogGimbalBoundaryFactor = 0.34;
const double _kAnalogGimbalPointerRadiusFactor = 0.105;
const double _kAnalogGimbalPointerTravelFactor = _kAnalogGimbalBoundaryFactor;

double _safeVisualExtent(
  double available, {
  required double min,
  required double max,
  required double scale,
}) {
  final boundedAvailable = math.max(0.0, available);
  if (boundedAvailable <= min) return boundedAvailable;
  return (boundedAvailable * scale)
      .clamp(min, math.min(max, boundedAvailable))
      .toDouble();
}

double _dualAxisSide(double maxWidth, double maxHeight) {
  return _safeVisualExtent(
    math.min(maxWidth, maxHeight),
    min: 92.0,
    max: 288.0,
    scale: _kDualAxisVisualScale,
  );
}

double _joystickSlotPaddingFor(double maxWidth, double maxHeight) {
  final shortest = math.min(maxWidth, maxHeight);
  if (shortest <= 112.0) return 6.0;
  return _kJoystickSlotPadding;
}

class _JoystickDragGeometry {
  const _JoystickDragGeometry({required this.center, required this.radius});

  final Offset center;
  final double radius;
}

class JoystickOutput {
  const JoystickOutput({
    required this.x,
    required this.y,
    required this.xStep,
    required this.yStep,
  });

  final double x;
  final double y;
  final int xStep;
  final int yStep;

  bool get isNeutral => xStep == 0 && yStep == 0 && x == 0.0 && y == 0.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoystickOutput &&
          other.x == x &&
          other.y == y &&
          other.xStep == xStep &&
          other.yStep == yStep;

  @override
  int get hashCode => Object.hash(x, y, xStep, yStep);
}

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialJoystickControl
//
// Renders one of four *visually distinct* control families, selected by
// JoystickConfig.mode:
//   - singleAxisAnalog     -> vertical/horizontal proportional throttle rail
//   - singleAxisDigital5   -> stepped ladder gate with 5 physical detents
//   - dualAxisAnalog       -> round gimbal puck, free continuous travel
//   - dualAxisDigital4     -> cross gate with 4 latching direction cells
//
// The four are deliberately built from different shapes (rail vs. ladder vs.
// disc vs. cross) rather than sharing one painter with parameter tweaks, so
// an operator can identify the control family at a glance.
// ─────────────────────────────────────────────────────────────────────────────

class IndustrialJoystickControl extends StatefulWidget {
  const IndustrialJoystickControl({
    super.key,
    required this.config,
    required this.label,
    required this.activeColor,
    required this.activeColorLight,
    required this.enabled,
    required this.onChanged,
    this.icon,
  });

  final JoystickConfig config;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final bool enabled;
  final ValueChanged<JoystickOutput> onChanged;

  @override
  State<IndustrialJoystickControl> createState() =>
      _IndustrialJoystickControlState();
}

class _IndustrialJoystickControlState extends State<IndustrialJoystickControl>
    with TickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1.0,
    stiffness: 360.0,
    damping: 25.0,
  );

  AnimationController? _springX;
  AnimationController? _springY;
  Offset _value = Offset.zero;
  JoystickOutput _lastOutput = const JoystickOutput(
    x: 0,
    y: 0,
    xStep: 0,
    yStep: 0,
  );

  @override
  void dispose() {
    _cancelSpring();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant IndustrialJoystickControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) {
      _cancelSpring();
      _value = Offset.zero;
      _emitNeutralAfterBuild();
    }
  }

  JoystickConfig get _config => widget.config.normalizedForMode();

  void _emit() {
    final output = _outputFor(_value);
    if (output == _lastOutput) return;
    _lastOutput = output;
    widget.onChanged(output);
  }

  JoystickOutput _outputFor(Offset raw) {
    var x = raw.dx.clamp(-1.0, 1.0);
    var y = raw.dy.clamp(-1.0, 1.0);

    if (!_config.isDualAxis) {
      if (_config.axis == JoystickAxis.horizontal) {
        y = 0.0;
      } else {
        x = 0.0;
      }
    } else if (!_config.allowDiagonal) {
      if (x.abs() > y.abs()) {
        y = 0.0;
      } else if (y.abs() > x.abs()) {
        x = 0.0;
      }
    }

    x = _applyDeadZone(x);
    y = _applyDeadZone(y);

    return JoystickOutput(
      x: _roundAnalog(x),
      y: _roundAnalog(y),
      xStep: _stepFor(x),
      yStep: _stepFor(y),
    );
  }

  double _applyDeadZone(double value) {
    final abs = value.abs();
    if (abs < _config.deadZone) return 0.0;
    if (_config.isDigital) return value;
    final scaled = (abs - _config.deadZone) / (1.0 - _config.deadZone);
    return value.sign * scaled.clamp(0.0, 1.0);
  }

  double _roundAnalog(double value) => (value * 1000).round() / 1000.0;

  int _stepFor(double value) {
    final abs = value.abs();
    if (abs < _config.deadZone) return 0;
    if (abs >= _config.fastThreshold) return value.sign.toInt() * 2;
    if (abs >= _config.slowThreshold) return value.sign.toInt();
    return 0;
  }

  Offset _clampValue(Offset value) {
    var next = value;
    if (!_config.isDualAxis) {
      next = _config.axis == JoystickAxis.horizontal
          ? Offset(next.dx, 0)
          : Offset(0, next.dy);
    }

    next = Offset(next.dx.clamp(-1.0, 1.0), next.dy.clamp(-1.0, 1.0));
    if (_config.boundary == JoystickBoundary.square) return next;

    final distance = next.distance;
    if (distance <= 1.0 || distance == 0.0) return next;
    return next / distance;
  }

  /// For digital modes, the visual knob snaps to the detent/cell center
  /// instead of following the raw drag continuously. Analog modes ignore
  /// this and track the raw value 1:1.
  Offset _snappedForDisplay(Offset raw) {
    if (!_config.isDigital) return raw;

    if (!_config.isDualAxis) {
      final v = _config.axis == JoystickAxis.horizontal ? raw.dx : raw.dy;
      final step = _stepFor(v).toDouble();
      final snapped = step == 0
          ? 0.0
          : (step.sign * (step.abs() == 2 ? 1.0 : 0.5));
      return _config.axis == JoystickAxis.horizontal
          ? Offset(snapped, 0)
          : Offset(0, snapped);
    }

    final xStep = _stepFor(raw.dx);
    final yStep = _stepFor(raw.dy);
    double cell(int step) => step == 0 ? 0.0 : step.sign.toDouble();
    return Offset(cell(xStep), cell(yStep));
  }

  void _handlePanStart(DragStartDetails details) {
    if (!widget.enabled) return;
    _cancelSpring();
    HapticFeedback.selectionClick();
  }

  void _handlePanUpdate(
    DragUpdateDetails details,
    _JoystickDragGeometry geometry,
  ) {
    if (!widget.enabled) return;
    final radius = geometry.radius;
    if (radius <= 0) return;
    final centerDelta = details.localPosition - geometry.center;
    final next = _clampValue(
      Offset(centerDelta.dx / radius, -centerDelta.dy / radius),
    );
    final prevStepKey = _stepKey(_value);
    setState(() => _value = next);
    if (_config.isDigital && _stepKey(next) != prevStepKey) {
      HapticFeedback.selectionClick();
    }
    _emit();
  }

  String _stepKey(Offset v) => '${_stepFor(v.dx)}:${_stepFor(v.dy)}';

  void _handlePanEnd() {
    if (!widget.enabled) return;
    if (_config.springReturn) {
      _springBackToCenter();
    } else {
      HapticFeedback.mediumImpact();
      _emit();
    }
  }

  void _springBackToCenter() {
    _cancelSpring();
    final start = _value;
    final distance = start.distance;
    if (distance == 0.0) {
      _emit();
      return;
    }

    final ctrlX = AnimationController.unbounded(vsync: this);
    final ctrlY = AnimationController.unbounded(vsync: this);
    _springX = ctrlX;
    _springY = ctrlY;
    ctrlX.value = start.dx;
    ctrlY.value = start.dy;

    void tick() {
      if (!mounted) return;
      setState(() => _value = Offset(ctrlX.value, ctrlY.value));
    }

    ctrlX.addListener(tick);
    ctrlY.addListener(tick);

    final xFuture = ctrlX.animateWith(
      SpringSimulation(_spring, start.dx, 0, 0),
    );
    final yFuture = ctrlY.animateWith(
      SpringSimulation(_spring, start.dy, 0, 0),
    );
    Future.wait([xFuture, yFuture]).whenComplete(() {
      if (_springX == ctrlX) _springX = null;
      if (_springY == ctrlY) _springY = null;
      ctrlX.dispose();
      ctrlY.dispose();
      if (!mounted) return;
      setState(() => _value = Offset.zero);
      _emit();
    });

    _emitNeutral();
  }

  void _emitNeutral() {
    const neutral = JoystickOutput(x: 0, y: 0, xStep: 0, yStep: 0);
    if (_lastOutput == neutral) return;
    _lastOutput = neutral;
    widget.onChanged(neutral);
  }

  void _emitNeutralAfterBuild() {
    const neutral = JoystickOutput(x: 0, y: 0, xStep: 0, yStep: 0);
    if (_lastOutput == neutral) return;
    _lastOutput = neutral;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onChanged(neutral);
    });
  }

  void _cancelSpring() {
    final springX = _springX;
    final springY = _springY;
    _springX = null;
    _springY = null;
    springX?.dispose();
    springY?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final output = _outputFor(_value);
    final isActive = output.xStep != 0 || output.yStep != 0;
    final display = _snappedForDisplay(_value);

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: '${widget.label}, ${config.mode.label}',
      child: Opacity(
        opacity: widget.enabled ? 1.0 : 0.52,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 220.0;
            final maxH = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 220.0;
            final slotPadding = _joystickSlotPaddingFor(maxW, maxH);
            final innerW = math.max(0.0, maxW - slotPadding * 2);
            final innerH = math.max(0.0, maxH - slotPadding * 2);

            final body = switch (config.mode) {
              JoystickMode.singleAxisAnalog => _AnalogRail(
                config: config,
                value: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.singleAxisDigital5 => _DigitalLadder(
                config: config,
                rawValue: _value,
                display: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.dualAxisAnalog => _AnalogGimbal(
                config: config,
                value: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
              JoystickMode.dualAxisDigital4 => _DigitalCrossGate(
                config: config,
                display: display,
                isActive: isActive,
                enabled: widget.enabled,
                label: widget.label,
                icon: widget.icon,
                activeColor: widget.activeColor,
                activeColorLight: widget.activeColorLight,
                maxWidth: innerW,
                maxHeight: innerH,
              ),
            };

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled ? _handlePanStart : null,
              onPanUpdate: widget.enabled
                  ? (details) => _handlePanUpdate(
                      details,
                      _dragGeometryFor(config, maxW, maxH, slotPadding),
                    )
                  : null,
              onPanEnd: widget.enabled ? (_) => _handlePanEnd() : null,
              onPanCancel: widget.enabled ? _handlePanEnd : null,
              child: SizedBox(
                width: maxW,
                height: maxH,
                child: Padding(
                  padding: EdgeInsets.all(slotPadding),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: UnconstrainedBox(child: body),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  _JoystickDragGeometry _dragGeometryFor(
    JoystickConfig config,
    double maxW,
    double maxH,
    double slotPadding,
  ) {
    final innerW = math.max(0.0, maxW - slotPadding * 2);
    final innerH = math.max(0.0, maxH - slotPadding * 2);
    final center = Offset(maxW / 2, maxH / 2);
    if (!config.isDualAxis) {
      final availableLength = config.axis == JoystickAxis.horizontal
          ? innerW
          : innerH;
      final length = _safeVisualExtent(
        availableLength,
        min: 96.0,
        max: 320.0,
        scale: _kSingleAxisVisualScale,
      );
      return _JoystickDragGeometry(center: center, radius: length / 2);
    }
    return _JoystickDragGeometry(
      center: center,
      radius: _dualAxisSide(innerW, innerH) * _kAnalogGimbalPointerTravelFactor,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1) SINGLE-AXIS ANALOG — vertical/horizontal proportional throttle rail.
//
// A tall capsule track with a continuously-sliding puck and a fill trail
// from center to puck. No steps, no notches — pure smooth-glide metaphor.
// ─────────────────────────────────────────────────────────────────────────────

class _AnalogRail extends StatelessWidget {
  const _AnalogRail({
    required this.config,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset value;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  bool get _horizontal => config.axis == JoystickAxis.horizontal;

  @override
  Widget build(BuildContext context) {
    final trackThickness = _safeVisualExtent(
      _horizontal ? maxHeight : maxWidth,
      min: 58.0,
      max: 118.0,
      scale: _kSingleAxisVisualScale,
    );
    final trackLength = _safeVisualExtent(
      _horizontal ? maxWidth : maxHeight,
      min: 104.0,
      max: 312.0,
      scale: _kSingleAxisVisualScale,
    );

    return Center(
      child: SizedBox(
        width: _horizontal ? trackLength : trackThickness,
        height: _horizontal ? trackThickness : trackLength,
        child: CustomPaint(
          painter: _AnalogRailPainter(
            horizontal: _horizontal,
            value: _horizontal ? value.dx : value.dy,
            isActive: isActive,
            enabled: enabled,
            activeColor: activeColor,
            activeColorLight: activeColorLight,
            label: label,
            modeText: config.mode.shortLabel,
            icon: icon,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _AnalogRailPainter extends CustomPainter {
  const _AnalogRailPainter({
    required this.horizontal,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
    required this.modeText,
    required this.icon,
  });

  final bool horizontal;
  final double value;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;
  final String modeText;
  final IconData? icon;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(math.min(w, h) / 2),
    );

    // Outer shell shadow + body.
    canvas.drawRRect(
      capsule.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      capsule,
      Paint()
        ..shader = LinearGradient(
          begin: horizontal ? Alignment.topCenter : Alignment.centerLeft,
          end: horizontal ? Alignment.bottomCenter : Alignment.centerRight,
          colors: const [Color(0xFF1B2836), Color(0xFF0E1721)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawRRect(
      capsule.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(24),
    );

    // Inner recessed channel (the "travel path").
    final inset = math.min(w, h) * 0.24;
    final channelRect = horizontal
        ? Rect.fromLTWH(inset, h * 0.36, w - inset * 2, h * 0.28)
        : Rect.fromLTWH(w * 0.36, inset, w * 0.28, h - inset * 2);
    final channelRRect = RRect.fromRectAndRadius(
      channelRect,
      Radius.circular(math.min(channelRect.width, channelRect.height) / 2),
    );
    canvas.drawRRect(channelRRect, Paint()..color = const Color(0xFF060B10));
    canvas.drawRRect(
      channelRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.black.withAlpha(200),
    );

    // Fine calibration ticks along the travel path (continuous-scale cue).
    final tickPaint = Paint()
      ..color = Colors.white.withAlpha(28)
      ..strokeWidth = 1.0;
    const tickCount = 10;
    for (var i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      if (horizontal) {
        final x = channelRect.left + channelRect.width * t;
        final tall = i == tickCount ~/ 2;
        canvas.drawLine(
          Offset(x, channelRect.top - (tall ? 6 : 3)),
          Offset(x, channelRect.top - 1),
          tickPaint,
        );
      } else {
        final y = channelRect.top + channelRect.height * (1 - t);
        final tall = i == tickCount ~/ 2;
        canvas.drawLine(
          Offset(channelRect.right + 1, y),
          Offset(channelRect.right + (tall ? 6 : 3), y),
          tickPaint,
        );
      }
    }

    // Center neutral notch.
    final center = channelRect.center;
    canvas.drawCircle(center, 3.0, Paint()..color = Colors.white.withAlpha(60));

    // Fill trail from center to puck position.
    final travel = horizontal
        ? (channelRect.width - channelRect.height) / 2
        : (channelRect.height - channelRect.width) / 2;
    final puckPos = horizontal
        ? Offset(center.dx + value * travel, center.dy)
        : Offset(center.dx, center.dy - value * travel);

    final trailColor = isActive && enabled
        ? activeColor
        : const Color(0xFF3A4E5F);
    final trailRect = horizontal
        ? Rect.fromPoints(
            Offset(math.min(center.dx, puckPos.dx), channelRect.top + 3),
            Offset(math.max(center.dx, puckPos.dx), channelRect.bottom - 3),
          )
        : Rect.fromPoints(
            Offset(channelRect.left + 3, math.min(center.dy, puckPos.dy)),
            Offset(channelRect.right - 3, math.max(center.dy, puckPos.dy)),
          );
    if (trailRect.width > 0 && trailRect.height > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          trailRect,
          Radius.circular(math.min(trailRect.width, trailRect.height) / 2),
        ),
        Paint()
          ..color = trailColor.withAlpha(isActive && enabled ? 200 : 90)
          ..maskFilter = isActive && enabled
              ? const MaskFilter.blur(BlurStyle.normal, 3)
              : null,
      );
    }

    // Puck (continuous, no snapping).
    final puckRadius = math.min(channelRect.width, channelRect.height) / 2 - 3;
    final puckBase = isActive && enabled
        ? activeColor
        : const Color(0xFF6B7C8D);
    final puckLight = isActive && enabled
        ? activeColorLight
        : const Color(0xFFC3CDD8);
    canvas.drawCircle(
      puckPos,
      puckRadius + 3,
      Paint()
        ..color = Colors.black.withAlpha(140)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      puckPos,
      puckRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [puckLight, puckBase],
        ).createShader(Rect.fromCircle(center: puckPos, radius: puckRadius)),
    );
    canvas.drawCircle(
      puckPos,
      puckRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(70),
    );
    if (isActive && enabled) {
      canvas.drawCircle(
        puckPos,
        puckRadius + 5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = activeColorLight.withAlpha(110),
      );
    }
    // Grip lines on puck for tactile affordance.
    final gripPaint = Paint()
      ..color = Colors.black.withAlpha(90)
      ..strokeWidth = 1.2;
    for (var i = -1; i <= 1; i++) {
      final offset = i * puckRadius * 0.35;
      if (horizontal) {
        canvas.drawLine(
          Offset(puckPos.dx + offset, puckPos.dy - puckRadius * 0.4),
          Offset(puckPos.dx + offset, puckPos.dy + puckRadius * 0.4),
          gripPaint,
        );
      } else {
        canvas.drawLine(
          Offset(puckPos.dx - puckRadius * 0.4, puckPos.dy + offset),
          Offset(puckPos.dx + puckRadius * 0.4, puckPos.dy + offset),
          gripPaint,
        );
      }
    }

    // ANALOG mode tag near one end.
    _paintTag(canvas, size, 'ANALOG', horizontal);

    // Label at the opposite end.
    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isActive && enabled
              ? activeColorLight
              : AppColors.darkText.withAlpha(enabled ? 230 : 120),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 12);
    labelPainter.paint(
      canvas,
      horizontal
          ? Offset(w / 2 - labelPainter.width / 2, h - labelPainter.height - 4)
          : Offset(w / 2 - labelPainter.width / 2, h - labelPainter.height - 6),
    );
  }

  void _paintTag(Canvas canvas, Size size, String text, bool horizontal) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 5));
  }

  @override
  bool shouldRepaint(covariant _AnalogRailPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2) SINGLE-AXIS DIGITAL 5-STEP (spring return) — a ladder gate with 5
// physical detent slots (Fast-, Slow-, Neutral, Slow+, Fast+). The knob
// visibly jumps between slot centers instead of gliding, and a center
// spring glyph communicates the return-to-neutral behavior.
// ─────────────────────────────────────────────────────────────────────────────

class _DigitalLadder extends StatelessWidget {
  const _DigitalLadder({
    required this.config,
    required this.rawValue,
    required this.display,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset rawValue;
  final Offset display;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  bool get _horizontal => config.axis == JoystickAxis.horizontal;

  int _stepFromDisplay() {
    final v = _horizontal ? display.dx : display.dy;
    if (v == 0) return 0;
    return v.abs() >= 1.0 ? (v.sign * 2).round() : v.sign.round();
  }

  @override
  Widget build(BuildContext context) {
    final thickness = _safeVisualExtent(
      _horizontal ? maxHeight : maxWidth,
      min: 62.0,
      max: 124.0,
      scale: _kSingleAxisVisualScale,
    );
    final length = _safeVisualExtent(
      _horizontal ? maxWidth : maxHeight,
      min: 132.0,
      max: 312.0,
      scale: _kSingleAxisVisualScale,
    );

    return Center(
      child: SizedBox(
        width: _horizontal ? length : thickness,
        height: _horizontal ? thickness : length,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: _stepFromDisplay().toDouble()),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          builder: (context, animatedStep, _) {
            return CustomPaint(
              painter: _DigitalLadderPainter(
                horizontal: _horizontal,
                step: animatedStep,
                activeStep: _stepFromDisplay(),
                isActive: isActive,
                enabled: enabled,
                springReturn: config.springReturn,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                label: label,
              ),
              child: const SizedBox.expand(),
            );
          },
        ),
      ),
    );
  }
}

class _DigitalLadderPainter extends CustomPainter {
  const _DigitalLadderPainter({
    required this.horizontal,
    required this.step,
    required this.activeStep,
    required this.isActive,
    required this.enabled,
    required this.springReturn,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
  });

  final bool horizontal;
  final double step;
  final int activeStep;
  final bool isActive;
  final bool enabled;
  final bool springReturn;
  final Color activeColor;
  final Color activeColorLight;
  final String label;

  static const _slotCount = 5; // -2, -1, 0, 1, 2

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bodyRect = Rect.fromLTWH(0, 0, w, h);
    final bodyRRect = RRect.fromRectAndRadius(
      bodyRect,
      const Radius.circular(14),
    );

    canvas.drawRRect(
      bodyRRect.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withAlpha(110)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawRRect(
      bodyRRect,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF20242C), Color(0xFF12151B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(bodyRect),
    );
    canvas.drawRRect(
      bodyRRect.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = Colors.white.withAlpha(20),
    );

    final inset = math.min(w, h) * 0.22;
    final gateRect = horizontal
        ? Rect.fromLTWH(inset, h * 0.30, w - inset * 2, h * 0.40)
        : Rect.fromLTWH(w * 0.30, inset, w * 0.40, h - inset * 2);

    // 5 discrete slot cells rendered as separated notch blocks — the
    // defining visual difference from the smooth analog rail.
    const gap = 4.0;
    final mainAxisExtent = horizontal ? gateRect.width : gateRect.height;
    final crossExtent = horizontal ? gateRect.height : gateRect.width;
    final cellExtent = (mainAxisExtent - gap * (_slotCount - 1)) / _slotCount;

    Rect cellRectFor(int index) {
      final start = horizontal
          ? gateRect.left + index * (cellExtent + gap)
          : gateRect.top + index * (cellExtent + gap);
      return horizontal
          ? Rect.fromLTWH(start, gateRect.top, cellExtent, crossExtent)
          : Rect.fromLTWH(gateRect.left, start, crossExtent, cellExtent);
    }

    // Slot index 0 = most-negative step (-2), index 4 = most-positive (+2).
    // When vertical, up should be positive, so index 0 (top) maps to +2.
    int stepForSlot(int index) {
      final ordered = horizontal ? index - 2 : 2 - index;
      return ordered;
    }

    final labels = <int, String>{
      -2: 'FAST',
      -1: 'SLOW',
      0: '',
      1: 'SLOW',
      2: 'FAST',
    };

    for (var i = 0; i < _slotCount; i++) {
      final slotStep = stepForSlot(i);
      final rect = cellRectFor(i);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final isNeutralSlot = slotStep == 0;
      final magnitude = slotStep.abs();

      final litFraction = _litFractionFor(slotStep);

      final baseColor = isNeutralSlot
          ? const Color(0xFF0B0F14)
          : const Color(0xFF141A21);
      canvas.drawRRect(rrect, Paint()..color = baseColor);

      if (litFraction > 0) {
        final litColor = magnitude == 2
            ? activeColor
            : Color.lerp(activeColor, Colors.white, 0.18)!;
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = litColor.withAlpha(
              (litFraction * (enabled ? 235 : 120)).round(),
            )
            ..maskFilter = litFraction > 0.5
                ? const MaskFilter.blur(BlurStyle.normal, 2)
                : null,
        );
      }

      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNeutralSlot ? 1.6 : 1.0
          ..color = isNeutralSlot
              ? Colors.white.withAlpha(90)
              : Colors.black.withAlpha(200),
      );

      // Detent notch marks (little tick at the cell's outer edge) — visually
      // reads as a physical gate rather than a continuous channel.
      final notchPaint = Paint()
        ..color = Colors.white.withAlpha(36)
        ..strokeWidth = 1.2;
      if (horizontal) {
        canvas.drawLine(
          Offset(rect.center.dx, rect.top + 2),
          Offset(rect.center.dx, rect.top + 6),
          notchPaint,
        );
      } else {
        canvas.drawLine(
          Offset(rect.right - 2, rect.center.dy),
          Offset(rect.right - 6, rect.center.dy),
          notchPaint,
        );
      }

      final text = labels[slotStep] ?? '';
      if (text.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: litFraction > 0.4
                  ? Colors.black.withAlpha(180)
                  : AppColors.darkTextMuted.withAlpha(enabled ? 160 : 80),
              fontSize: 7,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            rect.center.dx - tp.width / 2,
            horizontal
                ? rect.bottom - tp.height - 3
                : rect.center.dy - tp.height / 2,
          ),
        );
      } else {
        // Neutral slot gets a small spring/center glyph instead of text.
        canvas.drawCircle(
          rect.center,
          2.6,
          Paint()..color = Colors.white.withAlpha(120),
        );
      }
    }

    // Slider indicator (the physical lever) drawn on top, jumping between
    // slot centers as `step` animates.
    final clampedStep = step.clamp(-2.0, 2.0);
    final indicatorIndex = horizontal ? clampedStep + 2 : 2 - clampedStep;
    final indicatorRect = _lerpCellRect(cellRectFor, indicatorIndex);
    final knobRect = horizontal
        ? Rect.fromCenter(
            center: indicatorRect.center,
            width: indicatorRect.width * 0.72,
            height: crossExtent * 1.16,
          )
        : Rect.fromCenter(
            center: indicatorRect.center,
            width: crossExtent * 1.16,
            height: indicatorRect.height * 0.72,
          );
    final knobRRect = RRect.fromRectAndRadius(
      knobRect,
      const Radius.circular(8),
    );

    final leverBase = isActive && enabled
        ? activeColor
        : const Color(0xFF5B6B7A);
    final leverLight = isActive && enabled
        ? activeColorLight
        : const Color(0xFFB9C4CE);
    canvas.drawRRect(
      knobRRect.shift(const Offset(0, 2)),
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [leverLight, leverBase],
        ).createShader(knobRect),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withAlpha(90),
    );
    // Ribbed grip on the lever cap.
    final ribPaint = Paint()
      ..color = Colors.black.withAlpha(100)
      ..strokeWidth = 1.1;
    for (var i = -1; i <= 1; i++) {
      final o = i * (horizontal ? knobRect.width : knobRect.height) * 0.22;
      if (horizontal) {
        canvas.drawLine(
          Offset(knobRect.center.dx + o, knobRect.top + 4),
          Offset(knobRect.center.dx + o, knobRect.bottom - 4),
          ribPaint,
        );
      } else {
        canvas.drawLine(
          Offset(knobRect.left + 4, knobRect.center.dy + o),
          Offset(knobRect.right - 4, knobRect.center.dy + o),
          ribPaint,
        );
      }
    }

    // DIGITAL tag + spring-return glyph.
    final tagText = springReturn ? 'DIGITAL · SPRING' : 'DIGITAL';
    final tp = TextPainter(
      text: TextSpan(
        text: tagText,
        style: TextStyle(
          color: AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 8);
    tp.paint(canvas, Offset(w / 2 - tp.width / 2, 5));

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isActive && enabled
              ? activeColorLight
              : AppColors.darkText.withAlpha(enabled ? 230 : 120),
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - 12);
    labelPainter.paint(
      canvas,
      Offset(w / 2 - labelPainter.width / 2, h - labelPainter.height - 4),
    );
  }

  double _litFractionFor(int slotStep) {
    if (slotStep == 0) return 0;
    if (activeStep == 0) return 0;
    if (activeStep.sign != slotStep.sign) return 0;
    if (slotStep.abs() == 1) return 1.0; // slow lights once past slow threshold
    // fast slot lights only when activeStep reaches magnitude 2
    return activeStep.abs() >= 2 ? 1.0 : 0.0;
  }

  Rect _lerpCellRect(Rect Function(int) cellRectFor, double indexFractional) {
    final lower = indexFractional.floor().clamp(0, _slotCount - 1);
    final upper = indexFractional.ceil().clamp(0, _slotCount - 1);
    final t = indexFractional - lower;
    final a = cellRectFor(lower);
    if (lower == upper) return a;
    final b = cellRectFor(upper);
    return Rect.lerp(a, b, t)!;
  }

  @override
  bool shouldRepaint(covariant _DigitalLadderPainter oldDelegate) {
    return oldDelegate.step != step ||
        oldDelegate.activeStep != activeStep ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3) DUAL-AXIS ANALOG — round gimbal puck with free continuous 2D travel.
// ─────────────────────────────────────────────────────────────────────────────

class _AnalogGimbal extends StatelessWidget {
  const _AnalogGimbal({
    required this.config,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset value;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final side = _dualAxisSide(maxWidth, maxHeight);
    final radius = side * _kAnalogGimbalPointerTravelFactor;
    final knobRadius = side * _kAnalogGimbalPointerRadiusFactor;
    final knobOffset = Offset(value.dx * radius, -value.dy * radius);

    return Center(
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(
              painter: _GimbalPainter(
                config: config,
                value: value,
                isActive: isActive,
                enabled: enabled,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                label: label,
              ),
              child: SizedBox(width: side, height: side),
            ),
            Transform.translate(
              offset: knobOffset,
              child: _GimbalKnob(
                radius: knobRadius,
                value: value,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                isActive: isActive,
                enabled: enabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GimbalKnob extends StatelessWidget {
  const _GimbalKnob({
    required this.radius,
    required this.value,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.enabled,
  });

  final double radius;
  final Offset value;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return CustomPaint(
      painter: _GimbalKnobPainter(
        value: value,
        activeColor: activeColor,
        activeColorLight: activeColorLight,
        isActive: isActive,
        enabled: enabled,
      ),
      size: Size.square(size),
    );
  }
}

class _GimbalKnobPainter extends CustomPainter {
  const _GimbalKnobPainter({
    required this.value,
    required this.activeColor,
    required this.activeColorLight,
    required this.isActive,
    required this.enabled,
  });

  final Offset value;
  final Color activeColor;
  final Color activeColorLight;
  final bool isActive;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final r = side / 2;
    final active = isActive && enabled;
    final base = active ? activeColor : const Color(0xFF50606E);
    final light = active ? activeColorLight : const Color(0xFFC8D2DC);
    final dark = Color.alphaBlend(Colors.black.withAlpha(135), base);
    final thumbRect = Rect.fromCircle(center: center, radius: r);

    final travel = value.distance.clamp(0.0, 1.0);
    final tilt = value.distance == 0
        ? Offset.zero
        : Offset(value.dx, -value.dy) / value.distance;

    canvas.drawCircle(
      center + Offset(0, r * 0.22),
      r * 0.92,
      Paint()
        ..color = Colors.black.withAlpha(145)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.24),
    );

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(-0.35 + tilt.dx * 0.12, -0.45 + tilt.dy * 0.12),
          radius: 1.05,
          colors: [light, base, dark],
          stops: const [0.0, 0.54, 1.0],
        ).createShader(thumbRect),
    );
    canvas.drawCircle(
      center,
      r - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.1, side * 0.055)
        ..color = Colors.white.withAlpha(enabled ? 56 : 24),
    );

    if (active) {
      canvas.drawCircle(
        center,
        r * 0.82,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, side * 0.035)
          ..color = activeColorLight.withAlpha((80 + travel * 70).round()),
      );
    }

    final insertR = r * 0.48;
    final insertRect = Rect.fromCircle(center: center, radius: insertR);
    canvas.drawCircle(
      center,
      insertR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.35),
          radius: 1.0,
          colors: [
            Colors.white.withAlpha(enabled ? 78 : 34),
            Colors.black.withAlpha(34),
          ],
        ).createShader(insertRect),
    );
    canvas.drawCircle(
      center,
      insertR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, side * 0.028)
        ..color = Colors.black.withAlpha(110),
    );

    final groovePaint = Paint()
      ..color = Colors.black.withAlpha(92)
      ..strokeWidth = math.max(0.8, side * 0.032)
      ..strokeCap = StrokeCap.round;
    for (final offset in [-0.34, 0.0, 0.34]) {
      final y = center.dy + r * offset;
      canvas.drawLine(
        Offset(center.dx - r * 0.30, y),
        Offset(center.dx + r * 0.30, y),
        groovePaint,
      );
    }

    canvas.drawCircle(
      center + Offset(-r * 0.26, -r * 0.30),
      r * 0.13,
      Paint()..color = Colors.white.withAlpha(enabled ? 82 : 34),
    );
  }

  @override
  bool shouldRepaint(covariant _GimbalKnobPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled;
  }
}

class _GimbalPainter extends CustomPainter {
  const _GimbalPainter({
    required this.config,
    required this.value,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
  });

  final JoystickConfig config;
  final Offset value;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = side * 0.48;
    final boundaryR = side * _kAnalogGimbalBoundaryFactor;
    final pointerTravelR = side * _kAnalogGimbalPointerTravelFactor;

    canvas.drawCircle(
      center + Offset(0, side * 0.025),
      outerR,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // Circular bezel — smooth radial dish (distinct from the ladder's flat
    // rounded-rect body and the cross-gate's angular plate).
    final plateRect = Rect.fromCircle(center: center, radius: outerR);
    canvas.drawCircle(
      center,
      outerR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.36, -0.5),
          radius: 1.2,
          colors: [Color(0xFF2C3B4C), Color(0xFF17222E), Color(0xFF080D13)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(plateRect),
    );
    canvas.drawCircle(
      center,
      outerR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withAlpha(30),
    );

    // Concentric travel rings (continuous-field cue, no wedge divisions).
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.white.withAlpha(18);
    for (final f in [0.34, 0.67, 1.0]) {
      canvas.drawCircle(center, boundaryR * f, ringPaint);
    }

    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = side * 0.014
      ..color = enabled
          ? AppColors.darkBorder.withAlpha(230)
          : AppColors.disabled.withAlpha(120);
    if (config.boundary == JoystickBoundary.circular) {
      canvas.drawCircle(center, boundaryR, boundaryPaint);
    } else {
      final rect = Rect.fromCenter(
        center: center,
        width: boundaryR * 2,
        height: boundaryR * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(side * 0.05)),
        boundaryPaint,
      );
    }

    // Faint crosshair (fine, not gate-like).
    final crossPaint = Paint()
      ..color = Colors.white.withAlpha(22)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(center.dx - boundaryR, center.dy),
      Offset(center.dx + boundaryR, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - boundaryR),
      Offset(center.dx, center.dy + boundaryR),
      crossPaint,
    );

    final target = Offset(
      center.dx + value.dx * pointerTravelR,
      center.dy - value.dy * pointerTravelR,
    );

    // Smooth proportional vector from center to the current X/Y output.
    if (isActive && enabled) {
      canvas.drawLine(
        center,
        target,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = side * 0.02
          ..strokeCap = StrokeCap.round
          ..color = activeColorLight.withAlpha(200)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      canvas.drawCircle(
        target,
        side * 0.018,
        Paint()..color = activeColorLight.withAlpha(210),
      );
    }

    canvas.drawCircle(
      center,
      side * 0.05,
      Paint()
        ..color = isActive && enabled
            ? activeColor.withAlpha(160)
            : const Color(0xFF263748),
    );

    // ANALOG tag.
    final tagPainter = TextPainter(
      text: TextSpan(
        text: config.springReturn ? '2-AXIS ANALOG' : '2-AXIS ANALOG',
        style: TextStyle(
          color: AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
          fontSize: (side * 0.042).clamp(7.0, 10.0),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tagPainter.paint(
      canvas,
      Offset(center.dx - tagPainter.width / 2, side * 0.08),
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isActive && enabled
              ? activeColorLight
              : AppColors.darkText.withAlpha(enabled ? 230 : 120),
          fontSize: (side * 0.055).clamp(9.0, 15.0),
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: side * 0.66);
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, size.height - side * 0.13),
    );
  }

  @override
  bool shouldRepaint(covariant _GimbalPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.config != config ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4) DUAL-AXIS DIGITAL 4-STEP (friction/maintained) — a cross/H-gate with 4
// chunky latching cells (N/E/S/W). The knob jumps to a cell and *stays*
// there (no spring animation), reinforcing the maintained-friction feel.
// ─────────────────────────────────────────────────────────────────────────────

class _DigitalCrossGate extends StatelessWidget {
  const _DigitalCrossGate({
    required this.config,
    required this.display,
    required this.isActive,
    required this.enabled,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.activeColorLight,
    required this.maxWidth,
    required this.maxHeight,
  });

  final JoystickConfig config;
  final Offset display;
  final bool isActive;
  final bool enabled;
  final String label;
  final IconData? icon;
  final Color activeColor;
  final Color activeColorLight;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final side = _dualAxisSide(maxWidth, maxHeight);
    final cellX = display.dx.round().clamp(-1, 1);
    final cellY = display.dy.round().clamp(-1, 1);

    return Center(
      child: SizedBox(
        width: side,
        height: side,
        child: TweenAnimationBuilder<Offset>(
          tween: Tween(
            begin: Offset.zero,
            end: Offset(cellX.toDouble(), cellY.toDouble()),
          ),
          duration: config.springReturn
              ? const Duration(milliseconds: 90)
              : const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          builder: (context, animatedCell, _) {
            return CustomPaint(
              painter: _CrossGatePainter(
                config: config,
                animatedCell: animatedCell,
                activeCellX: cellX,
                activeCellY: cellY,
                isActive: isActive,
                enabled: enabled,
                activeColor: activeColor,
                activeColorLight: activeColorLight,
                label: label,
              ),
              child: SizedBox(width: side, height: side),
            );
          },
        ),
      ),
    );
  }
}

class _CrossGatePainter extends CustomPainter {
  const _CrossGatePainter({
    required this.config,
    required this.animatedCell,
    required this.activeCellX,
    required this.activeCellY,
    required this.isActive,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.label,
  });

  final JoystickConfig config;
  final Offset animatedCell;
  final int activeCellX;
  final int activeCellY;
  final bool isActive;
  final bool enabled;
  final Color activeColor;
  final Color activeColorLight;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final plateR = side * 0.48;

    canvas.drawCircle(
      center + Offset(0, side * 0.025),
      plateR,
      Paint()
        ..color = Colors.black.withAlpha(130)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );

    // Angular square plate (distinct from the gimbal's round dish).
    final plateRect = Rect.fromCenter(
      center: center,
      width: plateR * 2,
      height: plateR * 2,
    );
    final plateRRect = RRect.fromRectAndRadius(
      plateRect,
      Radius.circular(side * 0.09),
    );
    canvas.drawRRect(
      plateRRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF23262E), Color(0xFF121319)],
        ).createShader(plateRect),
    );
    canvas.drawRRect(
      plateRRect.deflate(1.2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withAlpha(24),
    );

    // Cross-shaped gate carved from 5 cells: center + N/E/S/W. Each is a
    // distinct angular block with a visible seam — reads as "gated slots"
    // rather than a free field.
    final armLen = plateR * 0.62;
    final cell = plateR * 0.46;
    final gap = side * 0.02;

    Rect cellRect(int cx, int cy) {
      final dx = cx * (cell + gap);
      final dy = -cy * (cell + gap);
      return Rect.fromCenter(
        center: center + Offset(dx, dy),
        width: cell,
        height: cell,
      );
    }

    final positions = <(int, int)>[(0, 0), (0, 1), (0, -1), (-1, 0), (1, 0)];

    for (final (cx, cy) in positions) {
      final rect = cellRect(cx, cy);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(side * 0.03));
      final isNeutral = cx == 0 && cy == 0;
      final isEngaged =
          !isNeutral && activeCellX == cx && activeCellY == cy && isActive;

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = isNeutral
              ? const Color(0xFF0B0D11)
              : const Color(0xFF161920),
      );
      if (isEngaged && enabled) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = activeColor.withAlpha(230)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
      }
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isNeutral ? 1.6 : 1.1
          ..color = isNeutral
              ? Colors.white.withAlpha(100)
              : Colors.black.withAlpha(210),
      );

      // Chevron direction glyph on each arm cell.
      if (!isNeutral) {
        final glyphColor = isEngaged && enabled
            ? Colors.black.withAlpha(190)
            : AppColors.darkTextMuted.withAlpha(enabled ? 150 : 80);
        _drawChevron(canvas, rect.center, cx, cy, side * 0.05, glyphColor);
      } else {
        canvas.drawCircle(
          rect.center,
          side * 0.018,
          Paint()..color = Colors.white.withAlpha(110),
        );
      }
    }

    // Connective seams between center and arms (visual "gate track").
    final seamPaint = Paint()
      ..color = Colors.black.withAlpha(160)
      ..strokeWidth = side * 0.012;
    canvas.drawLine(
      center + Offset(0, -armLen * 0.35),
      center + Offset(0, armLen * 0.35),
      seamPaint,
    );
    canvas.drawLine(
      center + Offset(-armLen * 0.35, 0),
      center + Offset(armLen * 0.35, 0),
      seamPaint,
    );

    // Latching knob — square-ish puck that jumps between cells and holds.
    final knobCenter =
        center +
        Offset(animatedCell.dx * (cell + gap), -animatedCell.dy * (cell + gap));
    final knobSize = cell * 0.54;
    final knobRect = Rect.fromCenter(
      center: knobCenter,
      width: knobSize,
      height: knobSize,
    );
    final knobRRect = RRect.fromRectAndRadius(
      knobRect,
      Radius.circular(side * 0.025),
    );
    final base = isActive && enabled ? activeColor : const Color(0xFF576675);
    final light = isActive && enabled
        ? activeColorLight
        : const Color(0xFFC0CAD3);

    canvas.drawRRect(
      knobRRect.shift(const Offset(0, 3)),
      Paint()
        ..color = Colors.black.withAlpha(170)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, base],
        ).createShader(knobRect),
    );
    canvas.drawRRect(
      knobRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withAlpha(90),
    );
    if (isActive && enabled) {
      canvas.drawRRect(
        knobRRect.inflate(side * 0.015),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = activeColorLight.withAlpha(110),
      );
    }

    // DIGITAL FRICTION tag.
    final tagPainter = TextPainter(
      text: TextSpan(
        text: 'GATED · FRICTION',
        style: TextStyle(
          color: AppColors.darkTextMuted.withAlpha(enabled ? 210 : 110),
          fontSize: (side * 0.04).clamp(7.0, 10.0),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: side * 0.9);
    tagPainter.paint(
      canvas,
      Offset(center.dx - tagPainter.width / 2, side * 0.045),
    );

    final labelPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isActive && enabled
              ? activeColorLight
              : AppColors.darkText.withAlpha(enabled ? 230 : 120),
          fontSize: (side * 0.052).clamp(9.0, 14.0),
          fontWeight: FontWeight.w800,
        ),
      ),
      maxLines: 1,
      ellipsis: '…',
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: side * 0.66);
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, size.height - side * 0.10),
    );
  }

  void _drawChevron(
    Canvas canvas,
    Offset center,
    int dx,
    int dy,
    double size,
    Color color,
  ) {
    final path = Path();
    final dir = Offset(dx.toDouble(), -dy.toDouble());
    final perp = Offset(-dir.dy, dir.dx);
    final tip = center + dir * size * 0.5;
    final baseA = center - dir * size * 0.35 + perp * size * 0.4;
    final baseB = center - dir * size * 0.35 - perp * size * 0.4;
    path.moveTo(baseA.dx, baseA.dy);
    path.lineTo(tip.dx, tip.dy);
    path.lineTo(baseB.dx, baseB.dy);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size * 0.22
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrossGatePainter oldDelegate) {
    return oldDelegate.animatedCell != animatedCell ||
        oldDelegate.activeCellX != activeCellX ||
        oldDelegate.activeCellY != activeCellY ||
        oldDelegate.isActive != isActive ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.label != label;
  }
}
