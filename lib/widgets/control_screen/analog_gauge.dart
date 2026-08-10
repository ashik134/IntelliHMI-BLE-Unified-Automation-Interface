import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalogGauge / AnalogGaugeCard
//
// Industrial radial dial for the live analog channels the PLC pushes over the
// analog characteristic (BLEConstants.analogCharUuid — payload "A1:<v>,A2:<v>",
// parsed in BleService and surfaced as CraneController.a1 / .a2).
//
// The dial is purely an indicator: it never writes back to the PLC and holds no
// state of its own beyond the value sweep animation, so it is safe to drop into
// any read-only surface. Everything is painted from the shortest side of the
// box it is given, so one widget covers the compact phone strip and the larger
// tablet/landscape layouts without per-screen tuning.
// ─────────────────────────────────────────────────────────────────────────────

/// Dial geometry: a 270° scale opening at the bottom, matching the arc used by
/// [IndustrialPotentiometerControl] so both read as the same instrument family.
const double _kStartAngle = math.pi * 0.75; // 135° — lower left
const double _kSweepAngle = math.pi * 1.5; // 270° — ends lower right

/// Operating band the current reading falls into. Drives the arc tip colour,
/// tick tinting, readout colour and the card's status pip.
enum GaugeZone {
  normal,
  warning,
  critical;

  /// Resolves the band for a 0..1 [fraction] of full scale.
  static GaugeZone forFraction(
    double fraction, {
    required double warningFraction,
    required double criticalFraction,
  }) {
    if (fraction >= criticalFraction) return GaugeZone.critical;
    if (fraction >= warningFraction) return GaugeZone.warning;
    return GaugeZone.normal;
  }

  String get statusLabel => switch (this) {
    GaugeZone.normal => 'NOMINAL',
    GaugeZone.warning => 'HIGH',
    GaugeZone.critical => 'CRITICAL',
  };
}

/// What the dial prints in its centre.
enum AnalogGaugeReadout {
  /// The formatted reading, with the unit (or percent of full scale when no
  /// unit is configured) underneath.
  value,

  /// Percent of full scale only — for layouts that already print the reading
  /// next to the dial.
  percent,

  /// Nothing; the arc alone carries the value.
  none,
}

/// Bare radial dial — no panel chrome. Fills the largest centred square that
/// fits its constraints. Use [AnalogGaugeCard] for the framed HMI presentation.
class AnalogGauge extends StatelessWidget {
  const AnalogGauge({
    super.key,
    required this.value,
    required this.color,
    required this.colorLight,
    this.minValue = 0,
    this.maxValue = defaultFullScale,
    this.unit = '',
    this.warningFraction = 0.75,
    this.criticalFraction = 0.9,
    this.readout = AnalogGaugeReadout.value,
    this.animationDuration = const Duration(milliseconds: 260),
    this.semanticLabel,
  });

  /// Full-scale reading assumed for the PLC's analog channels — the firmware
  /// reports raw 12-bit ADC counts. Pass [maxValue] explicitly if a channel is
  /// scaled into engineering units before it reaches the app.
  static const double defaultFullScale = 4095;

  /// Live reading, in the same units as [minValue] / [maxValue]. Values outside
  /// the range are clamped for the sweep but still shown verbatim in the
  /// readout, so an over-range sensor is never silently hidden.
  final double value;

  /// Channel identity colour — the base of the value arc.
  final Color color;

  /// Lighter partner of [color], used for the arc's leading edge and glow.
  final Color colorLight;

  final double minValue;
  final double maxValue;

  /// Engineering unit shown under the readout. When empty the dial shows the
  /// percentage of full scale instead.
  final String unit;

  /// Fraction of full scale at which the dial switches to the warning colour.
  final double warningFraction;

  /// Fraction of full scale at which the dial switches to the critical colour.
  final double criticalFraction;

  /// What the centre of the dial prints.
  final AnalogGaugeReadout readout;

  final Duration animationDuration;
  final String? semanticLabel;

  /// Clamped 0..1 position of [value] on the scale.
  static double fractionFor(
    double value, {
    double minValue = 0,
    double maxValue = defaultFullScale,
  }) {
    final span = maxValue - minValue;
    if (!span.isFinite || span <= 0 || !value.isFinite) return 0;
    return ((value - minValue) / span).clamp(0.0, 1.0).toDouble();
  }

  /// Readout formatting: whole numbers for wide ranges (raw ADC counts), one
  /// decimal for narrow engineering ranges where the digit still carries info.
  static String formatValue(double value, {required double span}) {
    if (!value.isFinite) return '--';
    return span >= 50 ? value.round().toString() : value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final span = maxValue - minValue;
    final valueText = formatValue(value, span: span);
    // The dial paints its text itself, so it has to pick the app's font up
    // explicitly instead of inheriting it through the widget tree.
    final fontFamily = DefaultTextStyle.of(context).style.fontFamily;

    return Semantics(
      label: semanticLabel,
      value: unit.isEmpty ? valueText : '$valueText $unit',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 120.0;
          final maxH = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : 120.0;
          final side = math.min(maxW, maxH);
          if (side <= 0) return const SizedBox.shrink();

          return Center(
            child: SizedBox(
              width: side,
              height: side,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: value),
                duration: animationDuration,
                curve: Curves.easeOutCubic,
                builder: (context, animatedValue, _) {
                  final animatedFraction = fractionFor(
                    animatedValue,
                    minValue: minValue,
                    maxValue: maxValue,
                  );
                  final percentText = '${(animatedFraction * 100).round()}%';
                  return CustomPaint(
                    painter: _AnalogGaugePainter(
                      fraction: animatedFraction,
                      // The digits track the sweep so the dial reads as one
                      // instrument, but they settle on the true reading.
                      valueText: switch (readout) {
                        AnalogGaugeReadout.value => formatValue(
                          animatedValue,
                          span: span,
                        ),
                        AnalogGaugeReadout.percent => percentText,
                        AnalogGaugeReadout.none => '',
                      },
                      subText: switch (readout) {
                        AnalogGaugeReadout.value =>
                          unit.isEmpty ? percentText : unit.toUpperCase(),
                        AnalogGaugeReadout.percent ||
                        AnalogGaugeReadout.none => '',
                      },
                      // Percent is supporting context for a reading printed
                      // elsewhere, so it stays visibly secondary.
                      valueFontFactor: readout == AnalogGaugeReadout.percent
                          ? 0.135
                          : 0.20,
                      fontFamily: fontFamily,
                      zone: GaugeZone.forFraction(
                        animatedFraction,
                        warningFraction: warningFraction,
                        criticalFraction: criticalFraction,
                      ),
                      color: color,
                      colorLight: colorLight,
                      warningFraction: warningFraction.clamp(0.0, 1.0),
                      criticalFraction: criticalFraction.clamp(0.0, 1.0),
                    ),
                    child: const SizedBox.expand(),
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

/// Framed dial: panel chrome, channel tag, label and live status pip around an
/// [AnalogGauge]. This is what the control screen's sensor strip renders.
///
/// Two compositions, picked from the box the card is given:
///  * **faceplate** — dial beside a readout column (tag, name, reading, status
///    and a headroom bar). Used whenever the leftover width beside a
///    square dial is worth printing on.
///  * **stacked** — header row above a centred dial that carries the reading
///    itself. The fallback for narrow cards.
class AnalogGaugeCard extends StatelessWidget {
  const AnalogGaugeCard({
    super.key,
    required this.tag,
    required this.label,
    required this.value,
    required this.color,
    required this.colorLight,
    this.minValue = 0,
    this.maxValue = AnalogGauge.defaultFullScale,
    this.unit = '',
    this.warningFraction = 0.75,
    this.criticalFraction = 0.9,
  });

  /// Short channel id (`A1`, `A2`) shown in the header chip.
  final String tag;

  /// Operator-facing channel name (`Load 1`).
  final String label;

  final double value;
  final Color color;
  final Color colorLight;
  final double minValue;
  final double maxValue;
  final String unit;
  final double warningFraction;
  final double criticalFraction;

  /// Below this card height the header is dropped so the dial keeps a usable
  /// diameter instead of both fighting for the same pixels.
  static const double _kHeaderCutoffHeight = 84;

  /// Narrowest readout column worth printing beside the dial. Under this the
  /// card falls back to the stacked composition. Tuned so a 360dp phone — the
  /// tightest layout that still shows the sensor strip — keeps the faceplate.
  static const double _kMinReadoutWidth = 48;

  static const EdgeInsets _kPadding = EdgeInsets.fromLTRB(8, 6, 8, 6);
  static const double _kDialGap = 8;

  @override
  Widget build(BuildContext context) {
    final fraction = AnalogGauge.fractionFor(
      value,
      minValue: minValue,
      maxValue: maxValue,
    );
    final zone = GaugeZone.forFraction(
      fraction,
      warningFraction: warningFraction,
      criticalFraction: criticalFraction,
    );
    final zoneColor = _zoneColor(zone, colorLight);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 110.0;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 180.0;
        final contentHeight = height - _kPadding.vertical;
        final readoutWidth =
            width - _kPadding.horizontal - contentHeight - _kDialGap;
        final faceplate = readoutWidth >= _kMinReadoutWidth;

        final dial = AnalogGauge(
          value: value,
          color: color,
          colorLight: colorLight,
          minValue: minValue,
          maxValue: maxValue,
          unit: unit,
          warningFraction: warningFraction,
          criticalFraction: criticalFraction,
          readout: faceplate
              // The reading is already printed beside the dial; the centre
              // carries the percent of full scale instead of repeating it.
              ? AnalogGaugeReadout.percent
              : AnalogGaugeReadout.value,
          semanticLabel: '$label ($tag)',
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.panelAlt, AppColors.panel],
            ),
            borderRadius: BorderRadius.circular(AppMetrics.radiusMd),
            border: Border.all(
              color: zone == GaugeZone.normal
                  ? AppColors.darkBorder
                  : zoneColor.withAlpha(110),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(70),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: _kPadding,
            child: faceplate
                ? Row(
                    children: [
                      AspectRatio(aspectRatio: 1, child: dial),
                      const SizedBox(width: _kDialGap),
                      Expanded(
                        child: _GaugeReadoutColumn(
                          tag: tag,
                          label: label,
                          valueText: AnalogGauge.formatValue(
                            value,
                            span: maxValue - minValue,
                          ),
                          unit: unit,
                          fraction: fraction,
                          color: color,
                          zone: zone,
                          zoneColor: zoneColor,
                          warningFraction: warningFraction,
                          criticalFraction: criticalFraction,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      if (height >= _kHeaderCutoffHeight) ...[
                        _GaugeHeader(
                          tag: tag,
                          label: label,
                          color: color,
                          zoneColor: zoneColor,
                        ),
                        const SizedBox(height: 3),
                      ],
                      Expanded(child: dial),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

/// Readout column of the faceplate composition: channel identity, the live
/// reading in full, and a linear headroom bar marking the warning/critical
/// thresholds the dial's bands also show.
class _GaugeReadoutColumn extends StatelessWidget {
  const _GaugeReadoutColumn({
    required this.tag,
    required this.label,
    required this.valueText,
    required this.unit,
    required this.fraction,
    required this.color,
    required this.zone,
    required this.zoneColor,
    required this.warningFraction,
    required this.criticalFraction,
  });

  final String tag;
  final String label;
  final String valueText;
  final String unit;
  final double fraction;
  final Color color;
  final GaugeZone zone;
  final Color zoneColor;
  final double warningFraction;
  final double criticalFraction;

  /// Width from which the column has room for the status word next to the pip.
  static const double _kStatusTextWidth = 104;

  /// Height from which the column has room for the threshold bar.
  static const double _kHeadroomBarMinHeight = 60;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 86.0;
        final showStatusText =
            constraints.maxWidth >= _kStatusTextWidth && height >= 70;
        // On a compact handset the column has room for identity and reading
        // but not for the threshold bar as well — the dial's own zone band
        // still carries that information.
        final showHeadroomBar = height >= _kHeadroomBarMinHeight;
        // The reading is the headline of this column, so it grows with the
        // card instead of leaving a tall card looking under-filled.
        final valueSize = (height * 0.30).clamp(14.0, 34.0).toDouble();
        final labelSize = (height * 0.10).clamp(8.0, 12.0).toDouble();

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TagChip(tag: tag, color: color),
                // Status stays pinned to the card's top-right corner rather
                // than floating in whatever space is left over.
                Expanded(
                  child: showStatusText
                      ? Align(
                          alignment: Alignment.centerRight,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6, right: 4),
                            child: Text(
                              zone.statusLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 8,
                                height: 1.2,
                                color: zone == GaugeZone.normal
                                    ? AppColors.darkTextSub
                                    : zoneColor,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.7,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                _StatusPip(color: zoneColor),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: labelSize,
                height: 1.2,
                color: AppColors.darkTextSub,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.7,
              ),
            ),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      valueText,
                      style: TextStyle(
                        fontSize: valueSize,
                        height: 1.0,
                        color: zone == GaugeZone.normal
                            ? AppColors.darkText
                            : zoneColor,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                    if (unit.isNotEmpty) ...[
                      const SizedBox(width: 3),
                      Text(
                        unit,
                        style: TextStyle(
                          fontSize: labelSize + 0.5,
                          height: 1.4,
                          color: AppColors.darkTextMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (showHeadroomBar) ...[
              const SizedBox(height: 5),
              _HeadroomBar(
                fraction: fraction,
                color: color,
                zoneColor: zoneColor,
                warningFraction: warningFraction,
                criticalFraction: criticalFraction,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.color});

  final String tag;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        tag,
        style: TextStyle(
          fontSize: 8,
          height: 1.2,
          color: color,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _StatusPip extends StatelessWidget {
  const _StatusPip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withAlpha(140), blurRadius: 5)],
      ),
    );
  }
}

/// Linear repeat of the dial's scale: fill to the current reading, with hairline
/// markers at the warning and critical thresholds.
class _HeadroomBar extends StatelessWidget {
  const _HeadroomBar({
    required this.fraction,
    required this.color,
    required this.zoneColor,
    required this.warningFraction,
    required this.criticalFraction,
  });

  final double fraction;
  final Color color;
  final Color zoneColor;
  final double warningFraction;
  final double criticalFraction;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 4,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          Widget marker(double at, Color markerColor) => Positioned(
            left: (width * at.clamp(0.0, 1.0) - 0.5).clamp(0.0, width - 1),
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: markerColor),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.darkBg,
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.darkBorder, width: 0.5),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  width: width * fraction.clamp(0.0, 1.0),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color, zoneColor]),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              marker(warningFraction, AppColors.accent.withAlpha(150)),
              marker(criticalFraction, AppColors.eStopColorLight.withAlpha(170)),
            ],
          );
        },
      ),
    );
  }
}

class _GaugeHeader extends StatelessWidget {
  const _GaugeHeader({
    required this.tag,
    required this.label,
    required this.color,
    required this.zoneColor,
  });

  final String tag;
  final String label;
  final Color color;
  final Color zoneColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TagChip(tag: tag, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8,
              height: 1.2,
              color: AppColors.darkTextSub,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        const SizedBox(width: 4),
        _StatusPip(color: zoneColor),
      ],
    );
  }
}

Color _zoneColor(GaugeZone zone, Color normalColor) => switch (zone) {
  GaugeZone.normal => normalColor,
  GaugeZone.warning => AppColors.accent,
  GaugeZone.critical => AppColors.eStopColorLight,
};

class _AnalogGaugePainter extends CustomPainter {
  const _AnalogGaugePainter({
    required this.fraction,
    required this.valueText,
    required this.subText,
    required this.valueFontFactor,
    required this.fontFamily,
    required this.zone,
    required this.color,
    required this.colorLight,
    required this.warningFraction,
    required this.criticalFraction,
  });

  final double fraction;
  final String valueText;
  final String subText;

  /// Readout type size as a share of the dial's side.
  final double valueFontFactor;
  final String? fontFamily;
  final GaugeZone zone;
  final Color color;
  final Color colorLight;
  final double warningFraction;
  final double criticalFraction;

  // Radii as a share of the dial radius, outside-in.
  static const double _kZoneBandRadius = 0.845;
  static const double _kZoneBandWidth = 0.05;
  static const double _kTickOuterRadius = 0.775;
  static const double _kTrackRadius = 0.585;
  static const double _kTrackWidth = 0.135;

  Color get _tipColor => _zoneColor(zone, colorLight);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = side / 2;

    _paintBezel(canvas, center, radius);
    _paintFace(canvas, center, radius);
    _paintZoneBand(canvas, center, radius);
    _paintTicks(canvas, center, radius);
    _paintTrack(canvas, center, radius);
    _paintValueArc(canvas, center, radius);
    _paintReadout(canvas, center, side);
  }

  // ── Housing ────────────────────────────────────────────────────────────────

  void _paintBezel(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center + Offset(0, radius * 0.05),
      radius * 0.97,
      Paint()
        ..color = Colors.black.withAlpha(110)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.13),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF35485C), Color(0xFF16222E), Color(0xFF080F16)],
          stops: [0.0, 0.52, 1.0],
        ).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius - math.max(0.5, radius * 0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.022)
        ..color = Colors.white.withAlpha(30),
    );
  }

  void _paintFace(Canvas canvas, Offset center, double radius) {
    final faceRadius = radius * 0.905;
    canvas.drawCircle(
      center,
      faceRadius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.28, -0.46),
          radius: 1.15,
          colors: [Color(0xFF17293A), Color(0xFF0C1825), Color(0xFF060D14)],
          stops: [0.0, 0.58, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: faceRadius)),
    );

    canvas.drawCircle(
      center,
      faceRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.02)
        ..color = Colors.black.withAlpha(120),
    );
  }

  // ── Scale ──────────────────────────────────────────────────────────────────

  /// Thin outer reference band: the operating zones stay visible even when the
  /// value arc is short, so an operator can see how much headroom is left.
  void _paintZoneBand(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(
      center: center,
      radius: radius * _kZoneBandRadius,
    );
    final strokeWidth = math.max(1.5, radius * _kZoneBandWidth);

    void band(double from, double to, Color bandColor) {
      final span = (to - from).clamp(0.0, 1.0);
      if (span <= 0) return;
      canvas.drawArc(
        rect,
        _kStartAngle + _kSweepAngle * from,
        _kSweepAngle * span,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = bandColor,
      );
    }

    band(0, warningFraction, color.withAlpha(75));
    band(warningFraction, criticalFraction, AppColors.accent.withAlpha(140));
    band(criticalFraction, 1, AppColors.eStopColorLight.withAlpha(165));
  }

  void _paintTicks(Canvas canvas, Offset center, double radius) {
    const totalTicks = 20;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, radius * 0.022);

    for (var i = 0; i <= totalTicks; i++) {
      final t = i / totalTicks;
      final isMajor = i % 5 == 0;
      final angle = _kStartAngle + _kSweepAngle * t;
      final outer = radius * _kTickOuterRadius;
      final inner = radius * (isMajor ? 0.685 : 0.725);

      final tickZone = GaugeZone.forFraction(
        t,
        warningFraction: warningFraction,
        criticalFraction: criticalFraction,
      );
      paint
        ..color = switch (tickZone) {
          GaugeZone.normal => Colors.white.withAlpha(isMajor ? 125 : 58),
          GaugeZone.warning => AppColors.accent.withAlpha(isMajor ? 175 : 95),
          GaugeZone.critical => AppColors.eStopColorLight.withAlpha(
            isMajor ? 195 : 110,
          ),
        }
        ..strokeWidth = math.max(0.8, radius * (isMajor ? 0.03 : 0.018));

      canvas.drawLine(
        center + Offset(math.cos(angle) * outer, math.sin(angle) * outer),
        center + Offset(math.cos(angle) * inner, math.sin(angle) * inner),
        paint,
      );
    }
  }

  // ── Value ──────────────────────────────────────────────────────────────────

  void _paintTrack(Canvas canvas, Offset center, double radius) {
    final rect = Rect.fromCircle(
      center: center,
      radius: radius * _kTrackRadius,
    );
    final strokeWidth = math.max(3.0, radius * _kTrackWidth);

    canvas.drawArc(
      rect,
      _kStartAngle,
      _kSweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth
        ..color = const Color(0xFF060D14).withAlpha(235),
    );

    // Zone tint inside the empty groove — the bands read the same whether the
    // arc has reached them or not.
    void tint(double from, double to, Color tintColor) {
      final span = (to - from).clamp(0.0, 1.0);
      if (span <= 0) return;
      canvas.drawArc(
        rect,
        _kStartAngle + _kSweepAngle * from,
        _kSweepAngle * span,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..color = tintColor,
      );
    }

    tint(warningFraction, criticalFraction, AppColors.accent.withAlpha(26));
    tint(criticalFraction, 1, AppColors.eStopColorLight.withAlpha(30));
  }

  void _paintValueArc(Canvas canvas, Offset center, double radius) {
    if (fraction <= 0.001) return;

    final rect = Rect.fromCircle(
      center: center,
      radius: radius * _kTrackRadius,
    );
    final strokeWidth = math.max(3.0, radius * _kTrackWidth);
    final sweep = _kSweepAngle * fraction;

    canvas.drawArc(
      rect,
      _kStartAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth * 1.35
        ..color = _tipColor.withAlpha(60)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.09),
    );

    // Painted per operating band rather than as one gradient across the whole
    // arc: a single gradient from a cool channel colour to the critical red
    // washes through lavender on the way, which reads as a colour of its own.
    // Each band keeps its own meaning instead.
    void segment(double from, double to, Shader? shader, Color? segmentColor) {
      final span = (to - from).clamp(0.0, 1.0);
      if (span <= 0) return;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      if (shader != null) {
        paint.shader = shader;
      } else {
        paint.color = segmentColor!;
      }
      canvas.drawArc(
        rect,
        _kStartAngle + _kSweepAngle * from,
        _kSweepAngle * span,
        false,
        paint,
      );
    }

    segment(
      0,
      math.min(fraction, warningFraction),
      SweepGradient(
        startAngle: _kStartAngle,
        endAngle: _kStartAngle + _kSweepAngle,
        colors: [color, colorLight],
      ).createShader(rect),
      null,
    );
    if (fraction > warningFraction) {
      segment(
        warningFraction,
        math.min(fraction, criticalFraction),
        null,
        AppColors.accent,
      );
    }
    if (fraction > criticalFraction) {
      segment(criticalFraction, fraction, null, AppColors.eStopColorLight);
    }

    // Bevel highlight along the inner edge — sells the arc as a lit element
    // rather than a flat stroke.
    canvas.drawArc(
      Rect.fromCircle(
        center: center,
        radius: radius * _kTrackRadius - strokeWidth * 0.26,
      ),
      _kStartAngle,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(1.0, strokeWidth * 0.16)
        ..color = Colors.white.withAlpha(55),
    );

    _paintTip(canvas, center, radius, strokeWidth);
  }

  void _paintTip(
    Canvas canvas,
    Offset center,
    double radius,
    double strokeWidth,
  ) {
    final angle = _kStartAngle + _kSweepAngle * fraction;
    final tip =
        center +
        Offset(
          math.cos(angle) * radius * _kTrackRadius,
          math.sin(angle) * radius * _kTrackRadius,
        );

    canvas.drawCircle(
      tip,
      strokeWidth * 0.62,
      Paint()
        ..color = _tipColor.withAlpha(110)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.06),
    );
    canvas.drawCircle(
      tip,
      math.max(1.2, strokeWidth * 0.24),
      Paint()..color = Colors.white.withAlpha(235),
    );
  }

  // ── Readout ────────────────────────────────────────────────────────────────

  void _paintReadout(Canvas canvas, Offset center, double side) {
    if (valueText.isEmpty && subText.isEmpty) return;

    final valueColor = switch (zone) {
      GaugeZone.normal => AppColors.darkText,
      GaugeZone.warning => AppColors.accent,
      GaugeZone.critical => AppColors.eStopColorLight,
    };

    final valuePainter = valueText.isEmpty
        ? null
        : _fitted(
            valueText,
            TextStyle(
              color: valueColor,
              fontSize: (side * valueFontFactor).clamp(9.0, 40.0).toDouble(),
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: -0.6,
              fontFamily: fontFamily,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
            // Widest the digits may run before they start crowding the track.
            side * 0.50,
          );

    final subPainter = subText.isEmpty
        ? null
        : _fitted(
            subText,
            TextStyle(
              color: AppColors.darkTextSub,
              fontSize: (side * 0.088).clamp(6.5, 14.0).toDouble(),
              fontWeight: FontWeight.w700,
              height: 1.0,
              letterSpacing: 0.9,
              fontFamily: fontFamily,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
            ),
            side * 0.46,
          );

    final gap = valuePainter != null && subPainter != null ? side * 0.03 : 0.0;
    final blockHeight =
        (valuePainter?.height ?? 0) + gap + (subPainter?.height ?? 0);
    // Anchored slightly below the dial centre so the block sits toward the
    // open bottom of the 270° scale instead of crowding the arc.
    var cursorY = center.dy + side * 0.05 - blockHeight / 2;

    if (valuePainter != null) {
      valuePainter.paint(
        canvas,
        Offset(center.dx - valuePainter.width / 2, cursorY),
      );
      cursorY += valuePainter.height + gap;
    }
    subPainter?.paint(
      canvas,
      Offset(center.dx - subPainter.width / 2, cursorY),
    );
  }

  /// Lays [text] out at [style], then shrinks the type until it fits
  /// [maxWidth] — a 4-digit ADC count must never be ellipsized into a lie.
  TextPainter _fitted(String text, TextStyle style, double maxWidth) {
    final limit = math.max(1.0, maxWidth);
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    if (painter.width <= limit || painter.width <= 0) return painter;

    final shrunk = (style.fontSize ?? 12) * (limit / painter.width);
    return TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: math.max(6.0, shrunk)),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  @override
  bool shouldRepaint(covariant _AnalogGaugePainter oldDelegate) {
    return oldDelegate.fraction != fraction ||
        oldDelegate.valueText != valueText ||
        oldDelegate.subText != subText ||
        oldDelegate.valueFontFactor != valueFontFactor ||
        oldDelegate.fontFamily != fontFamily ||
        oldDelegate.zone != zone ||
        oldDelegate.color != color ||
        oldDelegate.colorLight != colorLight ||
        oldDelegate.warningFraction != warningFraction ||
        oldDelegate.criticalFraction != criticalFraction;
  }
}
