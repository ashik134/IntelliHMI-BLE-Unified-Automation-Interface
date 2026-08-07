import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlacementCancelBar
//
// The only affordance visible while a widget is attached to the finger over
// the control screen — either a pending catalogue entry
// (CustomizationInteractionMode.placingWidget) or an already-placed widget
// being carried (CustomizationInteractionMode.movingWidget). There is no
// separate Add/confirm button by design, so this is also the sole way to
// back out short of releasing the finger over a valid canvas position.
// Supports both cancellation methods:
//   - Tap: InkWell.onTap.
//   - Drag-and-release: this is also a real DragTarget<Object>, so dropping
//     either kind of carried preview here is accepted directly (wasAccepted
//     is then true in the Draggable's own onDragEnd, which is exactly how
//     _DraggableCatalogCardState/control_canvas.dart's own move-draggable
//     tell "dropped on Cancel" apart from "dropped on the canvas" — see
//     their own _handleDragEnd doc comments). Object rather than CatalogEntry
//     so this one DragTarget accepts a Draggable<CatalogEntry> (catalogue
//     placement) AND a Draggable<String> (an existing widget's id, see
//     control_canvas.dart) identically.
// Either path calls LayoutEditController.cancelActivePlacementSession(),
// which dispatches to whichever of cancelCataloguePlacement/cancelMove is
// actually live and is watched by the floating preview to disappear
// immediately even though the underlying drag gesture may still be silently
// active until the finger actually lifts (see those methods' doc comments).
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
          child: DragTarget<Object>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (_) => context
                .read<LayoutEditController>()
                .cancelActivePlacementSession(),
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
                      .cancelActivePlacementSession(),
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
