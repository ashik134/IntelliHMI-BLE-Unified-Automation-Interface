import 'dart:convert';

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetType
//
// Placeholder enum for future control widget type switching.
// Currently only [sliderButton] is implemented and wired into the UI.
// Additional types will be enabled in a future release.
// ─────────────────────────────────────────────────────────────────────────────

enum ControlWidgetType {
  sliderButton,
  pressAndHold,
  toggle,
  joystick,
}

// ─────────────────────────────────────────────────────────────────────────────
// ControlWidgetSizeConfig
//
// Scale factors applied against base logical-pixel dimensions.
// All factors are clamped to [minHeightScale, maxHeightScale] by the
// LayoutValidationService before being stored.
// ─────────────────────────────────────────────────────────────────────────────

class ControlWidgetSizeConfig {
  const ControlWidgetSizeConfig({
    this.hoistButtonHeightScale = 1.0,
    this.estopButtonHeightScale = 1.0,
  });

  static const double minHeightScale = 0.7;
  static const double maxHeightScale = 1.5;

  /// Base height (logical pixels) for the hoist-button row.
  static const double baseHoistButtonHeight = 185.0;

  /// Base height (logical pixels) for the E-Stop swipe button.
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
//
// Operator-configurable display labels for all named UI elements.
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

  /// Instruction text shown inside the E-Stop swipe button track.
  final String estopSwipeInstruction;

  /// Label for the reset E-Stop action button.
  final String resetEstopLabel;

  /// When non-empty, overrides the connected device name in the AppBar.
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
          json['estopSwipeInstruction'] as String? ??
          'SWIPE TO EMERGENCY STOP',
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
//
// Toggles which optional diagnostic sections are visible on the control screen.
// ─────────────────────────────────────────────────────────────────────────────

class ControlArrangementConfig {
  const ControlArrangementConfig({
    this.showSensorRow = true,
    this.showLiveLEDs = true,
  });

  /// Whether the A1/A2 load-sensor row is shown.
  final bool showSensorRow;

  /// Whether the live PLC output LED indicators row is shown.
  final bool showLiveLEDs;

  ControlArrangementConfig copyWith({
    bool? showSensorRow,
    bool? showLiveLEDs,
  }) {
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
//
// Aggregates all sub-configurations.  Serialised to / from JSON for
// persistence via SharedPreferences.
// ─────────────────────────────────────────────────────────────────────────────

class ControlLayoutConfig {
  const ControlLayoutConfig({
    this.widgetType = ControlWidgetType.sliderButton,
    this.sizeConfig = const ControlWidgetSizeConfig(),
    this.labelConfig = const ControlLabelConfig(),
    this.arrangementConfig = const ControlArrangementConfig(),
  });

  /// Intended control widget type.  Only [ControlWidgetType.sliderButton] is
  /// currently functional; other values are persisted but not yet rendered.
  final ControlWidgetType widgetType;
  final ControlWidgetSizeConfig sizeConfig;
  final ControlLabelConfig labelConfig;
  final ControlArrangementConfig arrangementConfig;

  ControlLayoutConfig copyWith({
    ControlWidgetType? widgetType,
    ControlWidgetSizeConfig? sizeConfig,
    ControlLabelConfig? labelConfig,
    ControlArrangementConfig? arrangementConfig,
  }) {
    return ControlLayoutConfig(
      widgetType: widgetType ?? this.widgetType,
      sizeConfig: sizeConfig ?? this.sizeConfig,
      labelConfig: labelConfig ?? this.labelConfig,
      arrangementConfig: arrangementConfig ?? this.arrangementConfig,
    );
  }

  Map<String, dynamic> toJson() => {
    'widgetType': widgetType.name,
    'sizeConfig': sizeConfig.toJson(),
    'labelConfig': labelConfig.toJson(),
    'arrangementConfig': arrangementConfig.toJson(),
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
          other.arrangementConfig == arrangementConfig;

  @override
  int get hashCode =>
      Object.hash(widgetType, sizeConfig, labelConfig, arrangementConfig);
}
