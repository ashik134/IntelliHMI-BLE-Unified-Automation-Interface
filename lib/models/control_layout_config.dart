import 'dart:convert';

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetType
// ─────────────────────────────────────────────────────────────────────────────

enum ControlWidgetType { sliderButton, pushButton, toggle, joystick }

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetSizeConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlWidgetSizeConfig {
  const ControlWidgetSizeConfig({
    this.hoistButtonHeightScale = 1.0,
    this.estopButtonHeightScale = 1.0,
  });

  static const double minHeightScale = 0.7;
  static const double maxHeightScale = 1.5;

  /// Base height for the hoist-button row.
  static const double baseHoistButtonHeight = 185.0;

  /// Base height for the E-Stop swipe button.
  static const double baseEstopButtonHeight = 74.0;

  /// Industrial HMI minimum touch target (per IEC 62264 / Material guidance).
  static const double minTouchTargetPx = 48.0;

  final double hoistButtonHeightScale;
  final double estopButtonHeightScale;

  double get resolvedHoistHeight =>
      baseHoistButtonHeight * hoistButtonHeightScale;

  double get resolvedEstopHeight =>
      baseEstopButtonHeight * estopButtonHeightScale;

  ControlWidgetSizeConfig copyWith({
    double? hoistButtonHeightScale,
    double? estopButtonHeightScale,
  }) {
    return ControlWidgetSizeConfig(
      hoistButtonHeightScale:
          hoistButtonHeightScale ?? this.hoistButtonHeightScale,
      estopButtonHeightScale:
          estopButtonHeightScale ?? this.estopButtonHeightScale,
    );
  }

  Map<String, dynamic> toJson() => {
    'hoistButtonHeightScale': hoistButtonHeightScale,
    'estopButtonHeightScale': estopButtonHeightScale,
  };

  factory ControlWidgetSizeConfig.fromJson(Map<String, dynamic> json) {
    return ControlWidgetSizeConfig(
      hoistButtonHeightScale:
          (json['hoistButtonHeightScale'] as num?)?.toDouble() ?? 1.0,
      estopButtonHeightScale:
          (json['estopButtonHeightScale'] as num?)?.toDouble() ?? 1.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlWidgetSizeConfig &&
          other.hoistButtonHeightScale == hoistButtonHeightScale &&
          other.estopButtonHeightScale == estopButtonHeightScale;

  @override
  int get hashCode =>
      Object.hash(hoistButtonHeightScale, estopButtonHeightScale);
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlLabelConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlLabelConfig {
  const ControlLabelConfig({
    this.upLabel = 'UP',
    this.downLabel = 'DOWN',
    this.estopSwipeInstruction = 'SWIPE TO EMERGENCY STOP',
    this.resetEstopLabel = 'RESET E-STOP',
    this.screenTitle = '',
  });

  static const int maxLabelLength = 18;
  static const int minLabelLength = 1;

  final String upLabel;
  final String downLabel;

  final String estopSwipeInstruction;

  final String resetEstopLabel;

  final String screenTitle;

  ControlLabelConfig copyWith({
    String? upLabel,
    String? downLabel,
    String? estopSwipeInstruction,
    String? resetEstopLabel,
    String? screenTitle,
  }) {
    return ControlLabelConfig(
      upLabel: upLabel ?? this.upLabel,
      downLabel: downLabel ?? this.downLabel,
      estopSwipeInstruction:
          estopSwipeInstruction ?? this.estopSwipeInstruction,
      resetEstopLabel: resetEstopLabel ?? this.resetEstopLabel,
      screenTitle: screenTitle ?? this.screenTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'upLabel': upLabel,
    'downLabel': downLabel,
    'estopSwipeInstruction': estopSwipeInstruction,
    'resetEstopLabel': resetEstopLabel,
    'screenTitle': screenTitle,
  };

  factory ControlLabelConfig.fromJson(Map<String, dynamic> json) {
    return ControlLabelConfig(
      upLabel: json['upLabel'] as String? ?? 'UP',
      downLabel: json['downLabel'] as String? ?? 'DOWN',
      estopSwipeInstruction:
          json['estopSwipeInstruction'] as String? ?? 'SWIPE TO EMERGENCY STOP',
      resetEstopLabel: json['resetEstopLabel'] as String? ?? 'RESET E-STOP',
      screenTitle: json['screenTitle'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlLabelConfig &&
          other.upLabel == upLabel &&
          other.downLabel == downLabel &&
          other.estopSwipeInstruction == estopSwipeInstruction &&
          other.resetEstopLabel == resetEstopLabel &&
          other.screenTitle == screenTitle;

  @override
  int get hashCode => Object.hash(
    upLabel,
    downLabel,
    estopSwipeInstruction,
    resetEstopLabel,
    screenTitle,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlArrangementConfig
// ─────────────────────────────────────────────────────────────────────────────

class ControlArrangementConfig {
  const ControlArrangementConfig({
    this.showSensorRow = true,
    this.showLiveLEDs = true,
  });

  final bool showSensorRow;

  final bool showLiveLEDs;

  ControlArrangementConfig copyWith({bool? showSensorRow, bool? showLiveLEDs}) {
    return ControlArrangementConfig(
      showSensorRow: showSensorRow ?? this.showSensorRow,
      showLiveLEDs: showLiveLEDs ?? this.showLiveLEDs,
    );
  }

  Map<String, dynamic> toJson() => {
    'showSensorRow': showSensorRow,
    'showLiveLEDs': showLiveLEDs,
  };

  factory ControlArrangementConfig.fromJson(Map<String, dynamic> json) {
    return ControlArrangementConfig(
      showSensorRow: json['showSensorRow'] as bool? ?? true,
      showLiveLEDs: json['showLiveLEDs'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlArrangementConfig &&
          other.showSensorRow == showSensorRow &&
          other.showLiveLEDs == showLiveLEDs;

  @override
  int get hashCode => Object.hash(showSensorRow, showLiveLEDs);
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlLayoutConfig  (top-level)
// ─────────────────────────────────────────────────────────────────────────────

class ControlLayoutConfig {
  const ControlLayoutConfig({
    this.widgetType = ControlWidgetType.sliderButton,
    this.sizeConfig = const ControlWidgetSizeConfig(),
    this.labelConfig = const ControlLabelConfig(),
    this.arrangementConfig = const ControlArrangementConfig(),
    this.pushConfig = const PushControlConfig(),
  });

  /// Active control widget type.  [sliderButton] and [toggle] are functional
  final ControlWidgetType widgetType;
  final ControlWidgetSizeConfig sizeConfig;
  final ControlLabelConfig labelConfig;
  final ControlArrangementConfig arrangementConfig;
  final PushControlConfig pushConfig;

  ControlLayoutConfig copyWith({
    ControlWidgetType? widgetType,
    ControlWidgetSizeConfig? sizeConfig,
    ControlLabelConfig? labelConfig,
    ControlArrangementConfig? arrangementConfig,
    PushControlConfig? pushConfig,
  }) {
    return ControlLayoutConfig(
      widgetType: widgetType ?? this.widgetType,
      sizeConfig: sizeConfig ?? this.sizeConfig,
      labelConfig: labelConfig ?? this.labelConfig,
      arrangementConfig: arrangementConfig ?? this.arrangementConfig,
      pushConfig: pushConfig ?? this.pushConfig,
    );
  }

  Map<String, dynamic> toJson() => {
    'widgetType': widgetType.name,
    'sizeConfig': sizeConfig.toJson(),
    'labelConfig': labelConfig.toJson(),
    'arrangementConfig': arrangementConfig.toJson(),
    'pushConfig': pushConfig.toJson(),
  };

  factory ControlLayoutConfig.fromJson(Map<String, dynamic> json) {
    final typeName = json['widgetType'] as String?;
    final widgetType = ControlWidgetType.values.firstWhere(
      (e) => e.name == typeName,
      orElse: () => ControlWidgetType.sliderButton,
    );
    return ControlLayoutConfig(
      widgetType: widgetType,
      sizeConfig: json['sizeConfig'] != null
          ? ControlWidgetSizeConfig.fromJson(
              json['sizeConfig'] as Map<String, dynamic>,
            )
          : const ControlWidgetSizeConfig(),
      labelConfig: json['labelConfig'] != null
          ? ControlLabelConfig.fromJson(
              json['labelConfig'] as Map<String, dynamic>,
            )
          : const ControlLabelConfig(),
      arrangementConfig: json['arrangementConfig'] != null
          ? ControlArrangementConfig.fromJson(
              json['arrangementConfig'] as Map<String, dynamic>,
            )
          : const ControlArrangementConfig(),
      pushConfig: json['pushConfig'] != null
          ? PushControlConfig.fromJson(
              json['pushConfig'] as Map<String, dynamic>,
            )
          : const PushControlConfig(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ControlLayoutConfig.fromJsonString(String source) {
    try {
      return ControlLayoutConfig.fromJson(
        jsonDecode(source) as Map<String, dynamic>,
      );
    } catch (_) {
      return const ControlLayoutConfig();
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ControlLayoutConfig &&
          other.widgetType == widgetType &&
          other.sizeConfig == sizeConfig &&
          other.labelConfig == labelConfig &&
          other.arrangementConfig == arrangementConfig &&
          other.pushConfig == pushConfig;

  @override
  int get hashCode => Object.hash(
    widgetType,
    sizeConfig,
    labelConfig,
    arrangementConfig,
    pushConfig,
  );
}

enum ToggleWiringConfig {
  /// 0-T  ·  Off → Momentary ON
  offMomentary,

  /// 0-R  ·  Off → Latched ON
  offLatched,

  /// R-0-R  ·  Latched ON → OFF → Latched ON
  latchedOffLatched,

  /// T-0-R  ·  Momentary ON (UP) → OFF → Latched ON (DOWN)
  momentaryUpLatchedDown,

  /// T-0-T  ·  Momentary ON → OFF → Momentary ON
  dualMomentary,
}

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonWiringConfig
//
// Industrial electrical wiring terminology for the toggle switch mechanism.
// Maps directly to the five standard 2-position / 3-position switch schemas
// used in industrial HMI panel design.
// ─────────────────────────────────────────────────────────────────────────────

enum PushButtonWiringConfig { offMomentary, offLatched }

// ─────────────────────────────────────────────────────────────────────────────
// PushButtonWiringConfig helpers
// ─────────────────────────────────────────────────────────────────────────────

extension PushButtonWiringConfigInfo on PushButtonWiringConfig {
  String get label {
    switch (this) {
      case PushButtonWiringConfig.offMomentary:
        return '0-T  ·  Off → Momentary';
      case PushButtonWiringConfig.offLatched:
        return '0-R  ·  Off → Latched';
    }
  }

  String get description {
    switch (this) {
      case PushButtonWiringConfig.offMomentary:
        return 'Hold either button to run. Release to stop. Both directions spring-return.';
      case PushButtonWiringConfig.offLatched:
        return 'Tap UP to start lifting; tap again to stop. Same for DOWN. Independent latching.';
    }
  }

  bool get upIsSpringReturn {
    switch (this) {
      case PushButtonWiringConfig.offMomentary:
        return true;
      case PushButtonWiringConfig.offLatched:
        return false;
    }
  }

  bool get downIsSpringReturn {
    switch (this) {
      case PushButtonWiringConfig.offMomentary:
        return true;
      case PushButtonWiringConfig.offLatched:
        return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PushControlConfig
//
// Configuration for toggle-mode hoist controls.
// Stored within ControlLayoutConfig when widgetType == toggle.
// ─────────────────────────────────────────────────────────────────────────────

class PushControlConfig {
  const PushControlConfig({
    this.wiringConfig = PushButtonWiringConfig.offMomentary,
  });

  /// The wiring schema that determines spring-return vs latched behaviour
  /// per button and mutual exclusion rules.
  final PushButtonWiringConfig wiringConfig;

  PushControlConfig copyWith({PushButtonWiringConfig? wiringConfig}) {
    return PushControlConfig(wiringConfig: wiringConfig ?? this.wiringConfig);
  }

  Map<String, dynamic> toJson() => {'wiringConfig': wiringConfig.name};

  factory PushControlConfig.fromJson(Map<String, dynamic> json) {
    final name = json['wiringConfig'] as String?;
    return PushControlConfig(
      wiringConfig: PushButtonWiringConfig.values.firstWhere(
        (e) => e.name == name,
        orElse: () => PushButtonWiringConfig.offMomentary,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PushControlConfig && other.wiringConfig == wiringConfig;

  @override
  int get hashCode => wiringConfig.hashCode;
}
