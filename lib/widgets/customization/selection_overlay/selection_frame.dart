import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

/// The rounded violet bounding-box outline drawn around a selected widget,
/// sitting ~2px outside the widget's own edge so it never clips the control
/// underneath. Purely decorative — no gestures — so it can be reused for
/// both the "settled" selection and the live resize/move ghost preview.
class SelectionFrame extends StatelessWidget {
  const SelectionFrame({
    super.key,
    this.borderRadius = 12,
    this.isGhost = false,
  });

  /// Corner radius of the frame, matching the wrapped widget's own radius.
  final double borderRadius;

  /// Ghost previews (shown mid-drag) use a lighter fill and dashed-feel
  /// treatment so they read as "not yet committed."
  final bool isGhost;

  /// Border stroke width when settled (selected, not mid-gesture).
  static const double borderWidth = 2;

  /// Border stroke width for the ghost/live-preview state.
  static const double ghostBorderWidth = 1.5;

  /// With [BorderSide.strokeAlignOutside], Flutter draws the stroke's
  /// centerline `width / 2` outside the box's own geometric edge — i.e.
  /// the visual line is NOT flush with the edge the box is laid out at.
  /// Resize handles need this offset to center themselves exactly on the
  /// visible line rather than on the (invisible) layout edge.
  static double borderCenterOffset(bool ghost) =>
      (ghost ? ghostBorderWidth : borderWidth) / 2;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: isGhost ? AppColors.selectionViolet.withAlpha(18) : null,
          border: Border.all(
            color: isGhost
                ? AppColors.selectionViolet.withAlpha(160)
                : AppColors.selectionViolet,
            width: isGhost ? ghostBorderWidth : borderWidth,
            strokeAlign: BorderSide.strokeAlignOutside,
          ),
          boxShadow: isGhost
              ? const []
              : const [
                  BoxShadow(
                    color: AppColors.selectionGlow,
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
        ),
      ),
    );
  }
}

/// Small violet pill showing the live "W x H" size label, anchored above
/// the top-left corner of the selection frame.
class SelectionSizeLabel extends StatelessWidget {
  const SelectionSizeLabel({super.key, required this.columns, required this.rows});

  final int columns;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.selectionVioletDeep,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Text(
          '$columns × $rows',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
