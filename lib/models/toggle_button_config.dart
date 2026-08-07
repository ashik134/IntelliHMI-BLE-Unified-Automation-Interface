import 'package:rev_crane_control_ops/models/control_orientation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToggleButtonConfig
//
// Backs ButtonType.toggle (all 5 catalogue wiring variants — see
// PushButtonWiringConfig). ToggleSwitchButton already renders two
// independent end labels (topLabel/bottomLabel, "left"/"right" in this
// model's naming — see ToggleSwitchPosition's doc comment: left = top of the
// vertical lever) and already defaults them from the wiring mode's O/T/R
// glyphs; this config lets the operator override those labels, override each
// side's icon, and disable one side entirely (forces that side permanently
// inert regardless of wiring mode).
// ─────────────────────────────────────────────────────────────────────────────

class ToggleButtonConfig {
  const ToggleButtonConfig({
    this.leftLabel,
    this.rightLabel,
    this.leftIconKey,
    this.rightIconKey,
    this.disableLeft = false,
    this.disableRight = false,
    this.orientation = ControlOrientation.vertical,
  });

  static const String customPropertiesKey = 'toggleButton';

  /// Top-of-lever side. Null keeps the wiring mode's own default glyph
  /// (O/T/R — see ToggleSwitchButton.resolvedTopLabel).
  final String? leftLabel;

  /// Bottom-of-lever side.
  final String? rightLabel;

  /// Icon-registry keys (see button_icon_registry.dart) — null keeps no
  /// per-side icon (today's behavior: only the overall widget icon/label
  /// footer is shown, the lever itself has no per-side icon).
  final String? leftIconKey;
  final String? rightIconKey;

  final bool disableLeft;
  final bool disableRight;

  /// Lever axis — vertical (default, today's only behavior: "left"/top and
  /// "right"/bottom are the two ends of a vertical lever) or horizontal
  /// (left/right ends of a horizontal lever). See
  /// ButtonConfig.supportsOrientation/orientationOf.
  final ControlOrientation orientation;

  ToggleButtonConfig copyWith({
    String? leftLabel,
    String? rightLabel,
    String? leftIconKey,
    String? rightIconKey,
    bool? disableLeft,
    bool? disableRight,
    ControlOrientation? orientation,
    bool clearLeftLabel = false,
    bool clearRightLabel = false,
    bool clearLeftIconKey = false,
    bool clearRightIconKey = false,
  }) {
    return ToggleButtonConfig(
      leftLabel: clearLeftLabel ? null : (leftLabel ?? this.leftLabel),
      rightLabel: clearRightLabel ? null : (rightLabel ?? this.rightLabel),
      leftIconKey: clearLeftIconKey
          ? null
          : (leftIconKey ?? this.leftIconKey),
      rightIconKey: clearRightIconKey
          ? null
          : (rightIconKey ?? this.rightIconKey),
      disableLeft: disableLeft ?? this.disableLeft,
      disableRight: disableRight ?? this.disableRight,
      orientation: orientation ?? this.orientation,
    );
  }

  Map<String, dynamic> toJson() => {
    'leftLabel': leftLabel,
    'rightLabel': rightLabel,
    'leftIconKey': leftIconKey,
    'rightIconKey': rightIconKey,
    'disableLeft': disableLeft,
    'disableRight': disableRight,
    'orientation': orientation.name,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory ToggleButtonConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return ToggleButtonConfig.fromJson(raw);
    if (raw is Map) {
      return ToggleButtonConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const ToggleButtonConfig();
  }

  factory ToggleButtonConfig.fromJson(Map<String, dynamic> json) {
    return ToggleButtonConfig(
      leftLabel: _cleanNullable(json['leftLabel'] as String?),
      rightLabel: _cleanNullable(json['rightLabel'] as String?),
      leftIconKey: _cleanNullable(json['leftIconKey'] as String?),
      rightIconKey: _cleanNullable(json['rightIconKey'] as String?),
      disableLeft: json['disableLeft'] as bool? ?? false,
      disableRight: json['disableRight'] as bool? ?? false,
      orientation: controlOrientationFromJson(json['orientation']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ToggleButtonConfig &&
          other.leftLabel == leftLabel &&
          other.rightLabel == rightLabel &&
          other.leftIconKey == leftIconKey &&
          other.rightIconKey == rightIconKey &&
          other.disableLeft == disableLeft &&
          other.disableRight == disableRight &&
          other.orientation == orientation;

  @override
  int get hashCode => Object.hash(
    leftLabel,
    rightLabel,
    leftIconKey,
    rightIconKey,
    disableLeft,
    disableRight,
    orientation,
  );
}

String? _cleanNullable(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
