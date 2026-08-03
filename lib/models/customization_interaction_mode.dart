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
//
// This stage only reaches placingWidget to mean "attached to the finger" —
// it does not yet mean a grid slot has been chosen or validated. See
// LayoutEditController's placement methods for the transitions between
// these states.
// ─────────────────────────────────────────────────────────────────────────────

enum CustomizationInteractionMode {
  editing,
  browsingCatalogue,
  liftingCatalogueWidget,
  placingWidget,
}
