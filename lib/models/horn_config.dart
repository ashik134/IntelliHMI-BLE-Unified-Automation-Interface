// ─────────────────────────────────────────────────────────────────────────────
// HornConfig
//
// Custom-properties bag for ButtonType.horn, mirroring PotentiometerConfig's
// shape/conventions exactly (own JSON namespace under
// ButtonConfig.customProperties, normalized()/copyWith()/toJson()/fromJson).
// The horn itself is a plain digital (boolean) output — real composition
// still goes through ButtonConfig.stateMappings via the normal idle/active
// logicalStates, same as ButtonType.pushButton. This config only carries the
// cosmetic/behavioral extras (beep style, haptic/sound toggles) that don't
// fit the generic push-button model.
// ─────────────────────────────────────────────────────────────────────────────

enum HornSoundPattern { steady, pulsing, doubleBeep }

class HornConfig {
  const HornConfig({
    this.soundPattern = HornSoundPattern.steady,
    this.hapticFeedback = true,
    this.visualBeepAnimation = true,
  });

  static const String customPropertiesKey = 'horn';

  final HornSoundPattern soundPattern;
  final bool hapticFeedback;
  final bool visualBeepAnimation;

  HornConfig copyWith({
    HornSoundPattern? soundPattern,
    bool? hapticFeedback,
    bool? visualBeepAnimation,
  }) {
    return HornConfig(
      soundPattern: soundPattern ?? this.soundPattern,
      hapticFeedback: hapticFeedback ?? this.hapticFeedback,
      visualBeepAnimation: visualBeepAnimation ?? this.visualBeepAnimation,
    );
  }

  Map<String, dynamic> toJson() => {
    'soundPattern': soundPattern.name,
    'hapticFeedback': hapticFeedback,
    'visualBeepAnimation': visualBeepAnimation,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory HornConfig.fromCustomProperties(Map<String, dynamic> properties) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return HornConfig.fromJson(raw);
    if (raw is Map) return HornConfig.fromJson(raw.cast<String, dynamic>());
    return const HornConfig();
  }

  factory HornConfig.fromJson(Map<String, dynamic> json) {
    return HornConfig(
      soundPattern: HornSoundPattern.values.firstWhere(
        (e) => e.name == json['soundPattern'],
        orElse: () => HornSoundPattern.steady,
      ),
      hapticFeedback: json['hapticFeedback'] as bool? ?? true,
      visualBeepAnimation: json['visualBeepAnimation'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HornConfig &&
          other.soundPattern == soundPattern &&
          other.hapticFeedback == hapticFeedback &&
          other.visualBeepAnimation == visualBeepAnimation;

  @override
  int get hashCode =>
      Object.hash(soundPattern, hapticFeedback, visualBeepAnimation);
}
