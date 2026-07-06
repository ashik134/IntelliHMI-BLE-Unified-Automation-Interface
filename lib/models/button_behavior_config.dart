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
  });

  static const int minRepeatIntervalMs = 50;
  static const int maxRepeatIntervalMs = 1000;

  final PushButtonWiringConfig wiring;
  final bool repeatWhileHeld;
  final int repeatIntervalMs;

  bool get isSpringReturn => wiring.isSpringReturn;

  ButtonBehaviorConfig copyWith({
    PushButtonWiringConfig? wiring,
    bool? repeatWhileHeld,
    int? repeatIntervalMs,
  }) {
    return ButtonBehaviorConfig(
      wiring: wiring ?? this.wiring,
      repeatWhileHeld: repeatWhileHeld ?? this.repeatWhileHeld,
      repeatIntervalMs: repeatIntervalMs ?? this.repeatIntervalMs,
    );
  }

  Map<String, dynamic> toJson() => {
    'wiring': wiring.name,
    'repeatWhileHeld': repeatWhileHeld,
    'repeatIntervalMs': repeatIntervalMs,
  };

  factory ButtonBehaviorConfig.fromJson(Map<String, dynamic> json) {
    return ButtonBehaviorConfig(
      wiring: PushButtonWiringConfig.values.firstWhere(
        (e) => e.name == json['wiring'],
        orElse: () => PushButtonWiringConfig.offMomentary,
      ),
      repeatWhileHeld: json['repeatWhileHeld'] as bool? ?? false,
      repeatIntervalMs: (json['repeatIntervalMs'] as num?)?.toInt() ?? 150,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ButtonBehaviorConfig &&
          other.wiring == wiring &&
          other.repeatWhileHeld == repeatWhileHeld &&
          other.repeatIntervalMs == repeatIntervalMs;

  @override
  int get hashCode => Object.hash(wiring, repeatWhileHeld, repeatIntervalMs);
}
