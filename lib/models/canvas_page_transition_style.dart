/// How ControlCanvas animates between grid pages while the operator swipes
/// during Edit Mode. Session-only UI preference — see
/// LayoutEditController.pageTransitionStyle — never written to
/// ControlLayoutConfig/SharedPreferences, and reset to [slide] every time a
/// new edit session starts (LayoutEditController.enter). It's only ever
/// visible while editing: live mode always renders with
/// NeverScrollableScrollPhysics, so there is no page-swipe to animate
/// outside Edit Mode.
///
/// Each style's actual motion lives in control_canvas.dart's
/// `_buildPageEffect` — [displayName]/[description] here only label it for
/// the picker sheet.
enum CanvasPageTransitionStyle {
  slide,
  fade,
  zoomFade,
  depth,
  cube;

  String get displayName => switch (this) {
    CanvasPageTransitionStyle.slide => 'Slide',
    CanvasPageTransitionStyle.fade => 'Fade',
    CanvasPageTransitionStyle.zoomFade => 'Zoom Fade',
    CanvasPageTransitionStyle.depth => 'Depth',
    CanvasPageTransitionStyle.cube => 'Cube',
  };

  /// One-line summary shown beneath [displayName] in the picker sheet — a
  /// bare list of names doesn't tell an operator what separates them.
  String get description => switch (this) {
    CanvasPageTransitionStyle.slide =>
      'Pages slide horizontally, following the swipe.',
    CanvasPageTransitionStyle.fade =>
      'Pages cross-fade into each other as the swipe crosses.',
    CanvasPageTransitionStyle.zoomFade =>
      'The incoming page grows from 92% while fading in.',
    CanvasPageTransitionStyle.depth =>
      'The outgoing page shrinks and dims as the new one slides over it.',
    CanvasPageTransitionStyle.cube =>
      'Pages pivot around their shared edge in subtle 3D.',
  };
}
