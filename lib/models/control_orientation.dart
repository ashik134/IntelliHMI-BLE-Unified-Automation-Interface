// ─────────────────────────────────────────────────────────────────────────────
// ControlOrientation
//
// Shared Horizontal/Vertical orientation for canvas widgets whose layout and
// interaction axis can meaningfully flip (see ButtonConfig.supportsOrientation).
// Several widget types already had their own per-type orientation enum
// (JoystickAxis, AnalogSliderOrientation, AnalogJoystickOrientation) before
// this one existed — those are kept as the storage type for their own
// customProperties (avoids touching widget code that pattern-matches on
// them) and convert to/from this shared enum via the extensions in their own
// model files, so generic call sites (ButtonConfig's dispatch helpers,
// GeneralTab) can treat every orientation-supporting type uniformly.
// ─────────────────────────────────────────────────────────────────────────────

enum ControlOrientation { horizontal, vertical }

extension ControlOrientationInfo on ControlOrientation {
  String get label => switch (this) {
    ControlOrientation.horizontal => 'Horizontal',
    ControlOrientation.vertical => 'Vertical',
  };
}

ControlOrientation controlOrientationFromJson(
  dynamic value, {
  ControlOrientation fallback = ControlOrientation.vertical,
}) {
  if (value is String) {
    return ControlOrientation.values.firstWhere(
      (o) => o.name == value,
      orElse: () => fallback,
    );
  }
  return fallback;
}
