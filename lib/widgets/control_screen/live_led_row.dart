import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LiveLedRow
//
// Extracted from the near-identical _liveLEDs/_ledIndicator (PLC14) and
// _liveLEDs/_led (PLC38) methods. Generalized to accept an arbitrary list of
// LedSpec so it covers PLC14's 4 outputs and PLC38's 10 without needing two
// near-duplicate implementations — the count/pin-label differences were the
// only real difference between the two originals.
// ─────────────────────────────────────────────────────────────────────────────

class LedSpec {
  const LedSpec({
    required this.label,
    required this.active,
    required this.color,
    required this.pin,
  });

  final String label;
  final bool active;
  final Color color;
  final String pin;
}

class LiveLedRow extends StatelessWidget {
  const LiveLedRow({super.key, required this.leds});

  final List<LedSpec> leds;

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
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [for (final led in leds) _LedIndicator(spec: led)],
      ),
    );
  }
}

class _LedIndicator extends StatelessWidget {
  const _LedIndicator({required this.spec});

  final LedSpec spec;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: spec.active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, _) {
            return Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: spec.active ? spec.color : Colors.grey.shade600,
                shape: BoxShape.circle,
                boxShadow: spec.active
                    ? [
                        BoxShadow(
                          color: spec.color.withAlpha(153),
                          blurRadius: 4 * value,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          spec.pin,
          style: const TextStyle(
            fontSize: 6,
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextSub,
          ),
        ),
        Text(
          spec.label,
          style: TextStyle(
            fontSize: 8,
            color: spec.active ? spec.color : AppColors.darkTextMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
