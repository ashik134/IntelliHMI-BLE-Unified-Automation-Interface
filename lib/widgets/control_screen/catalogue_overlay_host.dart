import 'package:flutter/material.dart';

import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/screens/widget_catalog_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CatalogueOverlayHost
//
// Renders the Widgets catalogue as a sliding layer INSIDE the control
// screen's own Stack, rather than as a separate pushed/popped Navigator
// route. This is deliberate, not cosmetic: NavigatorState.pop()/push()
// unconditionally calls _afterNavigation() -> _cancelActivePointers(),
// which dispatches a synthetic PointerCancelEvent to every pointer the
// Navigator has ever seen go down (see navigator.dart in the framework
// source) — including the one still held down mid long-press-drag. Popping
// a route while a LongPressDraggable's drag is still active on that same
// Navigator therefore ALWAYS cancels the drag within a frame, regardless of
// the Draggable's own (real, and otherwise sufficient) support for
// surviving being removed from the widget tree mid-drag. An earlier version
// of this flow pushed the catalogue as its own route and popped it to
// reveal the control screen — which canceled the drag immediately, landing
// the widget wherever the release-point search resolved to from the
// finger's position at that instant (auto-placement, not a carried drop).
// See _DraggableCatalogCard's doc comment in widget_catalog_screen.dart for
// the full account.
//
// Keeping the catalogue as a plain widget in the same route sidesteps that
// mechanism entirely: "closing" it is an ordinary rebuild, never a
// Navigator transition, so the drag that started on one of its cards keeps
// running right through the transition.
//
// Visible (slid to Offset.zero) for browsingCatalogue and
// liftingCatalogueWidget — i.e. for as long as the operator is still
// looking at the catalogue, including the brief lift-off animation. Slides
// fully off to the right, and stops absorbing touches, the moment the lift
// completes and CustomizationInteractionMode.placingWidget begins (see
// LayoutEditController.confirmPlacementStarted) — this IS the "reverse the
// transition when placement begins" / "reveal the control screen behind it"
// requirement, driven purely by interactionMode rather than by any
// navigation call. Stays mounted (off-screen, non-interactive) through
// placingWidget so the slide-out animation is never cut short by an early
// unmount — though per the framework's own design, unmounting mid-drag
// would in fact be safe too; this is just the simplest timing to reason
// about. Removed once the mode moves past placement (settlingWidget /
// editing).
// ─────────────────────────────────────────────────────────────────────────────

class CatalogueOverlayHost extends StatelessWidget {
  const CatalogueOverlayHost({super.key, required this.interactionMode});

  final CustomizationInteractionMode interactionMode;

  static const Duration _duration = Duration(milliseconds: 320);

  bool get _isMounted =>
      interactionMode == CustomizationInteractionMode.browsingCatalogue ||
      interactionMode == CustomizationInteractionMode.liftingCatalogueWidget ||
      interactionMode == CustomizationInteractionMode.placingWidget;

  bool get _isVisible =>
      interactionMode == CustomizationInteractionMode.browsingCatalogue ||
      interactionMode == CustomizationInteractionMode.liftingCatalogueWidget;

  @override
  Widget build(BuildContext context) {
    if (!_isMounted) return const SizedBox.shrink();
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_isVisible,
        child: AnimatedSlide(
          duration: _duration,
          curve: Curves.easeOutCubic,
          offset: _isVisible ? Offset.zero : const Offset(1, 0),
          child: const WidgetCatalogScreen(),
        ),
      ),
    );
  }
}
