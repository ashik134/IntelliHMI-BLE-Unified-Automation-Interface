import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// StatusBarChip
//
// Extracted from the near-identical _buildStatusBar layout code in both
// control screens. Each screen keeps its own (legitimately different) color
// and label derivation logic and passes the result in — only the chip
// chrome/layout was duplicated.
// ─────────────────────────────────────────────────────────────────────────────

class StatusBarChip extends StatelessWidget {
  const StatusBarChip({super.key, required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withAlpha(31),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(128)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 12,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
