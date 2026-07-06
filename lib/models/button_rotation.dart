// ─────────────────────────────────────────────────────────────────────────────
// ButtonRotation
//
// Render-only rotation, restricted to 90° steps (not a free-form angle)
// because: (1) it only affects icon/visual orientation, never gesture
// geometry or hit-testing math in IndustrialSpringButton/CraneSliderButton,
// which stay axis-aligned; (2) a bounded enum is trivially validated and
// trivially serialized, consistent with every other bounded field in this
// model (heightScale, cornerRadius, ...); (3) no concrete use case in scope
// needs a free angle — only a directional-arrow flip for sliders/push/
// toggle/cross-travel.
// ─────────────────────────────────────────────────────────────────────────────

enum ButtonRotation { none, deg90, deg180, deg270 }

extension ButtonRotationInfo on ButtonRotation {
  /// Fraction of a full turn, for use with Transform.rotate(angle: turns * 2π)
  /// or similar. RotatedBox(quarterTurns:) is preferred at the render shell
  /// since it avoids repainting/re-laying-out at odd angles — see
  /// ConfigurableButton.
  double get turns => switch (this) {
    ButtonRotation.none => 0.0,
    ButtonRotation.deg90 => 0.25,
    ButtonRotation.deg180 => 0.5,
    ButtonRotation.deg270 => 0.75,
  };

  int get quarterTurns => switch (this) {
    ButtonRotation.none => 0,
    ButtonRotation.deg90 => 1,
    ButtonRotation.deg180 => 2,
    ButtonRotation.deg270 => 3,
  };

  String get label => switch (this) {
    ButtonRotation.none => '0°',
    ButtonRotation.deg90 => '90°',
    ButtonRotation.deg180 => '180°',
    ButtonRotation.deg270 => '270°',
  };
}
