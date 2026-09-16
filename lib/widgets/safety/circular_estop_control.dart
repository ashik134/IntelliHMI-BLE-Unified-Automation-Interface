import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CircularEStopControl
//
// Standalone circular E-STOP control, used by the Safety Control Screen
// profile. Only one circular button is ever on screen at a time —
//
//   idle (tap to trip) ⇄ latched (swipe the handle clockwise to reset)
//
// estopLatched / onEStopTap / onResetActivated / resetEnabled are the full
// contract — drive them from whatever state you like.
// ─────────────────────────────────────────────────────────────────────────────

const Color _eStopColor = Color(0xFFDA3633);
const Color _readyColor = Color(0xFF3FB950);
const Color _targetColor = Color(0xFFE3B341);

class CircularEStopControl extends StatelessWidget {
  const CircularEStopControl({
    super.key,
    required this.estopLatched,
    required this.onEStopTap,
    required this.onResetActivated,
    this.diameter = 220.0,
    this.resetEnabled = true,
  });

  final bool estopLatched;
  final VoidCallback onEStopTap;
  final VoidCallback onResetActivated;
  final double diameter;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: animation,
          child: FadeTransition(opacity: animation, child: child),
        ),
        // The default switcher Stack clips at the box edge, which would slice
        // the dial's outer glow into a square.
        layoutBuilder: (currentChild, previousChildren) => Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        ),
        child: estopLatched
            ? _CircularResetSwipe(
                key: const ValueKey('estop-reset'),
                diameter: diameter,
                enabled: resetEnabled,
                onActivated: onResetActivated,
              )
            : _CircularEStopButton(
                key: const ValueKey('estop-idle'),
                diameter: diameter,
                onTap: onEStopTap,
              ),
      ),
    );
  }
}

// ── idle state: tap-to-trip mushroom-style circular button ─────────────────

class _CircularEStopButton extends StatefulWidget {
  const _CircularEStopButton({
    super.key,
    required this.diameter,
    required this.onTap,
  });

  final double diameter;
  final VoidCallback onTap;

  @override
  State<_CircularEStopButton> createState() => _CircularEStopButtonState();
}

class _CircularEStopButtonState extends State<_CircularEStopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.mediumImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.diameter;
    final innerD = d * 0.8;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final pulse = _pulseController.value;
        return Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [Color(0xFF3A3B3D), Color(0xFF17181A)],
              radius: 0.85,
            ),
            border: Border.all(color: Colors.white.withAlpha(30), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _eStopColor.withAlpha((70 + pulse * 60).round()),
                blurRadius: 18 + pulse * 14,
                spreadRadius: 1 + pulse * 3,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: child,
        );
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _handleTap,
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withAlpha(60),
            highlightColor: Colors.white.withAlpha(25),
            child: Container(
              width: innerD,
              height: innerD,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE74C3C), Color(0xFF8B1A1A)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border.all(
                  color: Colors.white.withAlpha(70),
                  width: 2.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Glossy highlight to read as a physical plastic cap
                  // rather than a flat filled circle.
                  Positioned(
                    top: innerD * 0.08,
                    child: Container(
                      width: innerD * 0.55,
                      height: innerD * 0.22,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(innerD),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withAlpha(70),
                            Colors.white.withAlpha(0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.power_settings_new,
                        color: Colors.white,
                        size: innerD * 0.34,
                      ),
                      SizedBox(height: innerD * 0.045),
                      Text(
                        'E-STOP',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: innerD * 0.12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── latched state: drag the handle clockwise around the groove to reset ────

class _CircularResetSwipe extends StatefulWidget {
  const _CircularResetSwipe({
    super.key,
    required this.diameter,
    required this.enabled,
    required this.onActivated,
  });

  final double diameter;
  final bool enabled;
  final VoidCallback onActivated;

  @override
  State<_CircularResetSwipe> createState() => _CircularResetSwipeState();
}

class _CircularResetSwipeState extends State<_CircularResetSwipe>
    with SingleTickerProviderStateMixin {
  // 12 o'clock, so the first inch of travel reads as "swipe right" exactly
  // like a linear track before curving down and around.
  static const double _startAngle = -math.pi / 2;

  // The groove stops short of a full circle so the start detent and the
  // reset target stay distinct positions instead of the same spot.
  static const double _gapAngle = math.pi / 7;
  static const double _requiredSweep = (2 * math.pi) - _gapAngle;

  // Ratchet clicks per full sweep. Feedback only — activation is still
  // decided solely by _sweep reaching _requiredSweep.
  static const int _detentCount = 8;

  // Groove is sized to swallow the handle, so the pair reads as one machined
  // channel rather than a puck floating over a thin progress ring.
  double get _trackWidth => (widget.diameter * 0.26).clamp(58.0, 96.0);
  double get _handleSize => _trackWidth - 10.0;
  double get _trackRadius => (widget.diameter - _trackWidth) / 2 - 3.0;
  double get _faceDiameter =>
      math.max(0.0, 2 * (_trackRadius - _trackWidth / 2) - 4.0);

  // ── drag state ──────────────────────────────────────────────────────────
  double _sweep = 0.0;
  double? _lastPointerAngle;
  bool _isDragging = false;
  int _lastDetent = 0;
  bool _reachedFull = false;

  // ── snap-back animation ────────────────────────────────────────────────
  late AnimationController _snapController;
  late Animation<double> _snapAnimation;
  double _snapStartSweep = 0.0;
  bool _isSnapping = false;

  double get _displaySweep {
    if (_isSnapping) return _snapStartSweep * (1.0 - _snapAnimation.value);
    return _sweep;
  }

  double get _progress => (_displaySweep / _requiredSweep).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _snapAnimation = CurvedAnimation(
      parent: _snapController,
      curve: Curves.easeOutCubic,
    );
    _snapController.addListener(() {
      if (mounted) setState(() {});
    });
    _snapController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isSnapping = false;
          _sweep = 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  double _angleAt(Offset localPosition, Offset center) {
    final v = localPosition - center;
    return math.atan2(v.dy, v.dx);
  }

  // Shortest signed distance between two angles, wrapped to (-pi, pi] so a
  // crossing of the +-pi seam doesn't register as a near-full reverse spin.
  double _shortestDelta(double from, double to) {
    var delta = to - from;
    while (delta <= -math.pi) {
      delta += 2 * math.pi;
    }
    while (delta > math.pi) {
      delta -= 2 * math.pi;
    }
    return delta;
  }

  void _onPanStart(DragStartDetails details, Offset center) {
    if (!widget.enabled) return;
    if (_isSnapping) {
      _snapController.stop();
      _isSnapping = false;
    }
    setState(() {
      _isDragging = true;
      _sweep = 0.0;
      _lastDetent = 0;
      _reachedFull = false;
      _lastPointerAngle = _angleAt(details.localPosition, center);
    });
  }

  void _onPanUpdate(DragUpdateDetails details, Offset center) {
    if (!_isDragging || _lastPointerAngle == null) return;
    final angle = _angleAt(details.localPosition, center);
    final delta = _shortestDelta(_lastPointerAngle!, angle);
    _lastPointerAngle = angle;
    setState(() {
      _sweep = (_sweep + delta).clamp(0.0, _requiredSweep);
    });
    _emitDetentFeedback();
  }

  void _emitDetentFeedback() {
    final detent = (_sweep / _requiredSweep * _detentCount).floor();
    if (detent != _lastDetent) {
      _lastDetent = detent;
      HapticFeedback.selectionClick();
    }
    if (_sweep >= _requiredSweep) {
      if (!_reachedFull) {
        _reachedFull = true;
        HapticFeedback.mediumImpact();
      }
    } else {
      _reachedFull = false;
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);

    if (_sweep >= _requiredSweep) {
      HapticFeedback.heavyImpact();
      widget.onActivated();
    } else {
      _snapStartSweep = _sweep;
      _isSnapping = true;
      _snapController.forward(from: 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Opacity(opacity: 0.45, child: _buildDial(0.0));
    }

    final center = Offset(widget.diameter / 2, widget.diameter / 2);

    return GestureDetector(
      onPanStart: (details) => _onPanStart(details, center),
      onPanUpdate: (details) => _onPanUpdate(details, center),
      onPanEnd: _onPanEnd,
      child: _buildDial(_progress),
    );
  }

  Widget _buildDial(double progress) {
    final d = widget.diameter;
    final center = Offset(d / 2, d / 2);
    final handleAngle = _startAngle + progress * _requiredSweep;
    final handleCenter =
        center +
        Offset(
          _trackRadius * math.cos(handleAngle),
          _trackRadius * math.sin(handleAngle),
        );
    final complete = progress >= 1.0;

    return SizedBox(
      width: d,
      height: d,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // ── housing ──────────────────────────────────────────────────
          Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFF2A1618), Color(0xFF140B0C)],
                radius: 0.95,
              ),
              border: Border.all(color: Colors.white.withAlpha(22), width: 1.4),
              boxShadow: [
                BoxShadow(
                  color: (complete ? _readyColor : _eStopColor).withAlpha(
                    (60 + progress * 90).round(),
                  ),
                  blurRadius: 18 + progress * 22,
                  spreadRadius: progress * 4,
                ),
                BoxShadow(
                  color: Colors.black.withAlpha(140),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),

          // ── machined groove, ticks, chevrons, progress fill ───────────
          CustomPaint(
            size: Size(d, d),
            painter: _ResetTrackPainter(
              progress: progress,
              trackRadius: _trackRadius,
              trackWidth: _trackWidth,
              startAngle: _startAngle,
              requiredSweep: _requiredSweep,
            ),
          ),

          // ── centre faceplate ─────────────────────────────────────────
          Container(
            width: _faceDiameter,
            height: _faceDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [Color(0xFF241A1B), Color(0xFF130C0D)],
              ),
              border: Border.all(color: Colors.white.withAlpha(18)),
              boxShadow: [
                BoxShadow(color: Colors.black.withAlpha(120), blurRadius: 10),
              ],
            ),
          ),
          _buildFace(progress, complete),

          // ── the handle ───────────────────────────────────────────────
          Positioned(
            left: handleCenter.dx - _handleSize / 2,
            top: handleCenter.dy - _handleSize / 2,
            child: Transform.rotate(
              angle: handleAngle + math.pi / 2,
              child: AnimatedScale(
                scale: _isDragging ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: _ResetHandle(
                  size: _handleSize,
                  dragging: _isDragging,
                  complete: complete,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFace(double progress, bool complete) {
    final size = _faceDiameter * 0.84;

    if (!widget.enabled) {
      return SizedBox(
        width: size,
        height: size,
        child: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, color: Colors.white38, size: 32),
              SizedBox(height: 8),
              Text(
                'EXIT EDIT\nMODE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final introOpacity = (1.0 - progress / 0.10).clamp(0.0, 1.0);
    final meterOpacity = complete
        ? 0.0
        : ((progress - 0.04) / 0.08).clamp(0.0, 1.0);

    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (introOpacity > 0.005)
              AnimatedOpacity(
                opacity: introOpacity,
                duration: const Duration(milliseconds: 120),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.rotate_right_rounded,
                        color: Colors.white54,
                        size: 34,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'SWIPE TO RESET',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'slide the handle clockwise',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            if (meterOpacity > 0.005)
              AnimatedOpacity(
                opacity: meterOpacity,
                duration: const Duration(milliseconds: 120),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'KEEP SWIPING',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (complete)
              const FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: _readyColor,
                      size: 38,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'RELEASE TO RESET',
                      style: TextStyle(
                        color: _readyColor,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The physical-feeling handle that rides inside the groove. Rotated by its
/// parent so the grip ridges stay square to the channel and the arrow always
/// points the way the operator has to travel.
class _ResetHandle extends StatelessWidget {
  const _ResetHandle({
    required this.size,
    required this.dragging,
    required this.complete,
  });

  final double size;
  final bool dragging;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final accent = complete ? _readyColor : _eStopColor;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7C838D), Color(0xFF3B4147), Color(0xFF22262A)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(
          color: accent.withAlpha(dragging || complete ? 235 : 170),
          width: math.max(2.0, size * 0.045),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(170),
            blurRadius: dragging ? 14 : 9,
            offset: const Offset(0, 4),
          ),
          if (complete)
            BoxShadow(
              color: _readyColor.withAlpha(120),
              blurRadius: 18,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _HandleGripPainter(complete: complete),
          ),
          Icon(
            complete
                ? Icons.check_rounded
                : Icons.keyboard_double_arrow_right_rounded,
            color: Colors.white,
            size: size * 0.44,
          ),
        ],
      ),
    );
  }
}

class _HandleGripPainter extends CustomPainter {
  const _HandleGripPainter({required this.complete});

  final bool complete;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Machined highlight across the top of the cap.
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.78),
      math.pi * 1.16,
      math.pi * 0.52,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.16
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withAlpha(32),
    );

    if (complete) return;

    // Grip ridges either side of the arrow, square to the direction of travel.
    final ridge = Paint()
      ..color = Colors.white.withAlpha(60)
      ..strokeWidth = math.max(1.6, r * 0.09)
      ..strokeCap = StrokeCap.round;
    for (final dx in [-r * 0.52, r * 0.52]) {
      canvas.drawLine(
        c + Offset(dx, -r * 0.22),
        c + Offset(dx, r * 0.22),
        ridge,
      );
    }
  }

  @override
  bool shouldRepaint(_HandleGripPainter old) => old.complete != complete;
}

/// Paints the recessed channel the handle travels in: groove walls, machined
/// detent ticks, the reset target zone, the energised fill left behind the
/// handle, and the chevrons that point the way round.
class _ResetTrackPainter extends CustomPainter {
  const _ResetTrackPainter({
    required this.progress,
    required this.trackRadius,
    required this.trackWidth,
    required this.startAngle,
    required this.requiredSweep,
  });

  final double progress;
  final double trackRadius;
  final double trackWidth;
  final double startAngle;
  final double requiredSweep;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: trackRadius);
    final endAngle = startAngle + requiredSweep;
    final filledSweep = requiredSweep * progress;
    final innerEdge = trackRadius - trackWidth / 2;
    final outerEdge = trackRadius + trackWidth / 2;
    final complete = progress >= 1.0;

    // ── recessed channel ────────────────────────────────────────────────
    canvas.drawArc(
      rect,
      startAngle,
      requiredSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF120809),
    );

    // Walls: dark shadow on the outer lip, faint catch-light on the inner.
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerEdge - 1.2),
      startAngle,
      requiredSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withAlpha(160),
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: innerEdge + 1.0),
      startAngle,
      requiredSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withAlpha(18),
    );

    // ── reset gate at the end of the run ────────────────────────────────
    const zoneSweep = math.pi / 15;
    final zoneStart = endAngle - zoneSweep;
    final zoneColor = complete ? _readyColor : _targetColor;
    // Butt caps, not round: this has to read as a machined gate with hard
    // edges, not a soft blob smeared across the end of the channel.
    canvas.drawArc(
      rect,
      zoneStart,
      zoneSweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth - 14
        ..strokeCap = StrokeCap.butt
        ..color = zoneColor.withAlpha(complete ? 80 : 26),
    );
    final gatePaint = Paint()
      ..color = zoneColor.withAlpha(complete ? 200 : 95)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    for (final a in [zoneStart, endAngle]) {
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (innerEdge + 5),
        center + dir * (outerEdge - 5),
        gatePaint,
      );
    }

    // ── machined detent ticks, hidden once the fill passes them ─────────
    const int tickCount = 60;
    final tickPaint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i <= tickCount; i++) {
      final t = i / tickCount;
      if (t <= progress) continue;
      final a = startAngle + requiredSweep * t;
      final dir = Offset(math.cos(a), math.sin(a));
      final major = i % 5 == 0;
      tickPaint
        ..color = Colors.white.withAlpha(major ? 42 : 20)
        ..strokeWidth = major ? 1.8 : 1.2;
      final len = trackWidth * (major ? 0.30 : 0.17);
      canvas.drawLine(
        center + dir * (outerEdge - 4),
        center + dir * (outerEdge - 4 - len),
        tickPaint,
      );
    }

    // ── energised fill left behind the handle ───────────────────────────
    if (progress > 0.001) {
      canvas.drawArc(
        rect,
        startAngle,
        filledSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = trackWidth - 8
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: 0.0,
            endAngle: requiredSweep,
            colors: const [Color(0xFF5C0B0B), Color(0xFF9E1B17), _eStopColor],
            stops: const [0.0, 0.55, 1.0],
            transform: GradientRotation(startAngle),
          ).createShader(rect),
      );

      // Hot inner edge so the filled run reads as live, not just coloured.
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerEdge + 4),
        startAngle,
        filledSweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = (complete ? _readyColor : _eStopColor).withAlpha(140),
      );
    }

    // ── start detent notch ──────────────────────────────────────────────
    final startDir = Offset(math.cos(startAngle), math.sin(startAngle));
    canvas.drawLine(
      center + startDir * (innerEdge + 4),
      center + startDir * (outerEdge - 4),
      Paint()
        ..color = Colors.white.withAlpha(34)
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round,
    );

    // ── direction chevrons running ahead of the handle ──────────────────
    final handleAngle = startAngle + filledSweep;
    const alphas = [110, 72, 40];
    for (int i = 0; i < 3; i++) {
      final a = handleAngle + 0.22 + i * 0.13;
      if (a > endAngle - 0.05) break;
      _drawChevron(canvas, center, a, trackWidth * 0.17, alphas[i]);
    }

    if (complete) {
      canvas.drawCircle(
        center,
        outerEdge + 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = _readyColor.withAlpha(110),
      );
    }
  }

  void _drawChevron(
    Canvas canvas,
    Offset center,
    double angle,
    double s,
    int alpha,
  ) {
    final p = center + Offset(math.cos(angle), math.sin(angle)) * trackRadius;
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.rotate(angle + math.pi / 2);
    canvas.drawPath(
      Path()
        ..moveTo(-s * 0.55, -s)
        ..lineTo(s * 0.55, 0)
        ..lineTo(-s * 0.55, s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.0, s * 0.34)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white.withAlpha(alpha),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ResetTrackPainter old) =>
      old.progress != progress ||
      old.trackRadius != trackRadius ||
      old.trackWidth != trackWidth;
}
