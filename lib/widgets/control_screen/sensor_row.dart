import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/hoist_notification.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/analog_gauge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SensorRow
//
// Live read-out strip for the layout's analog readers. Every gauge is fully
// described by the [SensorGaugeSpec]s handed in — scaling, units, thresholds
// and colours are all resolved upstream (FeedbackManager + the analog area of
// Feedback Settings), exactly like LiveLedRow takes resolved LedSpecs. The row
// owns nothing but layout and sizing, and never reads a controller itself.
//
// Sizing is driven by the device first and the row's own width second: a
// diagnostic strip that is merely *proportionate* still reads as oversized on a
// small handset, where every pixel it takes comes straight out of the control
// canvas. The screen's size class therefore sets the height band, and the row
// width only positions the strip inside it. Callers can still pin an exact
// [height] when a layout needs a fixed budget.
// ─────────────────────────────────────────────────────────────────────────────

/// One resolved gauge. Purely presentational — nothing here refers to a PLC
/// channel or a config, so the row cannot read or write anything itself.
@immutable
class SensorGaugeSpec {
  const SensorGaugeSpec({
    required this.tag,
    required this.label,
    required this.value,
    required this.color,
    required this.colorLight,
    this.unit = '',
    this.minValue = 0,
    this.maxValue = AnalogGauge.defaultFullScale,
    this.warningFraction = 0.75,
    this.criticalFraction = 0.9,
  });

  /// Short channel id shown in the header chip (`H1`).
  final String tag;

  /// Operator-facing name (`Load 1`).
  final String label;

  /// Already-scaled reading, in [unit]s.
  final double value;

  final Color color;
  final Color colorLight;
  final String unit;
  final double minValue;
  final double maxValue;
  final double warningFraction;
  final double criticalFraction;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SensorGaugeSpec &&
          other.tag == tag &&
          other.label == label &&
          other.value == value &&
          other.color == color &&
          other.colorLight == colorLight &&
          other.unit == unit &&
          other.minValue == minValue &&
          other.maxValue == maxValue &&
          other.warningFraction == warningFraction &&
          other.criticalFraction == criticalFraction;

  @override
  int get hashCode => Object.hash(
    tag,
    label,
    value,
    color,
    colorLight,
    unit,
    minValue,
    maxValue,
    warningFraction,
    criticalFraction,
  );
}

class SensorRow extends StatelessWidget {
  const SensorRow({super.key, required this.gauges, this.height});

  final List<SensorGaugeSpec> gauges;

  /// Optional fixed strip height. When null the row derives one from the
  /// screen's size class and its own width — see [heightFor].
  final double? height;

  /// Gap between gauge cards.
  static const double _kGap = 8;

  // ── Sizing bands ───────────────────────────────────────────────────────────
  // Interpolated between the two ends rather than switched at a breakpoint, so
  // two phones a few dp apart never render visibly different strips.

  /// Smallest handset the strip is tuned for; at or below this it is at its
  /// most compact.
  static const double _kCompactScreen = 320;

  /// Screen size class from which the strip is at full size (tablets).
  static const double _kExpandedScreen = 768;

  static const double _kMinHeightCompact = 62;
  static const double _kMinHeightExpanded = 96;
  static const double _kMaxHeightCompact = 78;
  static const double _kMaxHeightExpanded = 128;

  /// Share of a card's width used as its height on the compact / expanded ends.
  static const double _kAspectCompact = 0.46;
  static const double _kAspectExpanded = 0.62;

  /// Strip height for a device of [screenWidth] rendering a row [rowWidth]
  /// wide holding [cardCount] gauges.
  ///
  /// [screenWidth] is the screen's *shortest* side — the usual size-class
  /// signal — so a handset held in landscape is still sized as a handset.
  static double heightFor({
    required double screenWidth,
    required double rowWidth,
    int cardCount = 2,
  }) {
    final t =
        ((screenWidth - _kCompactScreen) / (_kExpandedScreen - _kCompactScreen))
            .clamp(0.0, 1.0)
            .toDouble();

    final cards = math.max(1, cardCount);
    final cardWidth = math.max(0.0, (rowWidth - _kGap * (cards - 1)) / cards);
    final proportional =
        cardWidth * lerpDouble(_kAspectCompact, _kAspectExpanded, t)!;

    return proportional
        .clamp(
          lerpDouble(_kMinHeightCompact, _kMinHeightExpanded, t)!,
          lerpDouble(_kMaxHeightCompact, _kMaxHeightExpanded, t)!,
        )
        .toDouble();
  }

  @override
  Widget build(BuildContext context) {
    if (gauges.isEmpty) return const SizedBox.shrink();

    final screen = MediaQuery.sizeOf(context);
    final screenWidth = math.min(screen.width, screen.height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final stripHeight =
            height ??
            heightFor(
              screenWidth: screenWidth,
              rowWidth: width,
              cardCount: gauges.length,
            );

        return SizedBox(
          height: stripHeight,
          child: Row(
            children: [
              for (var i = 0; i < gauges.length; i++) ...[
                if (i > 0) const SizedBox(width: _kGap),
                Expanded(
                  child: AnalogGaugeCard(
                    tag: gauges[i].tag,
                    label: gauges[i].label,
                    value: gauges[i].value,
                    color: gauges[i].color,
                    colorLight: gauges[i].colorLight,
                    unit: gauges[i].unit,
                    minValue: gauges[i].minValue,
                    maxValue: gauges[i].maxValue,
                    warningFraction: gauges[i].warningFraction,
                    criticalFraction: gauges[i].criticalFraction,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Firmware-value convenience for callers with no resolved feedback config.
List<SensorGaugeSpec> rawSensorGauges({required int h1, required int h2}) => [
  SensorGaugeSpec(
    tag: HoistNotification.hoist1Key,
    label: 'Load 1',
    value: h1.toDouble(),
    color: AppColors.upColor,
    colorLight: AppColors.upColorLight,
  ),
  SensorGaugeSpec(
    tag: HoistNotification.hoist2Key,
    label: 'Load 2',
    value: h2.toDouble(),
    color: AppColors.downColor,
    colorLight: AppColors.downColorLight,
  ),
];
