import 'package:rev_crane_control_ops/models/control_layout_config.dart'
    show PushButtonWiringConfig, PushButtonWiringConfigInfo;

// ─────────────────────────────────────────────────────────────────────────────
// ButtonBehaviorConfig
//
// Generalizes PushButtonWiringConfig (spring/latch — reused as-is, not
// duplicated) plus a repeat-while-held concept for future button types.
// Every current PLC14/PLC38 button type is continuous-motion, not
// increment/jog, so repeatWhileHeld is modeled but unused today — kept
// because it's explicitly named in the button-centric spec and a future
// jog-increment button type would need it.
// ─────────────────────────────────────────────────────────────────────────────

class ButtonBehaviorConfig {
  const ButtonBehaviorConfig({
    this.wiring = PushButtonWiringConfig.offMomentary,
    this.repeatWhileHeld = false,
    this.repeatIntervalMs = 150,
    this.debounceMs = 0,
    this.longPressRequiredMs = 0,
    this.pressAnimationStrength = defaultPressAnimationStrength,
  });

  static const int minRepeatIntervalMs = 50;
  static const int maxRepeatIntervalMs = 1000;

  /// 0 disables debouncing entirely (today's exact behavior — every
  /// pointer-down is honored immediately).
  static const int minDebounceMs = 0;
  static const int maxDebounceMs = 2000;

  /// 0 disables the long-press requirement (today's exact behavior — a
  /// spring-return push button activates on pointer-down).
  static const int minLongPressRequiredMs = 0;
  static const int maxLongPressRequiredMs = 3000;

  static const double minPressAnimationStrength = 0.0;
  static const double maxPressAnimationStrength = 1.0;

  /// Reproduces IndustrialSpringButton's pre-existing hardcoded
  /// `pressScale: 0.965` default exactly — see [pressScaleFor].
  static const double defaultPressAnimationStrength = 0.35;

  final PushButtonWiringConfig wiring;
  final bool repeatWhileHeld;
  final int repeatIntervalMs;

  /// Minimum interval between accepting a new press after the previous
  /// release, for push buttons only. See PushButtonStrategy/
  /// IndustrialSpringButton's pointer-down handling.
  final int debounceMs;

  /// Spring-return push buttons only: holds the pointer-down for this long
  /// before the press actually activates/dispatches, so a quick tap on a
  /// risky action is ignored. 0 = tap-to-activate (today's behavior).
  final int longPressRequiredMs;

  /// 0..1 — how strongly a push button visibly shrinks on press. Converted
  /// to IndustrialSpringButton's `pressScale` via [pressScaleFor]
  /// (`pressScale = 1.0 - strength * 0.1`, so the default value round-trips
  /// to the widget's original hardcoded 0.965).
  final double pressAnimationStrength;

  bool get isSpringReturn => wiring.isSpringReturn;

  /// See [pressAnimationStrength]'s doc comment for the mapping.
  double get pressScale => 1.0 - pressAnimationStrength * 0.1;

  ButtonBehaviorConfig copyWith({
    PushButtonWiringConfig? wiring,
    bool? repeatWhileHeld,
    int? repeatIntervalMs,
    int? debounceMs,
    int? longPressRequiredMs,
    double? pressAnimationStrength,
  }) {
    return ButtonBehaviorConfig(
      wiring: wiring ?? this.wiring,
      repeatWhileHeld: repeatWhileHeld ?? this.repeatWhileHeld,
      repeatIntervalMs: repeatIntervalMs ?? this.repeatIntervalMs,
      debounceMs: debounceMs ?? this.debounceMs,
      longPressRequiredMs: longPressRequiredMs ?? this.longPressRequiredMs,
      pressAnimationStrength:
          pressAnimationStrength ?? this.pressAnimationStrength,
    );
  }

  Map<String, dynamic> toJson() => {
    'wiring': wiring.name,
    'repeatWhileHeld': repeatWhileHeld,
    'repeatIntervalMs': repeatIntervalMs,
    'debounceMs': debounceMs,
    'longPressRequiredMs': longPressRequiredMs,
    'pressAnimationStrength': pressAnimationStrength,
  };

  factory ButtonBehaviorConfig.fromJson(Map<String, dynamic> json) {
    return ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.values.firstWhere(
        (e) => e.name == json['wiring'],
        orElse: () => PushButtonWiringConfig.offMomentary,
      ),
      repeatWhileHeld: json['repeatWhileHeld'] as bool? ?? false,
      repeatIntervalMs: (json['repeatIntervalMs'] as num?)?.toInt() ?? 150,
      debounceMs: (json['debounceMs'] as num?)?.toInt() ?? 0,
      longPressRequiredMs:
          (json['longPressRequiredMs'] as num?)?.toInt() ?? 0,
      pressAnimationStrength:
          (json['pressAnimationStrength'] as num?)?.toDouble() ??
          defaultPressAnimationStrength,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonBehaviorConfig &&
          other.wiring == wiring &&
          other.repeatWhileHeld == repeatWhileHeld &&
          other.repeatIntervalMs == repeatIntervalMs &&
          other.debounceMs == debounceMs &&
          other.longPressRequiredMs == longPressRequiredMs &&
          other.pressAnimationStrength == pressAnimationStrength;

  @override
  int get hashCode => Object.hash(
    wiring,
    repeatWhileHeld,
    repeatIntervalMs,
    debounceMs,
    longPressRequiredMs,
    pressAnimationStrength,
  );
}
