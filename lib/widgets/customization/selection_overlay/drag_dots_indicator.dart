import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

/// Small 6-dot "grip" affordance shown on unselected widgets while
/// customization mode is active, hinting that the tile is draggable
/// without the visual weight of a full selection frame.
class DragDotsIndicator extends StatelessWidget {
  const DragDotsIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Drag to move',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.panel.withAlpha(210),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              2,
              (_) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (_) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: AppColors.darkTextMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
