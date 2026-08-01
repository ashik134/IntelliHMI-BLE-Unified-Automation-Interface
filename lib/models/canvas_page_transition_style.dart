/// How ControlCanvas animates between grid pages while the operator swipes
/// during Edit Mode. Session-only UI preference — see
/// LayoutEditController.pageTransitionStyle — never written to
/// ControlLayoutConfig/SharedPreferences, and reset to [slide] every time a
/// new edit session starts (LayoutEditController.enter). It's only ever
/// visible while editing: live mode always renders with
/// NeverScrollableScrollPhysics, so there is no page-swipe to animate
/// outside Edit Mode.
enum CanvasPageTransitionStyle {
  slide,
  fade;

  String get displayName => switch (this) {
    CanvasPageTransitionStyle.slide => 'Slide',
    CanvasPageTransitionStyle.fade => 'Fade',
  };
}
