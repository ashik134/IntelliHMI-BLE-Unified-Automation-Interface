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
//
// placingWidget only means "attached to the finger" — it does not yet mean
// a grid slot has been chosen or validated. settlingWidget means a target
// rectangle HAS been chosen and the preview is (briefly, non-cancelably)
// animating into it, right before it becomes a real committed widget. See
// LayoutEditController's placement methods for the transitions between
// these states.
// ─────────────────────────────────────────────────────────────────────────────

enum CustomizationInteractionMode {
  editing,
  browsingCatalogue,
  liftingCatalogueWidget,
  placingWidget,
  settlingWidget,
}
