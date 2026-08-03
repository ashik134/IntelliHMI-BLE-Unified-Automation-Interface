import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlacementCancelBar
//
// The only affordance visible while a catalogue widget is attached to the
// finger over the control screen (CustomizationInteractionMode.
// placingWidget) — there is no separate Add/confirm button by design, so
// this is also the sole way to back out short of releasing the finger.
// Tapping it calls LayoutEditController.cancelCataloguePlacement(), which
// the floating preview itself watches to disappear immediately even though
// the underlying drag gesture may still be silently active until the
// finger actually lifts (see that method's doc comment).
// ─────────────────────────────────────────────────────────────────────────────

class PlacementCancelBar extends StatelessWidget {
  const PlacementCancelBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.only(top: 10, left: 14),
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.panel,
            shape: const StadiumBorder(
              side: BorderSide(color: AppColors.panelStroke),
            ),
            elevation: 6,
            shadowColor: Colors.black54,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () =>
                  context.read<LayoutEditController>().cancelCataloguePlacement(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppColors.darkText,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.darkText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
