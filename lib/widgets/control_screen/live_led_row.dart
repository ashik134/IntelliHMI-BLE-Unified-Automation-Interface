import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

enum LedIndicatorState { unmapped, pending, confirmedOn, confirmedOff }

class LedSpec {
  const LedSpec({
    required this.label,
    required this.commanded,
    required this.confirmed,
    required this.color,
    this.mapped = true,
    this.inactiveColor,
    this.pulseWhenInactive = false,
    this.pulseDuration = const Duration(milliseconds: 1000),
    this.pin,
  });

  final String label;

  final bool commanded;

  final bool confirmed;

  final bool mapped;

  final Color color;

  final Color? inactiveColor;

  final bool pulseWhenInactive;
  final Duration pulseDuration;
  final String? pin;

  LedIndicatorState get indicatorState {
    if (!mapped) return LedIndicatorState.unmapped;
    if (commanded != confirmed) return LedIndicatorState.pending;
    return commanded
        ? LedIndicatorState.confirmedOn
        : LedIndicatorState.confirmedOff;
  }

  bool get isPending => indicatorState == LedIndicatorState.pending;

  bool get showsReadyPulse =>
      indicatorState == LedIndicatorState.confirmedOff &&
      pulseWhenInactive &&
      inactiveColor != null;
}

class LiveLedRow extends StatelessWidget {
  const LiveLedRow({super.key, required this.leds});

  final List<LedSpec> leds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final led in leds) _LedIndicator(spec: led)],
      ),
    );
  }
}

class _LedIndicator extends StatefulWidget {
  const _LedIndicator({required this.spec});

  final LedSpec spec;

  @override
  State<_LedIndicator> createState() => _LedIndicatorState();
}

class _LedIndicatorState extends State<_LedIndicator>
    with TickerProviderStateMixin {
  static const double _ringDiameter = 15.0;
  static const double _ringStroke = 1.6;
  static const double _coreDiameter = 6.5;

  static const Duration _pendingBlinkDuration = Duration(milliseconds: 460);

  late final AnimationController _blinkCtrl;
  late final CurvedAnimation _blink;

  late final AnimationController _pulseCtrl;
  late final CurvedAnimation _pulse;

  LedSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: _pendingBlinkDuration,
    );
    _blink = CurvedAnimation(parent: _blinkCtrl, curve: Curves.easeInOut);
    _pulseCtrl = AnimationController(vsync: this, duration: spec.pulseDuration);
    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOutCubic);
    _syncAnimations();
  }

  @override
  void didUpdateWidget(covariant _LedIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.pulseDuration != spec.pulseDuration) {
      _pulseCtrl.duration = spec.pulseDuration;
    }
    _syncAnimations();
  }

  @override
  void dispose() {
    _blink.dispose();
    _blinkCtrl.dispose();
    _pulse.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _syncAnimations() {
    _run(_blinkCtrl, spec.isPending);
    _run(_pulseCtrl, spec.showsReadyPulse);
  }

  void _run(AnimationController controller, bool shouldAnimate) {
    if (shouldAnimate) {
      if (!controller.isAnimating) controller.repeat(reverse: true);
      return;
    }
    controller.stop();
    controller.value = 0.0;
  }

  // ── Ring (commanded) ──────────────────────────────────────────────────────

  Color _ringColor(double blinkValue) {
    switch (spec.indicatorState) {
      case LedIndicatorState.unmapped:
        return AppColors.ledUnmappedGrey;
      case LedIndicatorState.pending:
        return Color.lerp(
          AppColors.ledPendingAmberDim,
          AppColors.ledPendingAmber,
          blinkValue,
        )!;
      case LedIndicatorState.confirmedOn:
        return spec.color;
      case LedIndicatorState.confirmedOff:
        final ready = spec.inactiveColor;
        return ready != null
            ? ready.withAlpha(90)
            : const Color.fromARGB(255, 10, 109, 223);
    }
  }

  List<BoxShadow> _ringShadows(double blinkValue) {
    switch (spec.indicatorState) {
      case LedIndicatorState.unmapped:
      case LedIndicatorState.confirmedOff:
        return const <BoxShadow>[];
      case LedIndicatorState.pending:
        return [
          BoxShadow(
            color: AppColors.ledPendingAmber.withAlpha(
              (30 + (70 * blinkValue)).round(),
            ),
            blurRadius: 4 + (6 * blinkValue),
            spreadRadius: 0.5 * blinkValue,
          ),
        ];
      case LedIndicatorState.confirmedOn:
        return [BoxShadow(color: spec.color.withAlpha(64), blurRadius: 5)];
    }
  }

  // ── Core (confirmed) ──────────────────────────────────────────────────────

  Color _coreColor(double pulseValue) {
    // Pending is represented by the blinking amber ring alone. Suppress both
    // the last PLC-reported colour and the E-STOP ready colour until the app
    // command and processed-command echo agree again.
    if (spec.isPending) return AppColors.idleColor;

    if (spec.confirmed) return spec.color;

    final ready = spec.inactiveColor;
    if (ready != null && spec.pulseWhenInactive) {
      return Color.lerp(ready.withAlpha(185), ready, pulseValue)!;
    }

    return AppColors.idleColor;
  }

  List<BoxShadow> _coreShadows({
    required double confirmedValue,
    required double pulseValue,
  }) {
    if (spec.isPending) return const <BoxShadow>[];

    if (spec.confirmed) {
      return [
        BoxShadow(
          color: spec.color.withAlpha(153),
          blurRadius: 4 * confirmedValue,
          spreadRadius: 1,
        ),
      ];
    }

    if (!spec.showsReadyPulse) return const <BoxShadow>[];

    final ready = spec.inactiveColor!;
    return [
      BoxShadow(
        color: ready.withAlpha((60 + (70 * pulseValue)).round()),
        blurRadius: 4 + (6 * pulseValue),
        spreadRadius: 0.5 + (1.0 * pulseValue),
      ),
    ];
  }

  // ── Label + description ───────────────────────────────────────────────────

  Color get _labelColor {
    switch (spec.indicatorState) {
      case LedIndicatorState.unmapped:
        // An unmapped channel the PLC is nonetheless driving keeps the live
        // colour — a lit core must never be muted down to "spare channel".
        return spec.confirmed ? spec.color : AppColors.ledUnmappedGrey;
      case LedIndicatorState.pending:
        return AppColors.ledPendingAmber;
      case LedIndicatorState.confirmedOn:
        return spec.color;
      case LedIndicatorState.confirmedOff:
        if (spec.showsReadyPulse) return spec.inactiveColor!.withAlpha(210);
        return AppColors.darkTextMuted;
    }
  }

  /// Spelled out rather than colour-coded alone, so the four states stay
  /// readable to an operator who cannot rely on the amber/grey distinction.
  String get _stateDescription {
    final channel = spec.pin == null || spec.pin == spec.label
        ? spec.label
        : '${spec.label} (${spec.pin})';
    final reported = spec.confirmed ? 'ON' : 'OFF';
    switch (spec.indicatorState) {
      case LedIndicatorState.unmapped:
        return '$channel — unmapped: no control in this layout drives it. '
            'PLC reports $reported.';
      case LedIndicatorState.pending:
        return '$channel — pending: commanded '
            '${spec.commanded ? 'ON' : 'OFF'}, PLC still reports $reported.';
      case LedIndicatorState.confirmedOn:
      case LedIndicatorState.confirmedOff:
        return '$channel — $reported, confirmed by PLC.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _stateDescription,
      child: Tooltip(
        message: _stateDescription,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: spec.confirmed ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 300),
              builder: (context, confirmedValue, _) {
                return AnimatedBuilder(
                  animation: Listenable.merge([_blinkCtrl, _pulseCtrl]),
                  builder: (context, _) {
                    final blinkValue = spec.isPending ? _blink.value : 0.0;
                    final pulseValue = spec.showsReadyPulse
                        ? _pulse.value
                        : 0.0;

                    return Container(
                      width: _ringDiameter,
                      height: _ringDiameter,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: _ringShadows(blinkValue),
                      ),
                      child: CustomPaint(
                        key: ValueKey('led-ring-${spec.label}'),
                        painter: LedRingPainter(
                          color: _ringColor(blinkValue),
                          strokeWidth: _ringStroke,
                          dashed:
                              spec.indicatorState == LedIndicatorState.unmapped,
                        ),
                        child: Center(
                          child: Container(
                            key: ValueKey('led-core-${spec.label}'),
                            width: _coreDiameter,
                            height: _coreDiameter,
                            decoration: BoxDecoration(
                              color: _coreColor(pulseValue),
                              shape: BoxShape.circle,
                              boxShadow: _coreShadows(
                                confirmedValue: confirmedValue,
                                pulseValue: pulseValue,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 3),
            Text(
              spec.label,
              style: TextStyle(
                fontSize: 8,
                color: _labelColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws the commanded-state ring: a solid circle, or an evenly-dashed one
/// for an unmapped channel. Public so tests can assert the ring's colour and
/// dash pattern without golden files.
class LedRingPainter extends CustomPainter {
  const LedRingPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashed,
  });

  final Color color;
  final double strokeWidth;
  final bool dashed;

  /// Dash/gap arc lengths in logical pixels, chosen so a ~15px ring closes on
  /// a whole number of segments and reads as dashed rather than dotted.
  static const double _dashLength = 2.6;
  static const double _gapLength = 2.2;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    if (!dashed) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final rect = Rect.fromCircle(center: center, radius: radius);
    final circumference = 2 * math.pi * radius;
    const segment = _dashLength + _gapLength;
    // Round to whole segments and rescale, so the dash pattern always meets
    // itself cleanly instead of leaving a ragged joint at 3 o'clock.
    final segmentCount = math.max(4, (circumference / segment).round());
    final sweepPerSegment = (2 * math.pi) / segmentCount;
    final dashSweep = sweepPerSegment * (_dashLength / segment);

    for (var i = 0; i < segmentCount; i++) {
      canvas.drawArc(rect, i * sweepPerSegment, dashSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(LedRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.dashed != dashed;
}
