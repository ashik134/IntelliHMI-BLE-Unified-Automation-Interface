import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/potentiometer_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/control_button_visuals.dart';

// ─────────────────────────────────────────────────────────────────────────────
// IndustrialCenterOffPotentiometerControl
//
// A second rotary-knob instrument alongside IndustrialPotentiometerControl
// (potentiometer_control.dart, deliberately left untouched) — same
// PotentiometerConfig, same analog value/BLE pipeline (see
// analog_wire_config.dart's resolveAnalogWireConfig), different physical
// read: rest position is straight up at PotentiometerConfig.neutralValue,
// with a magnetic center detent instead of the plain potentiometer's
// spring-loaded-to-one-end feel. "Retained" vs "Spring Return" is the exact
// same PotentiometerConfig.springReturnEnabled flag the plain potentiometer
// already exposes — this control just starts and detents at the middle of
// travel instead of treating neutralValue as an incidental release point.
// ─────────────────────────────────────────────────────────────────────────────

// Symmetric ~200 degree sweep centered on straight-up, matching the
// reference image's arc — deliberately narrower and differently anchored
// than the plain potentiometer's 270 degree sweep opening at the bottom, so
// the dial itself reads as "centered" rather than "one-ended" at a glance.
const double _kCenterAngle = math.pi * 1.5;
const double _kHalfSweepAngle = math.pi * (100 / 180);
const double _kStartAngle = _kCenterAngle - _kHalfSweepAngle;
const double _kSweepAngle = _kHalfSweepAngle * 2;

// Same mechanical "give" on release/settle as IndustrialPotentiometerControl,
// kept as its own copy so this file has no dependency on that one's
// internals (see file doc comment — the two controls are intentionally
// independent implementations).
const SpringDescription _kKnobSpring = SpringDescription(
  mass: 0.5,
  stiffness: 280.0,
  damping: 20.0,
);

/// Half-width, in normalized [0,1] track fraction, of the magnetic center
/// detent band around neutralValue. Inside this band a drag snaps exactly
/// onto neutralValue instead of tracking the raw angle, and crossing either
/// edge fires a haptic tick — the tactile "catch" a real center-off rotary
/// switch has, layered on top of drag tracking without slowing it down
/// (gain stays 1:1 outside the band, so the finger is never lagged — see
/// IndustrialPotentiometerControl's own doc comment on _displayNormalized
/// for why 1:1 tracking during drag matters).
const double _kDetentBandHalfWidth = 0.035;

/// Minimum leftover width (beyond the dial's own square footprint) before
/// the flanking min/max end labels are worth showing at all — below this a
/// label would be a cramped, likely-truncated sliver, so the dial renders
/// alone instead. Text still ellipsizes gracefully above this threshold for
/// unusually long formatted values (e.g. a wide custom min/max range).
const double _kMinLabelGutter = 48.0;

class IndustrialCenterOffPotentiometerControl extends StatefulWidget {
  const IndustrialCenterOffPotentiometerControl({
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
  State<IndustrialCenterOffPotentiometerControl> createState() =>
      _IndustrialCenterOffPotentiometerControlState();
}

class _IndustrialCenterOffPotentiometerControlState
    extends State<IndustrialCenterOffPotentiometerControl>
    with TickerProviderStateMixin {
  late double _value;

  /// Rendered pointer/arc position in [0, 1] — see
  /// IndustrialPotentiometerControl._displayNormalized, same contract: 1:1
  /// with the live drag, spring-eased for every other transition.
  late double _displayNormalized;

  double? _dragStartAngle;
  double? _dragLastAngle;
  double _dragAccumulatedAngle = 0.0;
  double? _dragStartValue;
  bool _isDragging = false;

  /// Whether the live drag position is currently inside the center detent
  /// band — tracked purely so the crossing haptic fires exactly once per
  /// transition rather than once per pan-update frame while inside it.
  bool _inDetentBand = false;

  late final AnimationController _settleCtrl;
  bool _settleDrivesValue = false;
  double? _settleHapticTarget;
  bool _settleHapticFired = false;

  late final AnimationController _pressCtrl;

  PotentiometerConfig get _config => widget.config.normalized();

  double get _neutralNormalized =>
      _config.normalizedValueFor(_config.neutralValue);

  @override
  void initState() {
    super.initState();
    _value = _config.defaultValue;
    _displayNormalized = _config.normalizedValueFor(_value);
    _inDetentBand = _isInDetentBand(_displayNormalized);
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
  void didUpdateWidget(
    covariant IndustrialCenterOffPotentiometerControl oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      _settleCtrl.stop();
      _value = _config.clampAndSnap(_value);
      _displayNormalized = _config.normalizedValueFor(_value);
      _inDetentBand = _isInDetentBand(_displayNormalized);
    }
    if (!widget.enabled && oldWidget.enabled) {
      _settleCtrl.stop();
      _pressCtrl.reverse();
      _resetDrag();
    }
  }

  bool _isInDetentBand(double normalized) =>
      (normalized - _neutralNormalized).abs() <= _kDetentBandHalfWidth;

  /// Snaps [normalized] onto the exact neutral position when it falls inside
  /// the detent band, firing a haptic tick on every band-boundary crossing
  /// (entering OR leaving — "reaching" and "crossing" the center position
  /// are the same transition from opposite sides).
  double _applyDetent(double normalized) {
    final inBand = _isInDetentBand(normalized);
    if (inBand != _inDetentBand) {
      _inDetentBand = inBand;
      HapticFeedback.mediumImpact();
    }
    return inBand ? _neutralNormalized : normalized;
  }

  void _setValue(double next, {bool haptic = false}) {
    final snapped = _config.clampAndSnap(next);
    final rawNormalized = _config.normalizedValueFor(snapped);
    final detentedNormalized = _applyDetent(rawNormalized);
    final finalValue = _inDetentBand
        ? _config.clampAndSnap(_config.neutralValue)
        : snapped;
    if (finalValue == _value) {
      if (_displayNormalized != detentedNormalized) {
        setState(() => _displayNormalized = detentedNormalized);
      }
      return;
    }
    setState(() {
      _value = finalValue;
      _displayNormalized = detentedNormalized;
    });
    if (haptic) HapticFeedback.selectionClick();
    widget.onChanged(finalValue);
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

  /// Springs the knob back to neutral on release — only armed when the
  /// operator has opted into spring-return mode ("Spring Return" behavior;
  /// "Retained" leaves [_config.springReturnEnabled] false and the knob
  /// simply stays wherever it was released, identical in spirit to
  /// IndustrialPotentiometerControl's own spring-return).
  void _springReturnToNeutral() {
    final target = _neutralNormalized;
    _settleDrivesValue = true;
    _settleHapticTarget = target;
    _settleHapticFired = false;
    _inDetentBand = true;
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
          math.cos(indicatorAngle) * knobRadius * 0.85,
          math.sin(indicatorAngle) * knobRadius * 0.85,
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
    final targetNormalized = _config.normalizedValueFor(target);
    _inDetentBand = _isInDetentBand(targetNormalized);
    setState(() => _value = target);
    HapticFeedback.selectionClick();
    widget.onChanged(target);
    _animateDisplayTo(targetNormalized);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final normalized = _displayNormalized.clamp(0.0, 1.0).toDouble();
    final valueText = config.formatValue(_value);
    final atCenter = _isInDetentBand(normalized);
    final showLabels = config.showValue;
    final trimmedLabel = widget.label.trim();

    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: widget.label,
      value: atCenter ? 'Centre — $valueText' : valueText,
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

            // Same reasoning as IndustrialPotentiometerControl's own footer
            // gate: only reserve space for the label/icon row when there's
            // genuinely room for it alongside the dial's 72px usability
            // floor — otherwise it doesn't render rather than overflowing.
            const footerHeight = 6.0 + ControlButtonVisualMetrics.rowHeight;
            final wantsFooter = trimmedLabel.isNotEmpty || widget.icon != null;
            final showFooter = wantsFooter && maxH >= 72.0 + footerHeight;
            final dialAreaHeight = showFooter ? maxH - footerHeight : maxH;

            final dialSide = math.max(72.0, math.min(maxW, dialAreaHeight));
            final gutter = showLabels ? (maxW - dialSide) / 2 : 0.0;
            final hasLabelRoom = gutter >= _kMinLabelGutter;

            final dial = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: widget.enabled
                  ? (details) => _handlePanStart(details, Size(dialSide, dialSide))
                  : null,
              onPanUpdate: widget.enabled
                  ? (details) => _handlePanUpdate(details, Size(dialSide, dialSide))
                  : null,
              onPanEnd: widget.enabled ? (_) => _handlePanEnd() : null,
              onPanCancel: widget.enabled ? _handlePanEnd : null,
              child: SizedBox(
                width: dialSide,
                height: dialSide,
                child: CustomPaint(
                  painter: _CenterOffPotentiometerPainter(
                    normalizedValue: normalized,
                    neutralNormalized: _neutralNormalized,
                    atCenter: atCenter,
                    valueText: valueText,
                    showValue: config.showValue,
                    enabled: widget.enabled,
                    activeColor: widget.activeColor,
                    activeColorLight: widget.activeColorLight,
                    isDragging: _isDragging,
                    pressAmount: _pressCtrl.value,
                  ),
                ),
              ),
            );

            final Widget dialArea = !hasLabelRoom
                ? SizedBox(
                    width: maxW,
                    height: dialAreaHeight,
                    child: Center(child: dial),
                  )
                : SizedBox(
                    width: maxW,
                    height: dialAreaHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: gutter,
                          child: _EndLabel(
                            text: config.formatValue(config.minValue),
                            color: AppColors.darkInfo,
                            alignRight: true,
                            dialSide: dialSide,
                          ),
                        ),
                        dial,
                        SizedBox(
                          width: gutter,
                          child: _EndLabel(
                            text: config.formatValue(config.maxValue),
                            color: AppColors.darkSuccess,
                            alignRight: false,
                            dialSide: dialSide,
                          ),
                        ),
                      ],
                    ),
                  );

            if (!showFooter) return dialArea;

            return SizedBox(
              width: maxW,
              height: maxH,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  dialArea,
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

/// A flanking min/max end label (echoing the reference image's "A2"/"A1"
/// side labels) — plain widget-tree text rather than canvas-drawn, so it can
/// live outside the dial's own square footprint without any custom-paint
/// overflow risk. Shown only when there is real leftover width to spend
/// (see [_kMinLabelGutter]); the dial's own size never shrinks to make room.
class _EndLabel extends StatelessWidget {
  const _EndLabel({
    required this.text,
    required this.color,
    required this.alignRight,
    required this.dialSide,
  });

  final String text;
  final Color color;

  /// True for the left-hand (min) label, whose text should hug the dial —
  /// i.e. sit against the label column's right edge.
  final bool alignRight;
  final double dialSide;

  @override
  Widget build(BuildContext context) {
    final fontSize = (dialSide * 0.075).clamp(8.0, 12.0).toDouble();
    return Align(
      alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _CenterOffPotentiometerPainter extends CustomPainter {
  const _CenterOffPotentiometerPainter({
    required this.normalizedValue,
    required this.neutralNormalized,
    required this.atCenter,
    required this.valueText,
    required this.showValue,
    required this.enabled,
    required this.activeColor,
    required this.activeColorLight,
    required this.isDragging,
    required this.pressAmount,
  });

  final double normalizedValue;
  final double neutralNormalized;
  final bool atCenter;
  final String valueText;
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

    if (showValue) _paintValueText(canvas, center, side);
  }

  void _drawHousingShadow(Canvas canvas, Offset center, double side, double outerR) {
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

  /// Fine machined-edge knurling on the housing rim — purely decorative
  /// texture matching IndustrialPotentiometerControl's "metal" read.
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

  /// Minor ticks spread evenly across the sweep, plus one always-emphasized
  /// tick at the exact neutral angle — the "clear center detent" the brief
  /// calls for, drawn regardless of spring-return mode (unlike the plain
  /// potentiometer's neutral tick, which only appears when spring-return is
  /// on: here the detent is a physical feature of the dial itself, not
  /// conditional on release behavior).
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
      // Neutral light-gray dashes throughout — matching the reference's
      // monochrome scale, where color is reserved for the flanking end
      // labels rather than the dial's own markings.
      tickPaint.color = Colors.white.withAlpha(
        enabled ? (isMajor ? 158 : 68) : 34,
      );
      canvas.drawLine(
        center + Offset(math.cos(angle) * startR, math.sin(angle) * startR),
        center + Offset(math.cos(angle) * endR, math.sin(angle) * endR),
        tickPaint,
      );
    }

    final neutralAngle = _kStartAngle + _kSweepAngle * neutralNormalized;
    final startR = radius * 0.76;
    final endR = radius * 0.96;
    canvas.drawLine(
      center + Offset(math.cos(neutralAngle) * startR, math.sin(neutralAngle) * startR),
      center + Offset(math.cos(neutralAngle) * endR, math.sin(neutralAngle) * endR),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.6, side * 0.018)
        ..color = Colors.white.withAlpha(
          enabled ? (atCenter ? 235 : 190) : 100,
        ),
    );
  }

  /// Background sweep plus a "deviation from center" fill drawn from the
  /// neutral angle out to the current position, instead of the plain
  /// potentiometer's from-the-start fill — the natural read for a
  /// center-off gauge, where what matters is how far off-center you are.
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

    final neutralAngle = _kStartAngle + _kSweepAngle * neutralNormalized;
    final currentAngle = _kStartAngle + _kSweepAngle * normalizedValue;
    final fillSweep = currentAngle - neutralAngle;
    if (fillSweep.abs() > 0.002) {
      canvas.drawArc(
        rect,
        neutralAngle,
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

  void _drawKnobShadow(Canvas canvas, Offset center, double side, double knobR) {
    canvas.drawCircle(
      center + Offset(0, side * (0.028 - 0.014 * pressAmount)),
      knobR,
      Paint()
        ..color = Colors.black.withAlpha(150)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 - 2.5 * pressAmount),
    );
  }

  /// Flat, dark slate face — deliberately NOT the plain potentiometer's
  /// brushed-light-metal gradient (see IndustrialPotentiometerControl's own
  /// _drawKnobBody), matching the reference image's darker, more restrained
  /// knob read.
  void _drawKnobBody(Canvas canvas, Offset center, double knobR) {
    final knobRect = Rect.fromCircle(center: center, radius: knobR);
    canvas.drawCircle(
      center,
      knobR,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.35, -0.45),
          radius: 1.15,
          colors: [Color(0xFF3C4C5C), Color(0xFF232E39), Color(0xFF12181F)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(knobRect),
    );
    canvas.drawCircle(
      center,
      knobR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, knobR * 0.045)
        ..color = Colors.black.withAlpha(130),
    );
    canvas.drawCircle(
      center,
      knobR - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = Colors.white.withAlpha(enabled ? 30 : 12),
    );
  }

  /// A simple rounded indicator bar — not a triangular needle — matching the
  /// reference's plain, minimal pointer. Neutral light-gray rather than the
  /// active/accent color: in this design color is reserved for the flanking
  /// end labels, so the pointer itself reads the same at every position.
  void _drawPointer(Canvas canvas, Offset center, double knobR) {
    final angle = _kStartAngle + _kSweepAngle * normalizedValue;
    final dir = Offset(math.cos(angle), math.sin(angle));

    // Short and floating up near the rim — nowhere close to center — so the
    // whole lower half of the face stays clear for the CENTRE/value text,
    // matching the reference (its bar never approaches the readout at all).
    final inner = center + dir * knobR * 0.52;
    final outer = center + dir * knobR * 0.85;
    final barColor = Colors.white.withAlpha(enabled ? 222 : 110);
    final barWidth = math.max(2.0, knobR * 0.085);

    if (isDragging && enabled) {
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = barWidth + 3
          ..color = barColor.withAlpha(90)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    canvas.drawLine(
      inner,
      outer,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = barWidth
        ..color = barColor,
    );
  }

  /// Value readout, with a small "CENTRE" caption above it that appears only
  /// while the knob sits in the magnetic detent band — mirroring the
  /// reference image's "CENTRE / 0%" read at rest, and simply showing the
  /// bare value everywhere else off-center.
  void _paintValueText(Canvas canvas, Offset center, double side) {
    final valueStyle = TextStyle(
      color: AppColors.darkText.withAlpha(enabled ? 235 : 110),
      fontSize: (side * 0.095).clamp(10.0, 18.0).toDouble(),
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final valueTP = TextPainter(
      text: TextSpan(text: valueText, style: valueStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: side * 0.46);
    final valueTop = center.dy - side * 0.09;

    if (atCenter) {
      // Deliberately compact — this line only has to clear the needle's
      // (already-widened, see _drawPointer) base moat, not compete with the
      // value line below for size.
      final captionStyle = TextStyle(
        color: AppColors.darkTextMuted.withAlpha(enabled ? 255 : 130),
        fontSize: (side * 0.040).clamp(6.5, 9.0).toDouble(),
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
      );
      final captionTP = TextPainter(
        text: TextSpan(text: 'CENTRE', style: captionStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: side * 0.5);
      final captionTop = valueTop - captionTP.height - side * 0.004;
      captionTP.paint(
        canvas,
        Offset(center.dx - captionTP.width / 2, captionTop),
      );
    }

    valueTP.paint(canvas, Offset(center.dx - valueTP.width / 2, valueTop));
  }

  @override
  bool shouldRepaint(covariant _CenterOffPotentiometerPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.neutralNormalized != neutralNormalized ||
        oldDelegate.atCenter != atCenter ||
        oldDelegate.valueText != valueText ||
        oldDelegate.showValue != showValue ||
        oldDelegate.enabled != enabled ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.activeColorLight != activeColorLight ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.pressAmount != pressAmount;
  }
}
