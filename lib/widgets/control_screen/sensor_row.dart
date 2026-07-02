import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SensorRow
//
// Extracted verbatim from the byte-identical _sensorRow/_sensorCard methods
// in plc14_control_screen.dart and plc38_control_screen.dart (Load 1 / A1,
// Load 2 / A2). Pure presentational de-dup, no behavior change.
// ─────────────────────────────────────────────────────────────────────────────

class SensorRow extends StatelessWidget {
  const SensorRow({super.key, required this.a1, required this.a2});

  final int a1;
  final int a2;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SensorCard(
            label: 'Load 1',
            tag: 'A1',
            value: a1,
            color: AppColors.upColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SensorCard(
            label: 'Load 2',
            tag: 'A2',
            value: a2,
            color: AppColors.downColor,
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
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
                style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(color: AppColors.darkTextSub, fontSize: 8),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
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
