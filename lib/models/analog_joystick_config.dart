import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/control_orientation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AnalogJoystickConfig
//
// Backs both ButtonType.analogJoystick1D and .analogJoystick2D. Deliberately
// independent of JoystickConfig (the digital joystick's own config) — the
// analog joystick strategy builds a throwaway JoystickConfig purely to drive
// IndustrialJoystickControl's visuals; this class owns the analog-domain
// concerns (output range, neutral, which axis is transmitted) instead.
// ─────────────────────────────────────────────────────────────────────────────

enum AnalogJoystickOrientation { horizontal, vertical }

enum AnalogJoystickOutputAxis { x, y }

extension AnalogJoystickOrientationInfo on AnalogJoystickOrientation {
  String get label => switch (this) {
    AnalogJoystickOrientation.horizontal => 'Horizontal',
    AnalogJoystickOrientation.vertical => 'Vertical',
  };

  /// Lets generic call sites (ButtonConfig's orientation dispatch,
  /// GeneralTab) treat this type-specific enum like every other
  /// orientation-supporting type's — see [ControlOrientationToAnalogJoystick].
  ControlOrientation get asControlOrientation => switch (this) {
    AnalogJoystickOrientation.horizontal => ControlOrientation.horizontal,
    AnalogJoystickOrientation.vertical => ControlOrientation.vertical,
  };
}

extension ControlOrientationToAnalogJoystick on ControlOrientation {
  AnalogJoystickOrientation get asAnalogJoystickOrientation => switch (this) {
    ControlOrientation.horizontal => AnalogJoystickOrientation.horizontal,
    ControlOrientation.vertical => AnalogJoystickOrientation.vertical,
  };
}

extension AnalogJoystickOutputAxisInfo on AnalogJoystickOutputAxis {
  String get label => switch (this) {
    AnalogJoystickOutputAxis.x => 'X axis',
    AnalogJoystickOutputAxis.y => 'Y axis',
  };
}

class AnalogJoystickConfig with AnalogRangeMixin implements AnalogWireConfig {
  const AnalogJoystickConfig({
    this.minValue = -100.0,
    this.maxValue = 100.0,
    this.neutralValue = 0.0,
    this.stepSize = 1.0,
    this.deadZone = 0.12,
    this.springReturnEnabled = true,
    this.orientation = AnalogJoystickOrientation.vertical,
    this.outputAxis = AnalogJoystickOutputAxis.x,
    this.invert = false,
    this.outputEnabled = false,
    this.outputChannel,
    this.unit = '',
  });

  static const String customPropertiesKey = 'analogJoystick';

  @override
  final double minValue;
  @override
  final double maxValue;
  @override
  final double neutralValue;
  @override
  final double stepSize;

  /// Fraction of full-scale travel (0..0.9) near [neutralValue] that
  /// IndustrialJoystickControl treats as no-input. Same semantics as
  /// JoystickConfig.deadZone, kept independent so editing one never
  /// surprises the other.
  final double deadZone;
  final bool springReturnEnabled;

  /// Rail orientation for the 1D case; ignored for 2D (dual-axis always
  /// renders as a gimbal).
  final AnalogJoystickOrientation orientation;

  /// Which of the widget's two computed axes is actually transmitted for
  /// the 2D case — the firmware only accepts a single scalar "min,max,value"
  /// payload today, so a dual-axis gesture still emits one value. Ignored
  /// for 1D (the single rail axis is always the one transmitted).
  final AnalogJoystickOutputAxis outputAxis;
  final bool invert;

  /// Opt-in "send to PLC" flag, same convention as PotentiometerConfig —
  /// defaults to false so a freshly-added control stays inert until the
  /// operator explicitly enables it.
  @override
  final bool outputEnabled;

  /// Which firmware analog channel (A1..A6) this control writes to — see
  /// AnalogWireConfig.outputChannel. Null until the operator picks one in
  /// the OUTPUT MAPPING editor.
  @override
  final AnalogOutputChannel? outputChannel;
  final String unit;

  AnalogJoystickConfig normalized() {
    final safeMin = finiteOrAnalog(minValue, -100.0);
    var safeMax = finiteOrAnalog(maxValue, safeMin + 100.0);
    if (safeMax <= safeMin) safeMax = safeMin + 1.0;
    final safeRange = safeMax - safeMin;

    var safeStep = finiteOrAnalog(stepSize.abs(), 1.0);
    if (safeStep <= 0.0) safeStep = 1.0;
    if (safeStep > safeRange) safeStep = safeRange;

    final safeNeutral = finiteOrAnalog(
      neutralValue,
      safeMin + safeRange / 2,
    ).clamp(safeMin, safeMax).toDouble();

    final safeDeadZone = finiteOrAnalog(
      deadZone,
      0.12,
    ).clamp(0.0, 0.9).toDouble();

    return AnalogJoystickConfig(
      minValue: safeMin,
      maxValue: safeMax,
      neutralValue: safeNeutral,
      stepSize: safeStep,
      deadZone: safeDeadZone,
      springReturnEnabled: springReturnEnabled,
      orientation: orientation,
      outputAxis: outputAxis,
      invert: invert,
      outputEnabled: outputEnabled,
      outputChannel: outputChannel,
      unit: unit.trim(),
    );
  }

  AnalogJoystickConfig copyWith({
    double? minValue,
    double? maxValue,
    double? neutralValue,
    double? stepSize,
    double? deadZone,
    bool? springReturnEnabled,
    AnalogJoystickOrientation? orientation,
    AnalogJoystickOutputAxis? outputAxis,
    bool? invert,
    bool? outputEnabled,
    AnalogOutputChannel? outputChannel,
    String? unit,
    bool clearOutputChannel = false,
  }) {
    return AnalogJoystickConfig(
      minValue: minValue ?? this.minValue,
      maxValue: maxValue ?? this.maxValue,
      neutralValue: neutralValue ?? this.neutralValue,
      stepSize: stepSize ?? this.stepSize,
      deadZone: deadZone ?? this.deadZone,
      springReturnEnabled: springReturnEnabled ?? this.springReturnEnabled,
      orientation: orientation ?? this.orientation,
      outputAxis: outputAxis ?? this.outputAxis,
      invert: invert ?? this.invert,
      outputEnabled: outputEnabled ?? this.outputEnabled,
      outputChannel: clearOutputChannel
          ? null
          : (outputChannel ?? this.outputChannel),
      unit: unit ?? this.unit,
    ).normalized();
  }

  Map<String, dynamic> toJson() => {
    'minValue': minValue,
    'maxValue': maxValue,
    'neutralValue': neutralValue,
    'stepSize': stepSize,
    'deadZone': deadZone,
    'springReturnEnabled': springReturnEnabled,
    'orientation': orientation.name,
    'outputAxis': outputAxis.name,
    'invert': invert,
    'outputEnabled': outputEnabled,
    'outputChannel': outputChannel?.token,
    'unit': unit,
  };

  Map<String, dynamic> applyToCustomProperties(
    Map<String, dynamic> properties,
  ) {
    return {...properties, customPropertiesKey: toJson()};
  }

  factory AnalogJoystickConfig.fromCustomProperties(
    Map<String, dynamic> properties,
  ) {
    final raw = properties[customPropertiesKey];
    if (raw is Map<String, dynamic>) return AnalogJoystickConfig.fromJson(raw);
    if (raw is Map) {
      return AnalogJoystickConfig.fromJson(raw.cast<String, dynamic>());
    }
    return const AnalogJoystickConfig();
  }

  factory AnalogJoystickConfig.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, dynamic name, T fallback) {
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    return AnalogJoystickConfig(
      minValue: readAnalogDouble(json['minValue'], -100.0),
      maxValue: readAnalogDouble(json['maxValue'], 100.0),
      neutralValue: readAnalogDouble(json['neutralValue'], 0.0),
      stepSize: readAnalogDouble(json['stepSize'], 1.0),
      deadZone: readAnalogDouble(json['deadZone'], 0.12),
      springReturnEnabled: json['springReturnEnabled'] as bool? ?? true,
      orientation: enumValue(
        AnalogJoystickOrientation.values,
        json['orientation'],
        AnalogJoystickOrientation.vertical,
      ),
      outputAxis: enumValue(
        AnalogJoystickOutputAxis.values,
        json['outputAxis'],
        AnalogJoystickOutputAxis.x,
      ),
      invert: json['invert'] as bool? ?? false,
      outputEnabled: json['outputEnabled'] as bool? ?? false,
      outputChannel: AnalogOutputChannel.fromToken(json['outputChannel']),
      unit: json['unit'] as String? ?? '',
    ).normalized();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnalogJoystickConfig &&
          other.minValue == minValue &&
          other.maxValue == maxValue &&
          other.neutralValue == neutralValue &&
          other.stepSize == stepSize &&
          other.deadZone == deadZone &&
          other.springReturnEnabled == springReturnEnabled &&
          other.orientation == orientation &&
          other.outputAxis == outputAxis &&
          other.invert == invert &&
          other.outputEnabled == outputEnabled &&
          other.outputChannel == outputChannel &&
          other.unit == unit;

  @override
  int get hashCode => Object.hash(
    minValue,
    maxValue,
    neutralValue,
    stepSize,
    deadZone,
    springReturnEnabled,
    orientation,
    outputAxis,
    invert,
    outputEnabled,
    outputChannel,
    unit,
  );
}
