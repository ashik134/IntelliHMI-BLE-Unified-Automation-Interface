import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

/// Subtle dot-grid backdrop shown behind the control canvas while
/// customization mode is active — a lightweight visual cue (à la
/// Figma/Canva) that the surface is now an editable canvas, not live
/// controls. Painted once per layout pass; RepaintBoundary keeps it from
/// forcing repaints of the widgets stacked above it.
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key, this.spacing = 20, this.dotRadius = 1.1});

  final double spacing;
  final double dotRadius;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _DotGridPainter(spacing: spacing, dotRadius: dotRadius),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter({required this.spacing, required this.dotRadius});

  final double spacing;
  final double dotRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.selectionDotGrid;
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGridPainter oldDelegate) =>
      oldDelegate.spacing != spacing || oldDelegate.dotRadius != dotRadius;
}
