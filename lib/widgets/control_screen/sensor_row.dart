import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/gauges/radial_gauge_indicator.dart';

class SensorRow extends StatelessWidget {
  const SensorRow({
    super.key,
    required this.a1,
    required this.a2,
    this.gaugeMinValue = 0,
    this.gaugeMaxValue = 100,
    this.unit = 'kg',
  });

  final int a1;
  final int a2;
  final double gaugeMinValue;
  final double gaugeMaxValue;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final safeMin = gaugeMinValue.isFinite ? gaugeMinValue : 0.0;
    final safeMax = gaugeMaxValue.isFinite && gaugeMaxValue > safeMin
        ? gaugeMaxValue
        : safeMin + 100.0;
    final gaugeSpan = safeMax - safeMin;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        final stacked = width < 330;
        final gaugeSide = stacked
            ? math.min(width - 20, 156.0).clamp(124.0, 156.0).toDouble()
            : math.min(width * 0.38, 158.0).clamp(126.0, 158.0).toDouble();

        final gauge = SizedBox.square(
          dimension: gaugeSide,
          child: IndustrialRadialGaugeIndicator(
            label: 'Load Weight',
            minValue: safeMin,
            maxValue: safeMax,
            value: a1.toDouble(),
            unit: unit,
            minorTicksPerMajor: 4,
            showActiveGlow: a1 > safeMin,
            ranges: [
              RadialGaugeRange.normal(
                startValue: safeMin,
                endValue: safeMin + gaugeSpan * 0.7,
              ),
              RadialGaugeRange.warning(
                startValue: safeMin + gaugeSpan * 0.7,
                endValue: safeMin + gaugeSpan * 0.85,
              ),
              RadialGaugeRange.danger(
                startValue: safeMin + gaugeSpan * 0.85,
                endValue: safeMax,
              ),
            ],
          ),
        );
        final statusCards = _SensorStatusCards(a1: a1, a2: a2);

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(stacked ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.panelStroke.withAlpha(210)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(55),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [gauge, const SizedBox(height: 8), statusCards],
                )
              : Row(
                  children: [
                    gauge,
                    const SizedBox(width: 10),
                    Expanded(child: statusCards),
                  ],
                ),
        );
      },
    );
  }
}

class _SensorStatusCards extends StatelessWidget {
  const _SensorStatusCards({required this.a1, required this.a2});

  final int a1;
  final int a2;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 300;
        final cards = [
          _SensorCard(
            label: 'Load 1',
            tag: 'A1',
            value: a1,
            color: AppColors.upColor,
          ),
          _SensorCard(
            label: 'Load 2',
            tag: 'A2',
            value: a2,
            color: AppColors.downColor,
          ),
        ];

        if (wide) {
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 8),
              Expanded(child: cards[1]),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [cards[0], const SizedBox(height: 8), cards[1]],
        );
      },
    );
  }
}

class _SensorCard extends StatelessWidget {
  const _SensorCard({
    required this.label,
    required this.tag,
    required this.value,
    required this.color,
  });

  final String label;
  final String tag;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withAlpha(178),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder.withAlpha(210)),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.darkTextSub,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.darkText,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
