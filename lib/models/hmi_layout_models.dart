import 'dart:math';

import 'package:flutter/material.dart';

enum HmiWidgetType {
  estop,
  hoistSlider,
  potentiometer,
  analogJoystick,
  digitalJoystick,
  toggleSwitch,
  analogMeter,
  valueIndicator,
}

extension HmiWidgetTypeX on HmiWidgetType {
  String get key => switch (this) {
    HmiWidgetType.estop => 'estop',
    HmiWidgetType.hoistSlider => 'hoist_slider',
    HmiWidgetType.potentiometer => 'potentiometer',
    HmiWidgetType.analogJoystick => 'analog_joystick',
    HmiWidgetType.digitalJoystick => 'digital_joystick',
    HmiWidgetType.toggleSwitch => 'toggle_switch',
    HmiWidgetType.analogMeter => 'analog_meter',
    HmiWidgetType.valueIndicator => 'value_indicator',
  };

  String get displayName => switch (this) {
    HmiWidgetType.estop => 'E-Stop',
    HmiWidgetType.hoistSlider => 'Hoist Slider',
    HmiWidgetType.potentiometer => 'Potentiometer',
    HmiWidgetType.analogJoystick => 'Analog Joystick',
    HmiWidgetType.digitalJoystick => 'Digital Joystick',
    HmiWidgetType.toggleSwitch => 'Toggle Switch',
    HmiWidgetType.analogMeter => 'Analog Meter',
    HmiWidgetType.valueIndicator => 'Value Indicator',
  };

  static HmiWidgetType fromKey(String? key) {
    return HmiWidgetType.values.firstWhere(
      (type) => type.key == key,
      orElse: () => HmiWidgetType.valueIndicator,
    );
  }
}

enum ControlHoldMode { springReturn, maintained, latching }

extension ControlHoldModeX on ControlHoldMode {
  String get key => switch (this) {
    ControlHoldMode.springReturn => 'spring_return',
    ControlHoldMode.maintained => 'maintained',
    ControlHoldMode.latching => 'latching',
  };

  String get displayName => switch (this) {
    ControlHoldMode.springReturn => 'Spring Return',
    ControlHoldMode.maintained => 'Maintained',
    ControlHoldMode.latching => 'Latching',
  };

  static ControlHoldMode fromKey(String? key) {
    return ControlHoldMode.values.firstWhere(
      (mode) => mode.key == key,
      orElse: () => ControlHoldMode.springReturn,
    );
  }
}

enum TogglePattern {
  zeroMomentary,
  zeroLatched,
  latchedZeroLatched,
  momentaryZeroLatched,
  momentaryZeroMomentary,
}

extension TogglePatternX on TogglePattern {
  String get key => switch (this) {
    TogglePattern.zeroMomentary => '0-T',
    TogglePattern.zeroLatched => '0-R',
    TogglePattern.latchedZeroLatched => 'R-0-R',
    TogglePattern.momentaryZeroLatched => 'T-0-R',
    TogglePattern.momentaryZeroMomentary => 'T-0-T',
  };

  static TogglePattern fromKey(String? key) {
    return TogglePattern.values.firstWhere(
      (pattern) => pattern.key == key,
      orElse: () => TogglePattern.zeroMomentary,
    );
  }
}

class HmiWidgetLayout {
  const HmiWidgetLayout({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;

  HmiWidgetLayout normalized({double minWidth = 0.1, double minHeight = 0.08}) {
    final clampedWidth = width.clamp(minWidth, 1.0).toDouble();
    final clampedHeight = height.clamp(minHeight, 1.0).toDouble();
    return HmiWidgetLayout(
      x: x.clamp(0.0, (1.0 - clampedWidth)).toDouble(),
      y: y.clamp(0.0, (1.0 - clampedHeight)).toDouble(),
      width: clampedWidth,
      height: clampedHeight,
    );
  }

  HmiWidgetLayout moveBy(double deltaX, double deltaY) {
    return copyWith(x: x + deltaX, y: y + deltaY).normalized();
  }

  HmiWidgetLayout resizeBy(double deltaWidth, double deltaHeight) {
    return copyWith(
      width: width + deltaWidth,
      height: height + deltaHeight,
    ).normalized();
  }

  bool overlaps(HmiWidgetLayout other) {
    return x < other.x + other.width &&
        x + width > other.x &&
        y < other.y + other.height &&
        y + height > other.y;
  }

  HmiWidgetLayout copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    return HmiWidgetLayout(
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y, 'width': width, 'height': height};
  }

  factory HmiWidgetLayout.fromJson(Map<String, dynamic> json) {
    return HmiWidgetLayout(
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      width: (json['width'] as num?)?.toDouble() ?? 0.25,
      height: (json['height'] as num?)?.toDouble() ?? 0.2,
    ).normalized();
  }
}

class PlcBindingConfig {
  const PlcBindingConfig({
    required this.primaryTag,
    this.secondaryTag,
    this.tertiaryTag,
    this.quaternaryTag,
    this.invert = false,
  });

  final String primaryTag;
  final String? secondaryTag;
  final String? tertiaryTag;
  final String? quaternaryTag;
  final bool invert;

  PlcBindingConfig copyWith({
    String? primaryTag,
    String? secondaryTag,
    String? tertiaryTag,
    String? quaternaryTag,
    bool? invert,
  }) {
    return PlcBindingConfig(
      primaryTag: primaryTag ?? this.primaryTag,
      secondaryTag: secondaryTag ?? this.secondaryTag,
      tertiaryTag: tertiaryTag ?? this.tertiaryTag,
      quaternaryTag: quaternaryTag ?? this.quaternaryTag,
      invert: invert ?? this.invert,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'primaryTag': primaryTag,
      'secondaryTag': secondaryTag,
      'tertiaryTag': tertiaryTag,
      'quaternaryTag': quaternaryTag,
      'invert': invert,
    };
  }

  factory PlcBindingConfig.fromJson(Map<String, dynamic> json) {
    return PlcBindingConfig(
      primaryTag: json['primaryTag'] as String? ?? '',
      secondaryTag: json['secondaryTag'] as String?,
      tertiaryTag: json['tertiaryTag'] as String?,
      quaternaryTag: json['quaternaryTag'] as String?,
      invert: json['invert'] as bool? ?? false,
    );
  }
}

class HmiBehaviorConfig {
  const HmiBehaviorConfig({
    this.holdMode = ControlHoldMode.springReturn,
    this.togglePattern = TogglePattern.zeroMomentary,
    this.twoAxis = false,
    this.enableXAxis = true,
    this.enableYAxis = false,
    this.dualDirectionX = true,
    this.dualDirectionY = true,
    this.stepCountX = 1,
    this.stepCountY = 1,
    this.twoStepMode = false,
    this.deadZonePercent = 8,
    this.minValue = 0,
    this.maxValue = 100,
    this.unit = '',
    this.invertScale = false,
    this.trendEnabled = false,
    this.warningThreshold,
    this.alarmThreshold,
  });

  final ControlHoldMode holdMode;
  final TogglePattern togglePattern;
  final bool twoAxis;
  final bool enableXAxis;
  final bool enableYAxis;
  final bool dualDirectionX;
  final bool dualDirectionY;
  final int stepCountX;
  final int stepCountY;
  final bool twoStepMode;
  final int deadZonePercent;
  final double minValue;
  final double maxValue;
  final String unit;
  final bool invertScale;
  final bool trendEnabled;
  final double? warningThreshold;
  final double? alarmThreshold;

  HmiBehaviorConfig copyWith({
    ControlHoldMode? holdMode,
    TogglePattern? togglePattern,
    bool? twoAxis,
    bool? enableXAxis,
    bool? enableYAxis,
    bool? dualDirectionX,
    bool? dualDirectionY,
    int? stepCountX,
    int? stepCountY,
    bool? twoStepMode,
    int? deadZonePercent,
    double? minValue,
    double? maxValue,
    String? unit,
    bool? invertScale,
    bool? trendEnabled,
    double? warningThreshold,
    double? alarmThreshold,
    bool clearWarningThreshold = false,
    bool clearAlarmThreshold = false,
  }) {
    return HmiBehaviorConfig(
      holdMode: holdMode ?? this.holdMode,
      togglePattern: togglePattern ?? this.togglePattern,
      twoAxis: twoAxis ?? this.twoAxis,
      enableXAxis: enableXAxis ?? this.enableXAxis,
      enableYAxis: enableYAxis ?? this.enableYAxis,
      dualDirectionX: dualDirectionX ?? this.dualDirectionX,
      dualDirectionY: dualDirectionY ?? this.dualDirectionY,
      stepCountX: max(1, stepCountX ?? this.stepCountX),
      stepCountY: max(1, stepCountY ?? this.stepCountY),
      twoStepMode: twoStepMode ?? this.twoStepMode,
      deadZonePercent: (deadZonePercent ?? this.deadZonePercent).clamp(0, 40),
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      unit: unit ?? this.unit,
      invertScale: invertScale ?? this.invertScale,
      trendEnabled: trendEnabled ?? this.trendEnabled,
      warningThreshold: clearWarningThreshold
          ? null
          : (warningThreshold ?? this.warningThreshold),
      alarmThreshold: clearAlarmThreshold
          ? null
          : (alarmThreshold ?? this.alarmThreshold),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'holdMode': holdMode.key,
      'togglePattern': togglePattern.key,
      'twoAxis': twoAxis,
      'enableXAxis': enableXAxis,
      'enableYAxis': enableYAxis,
      'dualDirectionX': dualDirectionX,
      'dualDirectionY': dualDirectionY,
      'stepCountX': stepCountX,
      'stepCountY': stepCountY,
      'twoStepMode': twoStepMode,
      'deadZonePercent': deadZonePercent,
      'minValue': minValue,
      'maxValue': maxValue,
      'unit': unit,
      'invertScale': invertScale,
      'trendEnabled': trendEnabled,
      'warningThreshold': warningThreshold,
      'alarmThreshold': alarmThreshold,
    };
  }

  factory HmiBehaviorConfig.fromJson(Map<String, dynamic> json) {
    final minValue = (json['minValue'] as num?)?.toDouble() ?? 0;
    final maxValue = (json['maxValue'] as num?)?.toDouble() ?? 100;
    return HmiBehaviorConfig(
      holdMode: ControlHoldModeX.fromKey(json['holdMode'] as String?),
      togglePattern: TogglePatternX.fromKey(json['togglePattern'] as String?),
      twoAxis: json['twoAxis'] as bool? ?? false,
      enableXAxis: json['enableXAxis'] as bool? ?? true,
      enableYAxis: json['enableYAxis'] as bool? ?? false,
      dualDirectionX: json['dualDirectionX'] as bool? ?? true,
      dualDirectionY: json['dualDirectionY'] as bool? ?? true,
      stepCountX: max(1, json['stepCountX'] as int? ?? 1),
      stepCountY: max(1, json['stepCountY'] as int? ?? 1),
      twoStepMode: json['twoStepMode'] as bool? ?? false,
      deadZonePercent: (json['deadZonePercent'] as int? ?? 8).clamp(0, 40),
      minValue: minValue,
      maxValue: max(maxValue, minValue + 0.1),
      unit: json['unit'] as String? ?? '',
      invertScale: json['invertScale'] as bool? ?? false,
      trendEnabled: json['trendEnabled'] as bool? ?? false,
      warningThreshold: (json['warningThreshold'] as num?)?.toDouble(),
      alarmThreshold: (json['alarmThreshold'] as num?)?.toDouble(),
    );
  }
}

class HmiWidgetConfig {
  const HmiWidgetConfig({
    required this.id,
    required this.type,
    required this.label,
    required this.layout,
    required this.binding,
    required this.behavior,
    this.color = const Color(0xFF4BB7F3),
    this.enabled = true,
    this.visible = true,
    this.settings = const <String, dynamic>{},
  });

  final String id;
  final HmiWidgetType type;
  final String label;
  final HmiWidgetLayout layout;
  final PlcBindingConfig binding;
  final HmiBehaviorConfig behavior;
  final Color color;
  final bool enabled;
  final bool visible;
  final Map<String, dynamic> settings;

  HmiWidgetConfig copyWith({
    String? id,
    HmiWidgetType? type,
    String? label,
    HmiWidgetLayout? layout,
    PlcBindingConfig? binding,
    HmiBehaviorConfig? behavior,
    Color? color,
    bool? enabled,
    bool? visible,
    Map<String, dynamic>? settings,
  }) {
    return HmiWidgetConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      layout: (layout ?? this.layout).normalized(),
      binding: binding ?? this.binding,
      behavior: behavior ?? this.behavior,
      color: color ?? this.color,
      enabled: enabled ?? this.enabled,
      visible: visible ?? this.visible,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.key,
      'label': label,
      'layout': layout.toJson(),
      'binding': binding.toJson(),
      'behavior': behavior.toJson(),
      'color': color.toARGB32(),
      'enabled': enabled,
      'visible': visible,
      'settings': settings,
    };
  }

  factory HmiWidgetConfig.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    return HmiWidgetConfig(
      id: json['id'] as String,
      type: HmiWidgetTypeX.fromKey(json['type'] as String?),
      label: json['label'] as String? ?? 'Control',
      layout: HmiWidgetLayout.fromJson(
        (json['layout'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      binding: PlcBindingConfig.fromJson(
        (json['binding'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      behavior: HmiBehaviorConfig.fromJson(
        (json['behavior'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      ),
      color: Color(
        (json['color'] as int?) ?? const Color(0xFF4BB7F3).toARGB32(),
      ),
      enabled: json['enabled'] as bool? ?? true,
      visible: json['visible'] as bool? ?? true,
      settings: rawSettings is Map
          ? rawSettings.cast<String, dynamic>()
          : const <String, dynamic>{},
    );
  }
}

class HmiLayoutProfile {
  const HmiLayoutProfile({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.updatedAt,
    required this.widgets,
    this.version = 1,
    this.template = 'free',
  });

  final String id;
  final String name;
  final String deviceType;
  final DateTime updatedAt;
  final List<HmiWidgetConfig> widgets;
  final int version;
  final String template;

  HmiLayoutProfile copyWith({
    String? id,
    String? name,
    String? deviceType,
    DateTime? updatedAt,
    List<HmiWidgetConfig>? widgets,
    int? version,
    String? template,
  }) {
    return HmiLayoutProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      deviceType: deviceType ?? this.deviceType,
      updatedAt: updatedAt ?? this.updatedAt,
      widgets: widgets ?? this.widgets,
      version: version ?? this.version,
      template: template ?? this.template,
    );
  }

  HmiWidgetConfig? widgetById(String id) {
    for (final widget in widgets) {
      if (widget.id == id) {
        return widget;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'deviceType': deviceType,
      'updatedAt': updatedAt.toIso8601String(),
      'widgets': widgets.map((widget) => widget.toJson()).toList(),
      'version': version,
      'template': template,
    };
  }

  factory HmiLayoutProfile.fromJson(Map<String, dynamic> json) {
    final widgetList = (json['widgets'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => HmiWidgetConfig.fromJson(item.cast<String, dynamic>()))
        .toList();
    return HmiLayoutProfile(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Unnamed Profile',
      deviceType: json['deviceType'] as String? ?? 'generic',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      widgets: widgetList,
      version: json['version'] as int? ?? 1,
      template: json['template'] as String? ?? 'free',
    );
  }
}

enum LayoutIssueType { overlap, outOfBounds, hidden, missingBinding }

class LayoutIssue {
  const LayoutIssue({
    required this.type,
    required this.widgetId,
    required this.message,
  });

  final LayoutIssueType type;
  final String widgetId;
  final String message;
}
