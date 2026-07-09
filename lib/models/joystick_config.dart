import 'dart:math' as math;

enum JoystickMode {
  singleAxisAnalog,
  singleAxisDigital5,
  dualAxisAnalog,
  dualAxisDigital4,
}

enum JoystickAxis { horizontal, vertical }

enum JoystickBoundary { circular, square }

class JoystickConfig {
  const JoystickConfig({
    this.mode = JoystickMode.singleAxisDigital5,
    this.axis = JoystickAxis.vertical,
    this.boundary = JoystickBoundary.circular,
    this.springReturn = true,
    this.deadZone = 0.18,
    this.slowThreshold = 0.28,
    this.fastThreshold = 0.68,
    this.allowDiagonal = false,
  });

  static const String customPropertiesKey = 'joystick';

  final JoystickMode mode;
  final JoystickAxis axis;
  final JoystickBoundary boundary;
  final bool springReturn;
  final double deadZone;
  final double slowThreshold;
  final double fastThreshold;
  final bool allowDiagonal;

  bool get isDualAxis =>
      mode == JoystickMode.dualAxisAnalog ||
      mode == JoystickMode.dualAxisDigital4;

  bool get isAnalog =>
      mode == JoystickMode.singleAxisAnalog ||
      mode == JoystickMode.dualAxisAnalog;

  bool get isDigital => !isAnalog;

  JoystickConfig normalizedForMode() {
    return copyWith(
      boundary: switch (mode) {
        JoystickMode.dualAxisAnalog => JoystickBoundary.circular,
        JoystickMode.singleAxisAnalog ||
        JoystickMode.singleAxisDigital5 ||
        JoystickMode.dualAxisDigital4 => boundary,
      },
      springReturn: switch (mode) {
        JoystickMode.singleAxisDigital5 || JoystickMode.dualAxisAnalog => true,
        JoystickMode.singleAxisAnalog ||
        JoystickMode.dualAxisDigital4 => springReturn,
      },
      allowDiagonal: switch (mode) {
        JoystickMode.dualAxisAnalog => true,
        JoystickMode.singleAxisAnalog ||
        JoystickMode.singleAxisDigital5 ||
        JoystickMode.dualAxisDigital4 => allowDiagonal,
      },
    );
  }

  JoystickConfig copyWith({
    JoystickMode? mode,
    JoystickAxis? axis,
    JoystickBoundary? boundary,
    bool? springReturn,
    double? deadZone,
    double? slowThreshold,
    double? fastThreshold,
    bool? allowDiagonal,
  }) {
    return JoystickConfig(
      mode: mode ?? this.mode,
      axis: axis ?? this.axis,
      boundary: boundary ?? this.boundary,
      springReturn: springReturn ?? this.springReturn,
      deadZone: _clampUnit(deadZone ?? this.deadZone),
      slowThreshold: _clampUnit(slowThreshold ?? this.slowThreshold),
      fastThreshold: _clampUnit(fastThreshold ?? this.fastThreshold),
      allowDiagonal: allowDiagonal ?? this.allowDiagonal,
    );
  }

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'axis': axis.name,
    'boundary': boundary.name,
    'springReturn': springReturn,
    'deadZone': deadZone,
    'slowThreshold': slowThreshold,
    'fastThreshold': fastThreshold,
    'allowDiagonal': allowDiagonal,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory JoystickConfig.fromCustomProperties(Map<String, dynamic> properties) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return JoystickConfig.fromJson(raw);
    if (raw is Map) {
      return JoystickConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const JoystickConfig();
  }

  factory JoystickConfig.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, dynamic name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return JoystickConfig(
      mode: enumValue(
        JoystickMode.values,
        json['mode'],
        JoystickMode.singleAxisDigital5,
      ),
      axis: enumValue(JoystickAxis.values, json['axis'], JoystickAxis.vertical),
      boundary: enumValue(
        JoystickBoundary.values,
        json['boundary'],
        JoystickBoundary.circular,
      ),
      springReturn: json['springReturn'] as bool? ?? true,
      deadZone: _readUnit(json['deadZone'], 0.18),
      slowThreshold: _readUnit(json['slowThreshold'], 0.28),
      fastThreshold: _readUnit(json['fastThreshold'], 0.68),
      allowDiagonal: json['allowDiagonal'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is JoystickConfig &&
          other.mode == mode &&
          other.axis == axis &&
          other.boundary == boundary &&
          other.springReturn == springReturn &&
          other.deadZone == deadZone &&
          other.slowThreshold == slowThreshold &&
          other.fastThreshold == fastThreshold &&
          other.allowDiagonal == allowDiagonal;

  @override
  int get hashCode => Object.hash(
    mode,
    axis,
    boundary,
    springReturn,
    deadZone,
    slowThreshold,
    fastThreshold,
    allowDiagonal,
  );
}

double _readUnit(dynamic value, double fallback) {
  if (value is num) return _clampUnit(value.toDouble());
  return fallback;
}

double _clampUnit(double value) {
  if (value.isNaN || value.isInfinite) return 0.0;
  return math.min(1.0, math.max(0.0, value));
}

extension JoystickModeInfo on JoystickMode {
  String get label => switch (this) {
    JoystickMode.singleAxisAnalog => 'Single-axis analog',
    JoystickMode.singleAxisDigital5 => 'Single-axis digital 5-step',
    JoystickMode.dualAxisAnalog => 'Dual-axis analog',
    JoystickMode.dualAxisDigital4 => 'Dual-axis digital friction',
  };

  String get shortLabel => switch (this) {
    JoystickMode.singleAxisAnalog => '1A',
    JoystickMode.singleAxisDigital5 => '1D',
    JoystickMode.dualAxisAnalog => '2A',
    JoystickMode.dualAxisDigital4 => '2D',
  };
}
