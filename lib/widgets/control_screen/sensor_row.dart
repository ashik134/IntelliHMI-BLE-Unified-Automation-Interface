import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/analog_gauge.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SensorRow
//
// Live read-out strip for the two analog channels the PLC notifies over
// BLEConstants.analogCharUuid ("A1:<v>,A2:<v>"). Both channels render as
// industrial radial gauges (see AnalogGauge); the row owns nothing but layout
// and sizing — values arrive from CraneController.a1 / .a2.
//
// Sizing is driven by the device first and the row's own width second: a
// diagnostic strip that is merely *proportionate* still reads as oversized on a
// small handset, where every pixel it takes comes straight out of the control
// canvas. The screen's size class therefore sets the height band, and the row
// width only positions the strip inside it. Callers can still pin an exact
// [height] when a layout needs a fixed budget.
// ─────────────────────────────────────────────────────────────────────────────

class SensorRow extends StatelessWidget {
  const SensorRow({
    super.key,
    required this.a1,
    required this.a2,
    this.fullScale = AnalogGauge.defaultFullScale,
    this.height,
  });

  final int a1;
  final int a2;

  /// Top of the scale for both channels. Defaults to the PLC's raw 12-bit ADC
  /// full scale — override if the firmware ever scales the analog payload into
  /// engineering units.
  final double fullScale;

  /// Optional fixed strip height. When null the row derives one from the
  /// screen's size class and its own width — see [heightFor].
  final double? height;

  /// Gap between the two gauge cards.
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

  /// Strip height for a device of [screenWidth] rendering a row [rowWidth] wide.
  ///
  /// [screenWidth] is the screen's *shortest* side — the usual size-class
  /// signal — so a handset held in landscape is still sized as a handset.
  static double heightFor({
    required double screenWidth,
    required double rowWidth,
  }) {
    final t =
        ((screenWidth - _kCompactScreen) / (_kExpandedScreen - _kCompactScreen))
            .clamp(0.0, 1.0)
            .toDouble();

    final cardWidth = math.max(0.0, (rowWidth - _kGap) / 2);
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
    final screen = MediaQuery.sizeOf(context);
    final screenWidth = math.min(screen.width, screen.height);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final stripHeight =
            height ?? heightFor(screenWidth: screenWidth, rowWidth: width);

        return SizedBox(
          height: stripHeight,
          child: Row(
            children: [
              Expanded(
                child: AnalogGaugeCard(
                  tag: 'A1',
                  label: 'Load 1',
                  value: a1.toDouble(),
                  color: AppColors.upColor,
                  colorLight: AppColors.upColorLight,
                  maxValue: fullScale,
                ),
              ),
              const SizedBox(width: _kGap),
              Expanded(
                child: AnalogGaugeCard(
                  tag: 'A2',
                  label: 'Load 2',
                  value: a2.toDouble(),
                  color: AppColors.downColor,
                  colorLight: AppColors.downColorLight,
                  maxValue: fullScale,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
