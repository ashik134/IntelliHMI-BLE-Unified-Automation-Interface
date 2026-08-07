// ─────────────────────────────────────────────────────────────────────────────
// CustomizationInteractionMode
//
// The customization-mode interaction state, layered on top of
// LayoutEditController.isEditing. isEditing answers "is Edit Mode active at
// all"; this answers "what is the operator doing right now within Edit
// Mode" — a single source of truth instead of several unrelated booleans
// (isBrowsingCatalogue, isLifting, isPlacing, ...) that could drift out of
// sync with each other.
//
//   editing              -> normal canvas editing (toolbar visible)
//   browsingCatalogue    -> the Widgets catalogue route is on top
//   liftingCatalogueWidget -> long-press recognized; preview is lifting off
//                             its catalogue card, still over the catalogue
//   placingWidget        -> the lifted preview is attached to the finger,
//                           floating over the (now revealed) control screen
//   settlingWidget       -> the finger has released over a validated grid
//                           rectangle; the preview is animating from the
//                           release position into that rectangle
//   resizingWidget       -> a canvas edge-handle drag is live on the
//                           selected widget (see LayoutEditController
//                           .beginResize/updateResize/endResize)
//   movingWidget         -> a long-press recognized directly on an ALREADY
//                           PLACED canvas widget; that widget is attached to
//                           the finger and being carried, exactly like
//                           placingWidget but for an existing widget instead
//                           of a pending catalogue entry (see
//                           LayoutEditController.beginMove/updateMovePreview)
//   settlingMovedWidget  -> the finger has released over a validated grid
//                           rectangle for an in-flight move; the preview is
//                           animating into it — the move's counterpart to
//                           settlingWidget (see LayoutEditController
//                           .handleMoveDrop/commitMovedPlacement)
//
// placingWidget/movingWidget only mean "attached to the finger" — they do
// not yet mean a grid slot has been chosen or validated. settlingWidget/
// settlingMovedWidget mean a target rectangle HAS been chosen and the
// preview is (briefly, non-cancelably) animating into it, right before it
// becomes/returns to a real committed widget. See LayoutEditController's
// placement methods for the transitions between these states.
// ─────────────────────────────────────────────────────────────────────────────

enum CustomizationInteractionMode {
  editing,
  browsingCatalogue,
  liftingCatalogueWidget,
  placingWidget,
  settlingWidget,
  resizingWidget,
  movingWidget,
  settlingMovedWidget,
}
