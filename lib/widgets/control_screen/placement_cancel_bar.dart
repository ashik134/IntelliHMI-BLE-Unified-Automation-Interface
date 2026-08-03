import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlacementCancelBar
//
// The only affordance visible while a catalogue widget is attached to the
// finger over the control screen (CustomizationInteractionMode.
// placingWidget) — there is no separate Add/confirm button by design, so
// this is also the sole way to back out short of releasing the finger over
// a valid canvas position. Supports both cancellation methods:
//   - Tap: InkWell.onTap.
//   - Drag-and-release: this is also a real DragTarget<CatalogEntry>, so
//     dropping the carried preview here is accepted directly (wasAccepted
//     is then true in the Draggable's own onDragEnd, which is exactly how
//     _DraggableCatalogCardState tells "dropped on Cancel" apart from
//     "dropped on the canvas" — see its _handleDragEnd doc comment).
// Either path calls LayoutEditController.cancelCataloguePlacement(), which
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
          child: DragTarget<CatalogEntry>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (_) => context
                .read<LayoutEditController>()
                .cancelCataloguePlacement(),
            builder: (context, candidateData, rejectedData) {
              final hovering = candidateData.isNotEmpty;
              return Material(
                color: hovering ? AppColors.eStopColor : AppColors.panel,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: hovering
                        ? AppColors.eStopColor
                        : AppColors.panelStroke,
                  ),
                ),
                elevation: hovering ? 10 : 6,
                shadowColor: Colors.black54,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => context
                      .read<LayoutEditController>()
                      .cancelCataloguePlacement(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.symmetric(
                      horizontal: hovering ? 20 : 16,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.close_rounded,
                          size: hovering ? 20 : 18,
                          color: hovering ? Colors.white : AppColors.darkText,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          hovering ? 'Release to cancel' : 'Cancel',
                          style: TextStyle(
                            color: hovering ? Colors.white : AppColors.darkText,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
