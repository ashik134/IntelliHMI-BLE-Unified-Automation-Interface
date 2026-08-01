import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';

/// Opens a bottom sheet to preview/pick how ControlCanvas animates between
/// grid pages while swiping in Edit Mode. Session-only (see
/// LayoutEditController.pageTransitionStyle) — never written to the saved
/// layout, since live mode never allows page-swiping at all.
Future<void> showPageTransitionSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PageTransitionSheet(),
  );
}

class _PageTransitionSheet extends StatelessWidget {
  const _PageTransitionSheet();

  @override
  Widget build(BuildContext context) {
    final editCtrl = context.watch<LayoutEditController>();
    final current = editCtrl.pageTransitionStyle;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder),
          boxShadow: AppMetrics.shadowMd,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.panelStroke,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Page Transition',
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How the canvas animates when you swipe between pages while '
              'editing a multi-page layout.',
              style: TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            for (final style in CanvasPageTransitionStyle.values)
              _TransitionOptionTile(
                style: style,
                selected: style == current,
                onTap: () => editCtrl.setPageTransitionStyle(style),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.selectionViolet,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransitionOptionTile extends StatelessWidget {
  const _TransitionOptionTile({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final CanvasPageTransitionStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.selectionViolet.withAlpha(28)
              : AppColors.darkBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.selectionViolet : AppColors.darkBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected
                  ? AppColors.selectionViolet
                  : AppColors.darkTextMuted,
            ),
            const SizedBox(width: 10),
            Text(
              style.displayName,
              style: TextStyle(
                color: AppColors.darkText,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
