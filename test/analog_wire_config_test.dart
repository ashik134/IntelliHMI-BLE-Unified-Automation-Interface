// Pure-math regression guard for the shared analog range/mapping logic
// (AnalogRangeMixin) used by AnalogJoystickConfig and AnalogSliderConfig —
// the new analog controls' equivalent of PotentiometerConfig's own
// (untouched, separately-tested-by-production-use) min/max/step math.
//
// Covers:
//   - signedToValue: center-relative bipolar mapping (joystick), including
//     an off-center neutral (the O-T slider case: neutral == minValue).
//   - normalizedValueFor/valueForNormalized: absolute track-position mapping
//     (slider), round-tripping correctly.
//   - wirePayload: "min,max,value" formatting, decimal places derived from
//     stepSize, values clamped/snapped into range.
//   - normalized(): sanitizes NaN/inverted-range/non-positive-step input,
//     mirroring PotentiometerConfig.normalized()'s established contract.
//   - JSON round-trip for both new config models, including enum fields.
//   - AnalogSliderConfig.isOneSided reflects neutralValue's position.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/analog_joystick_config.dart';
import 'package:rev_crane_control_ops/models/analog_slider_config.dart';
import 'package:rev_crane_control_ops/models/analog_wire_config.dart';

void main() {
  group('AnalogRangeMixin.signedToValue — center-relative bipolar mapping', () {
    test('symmetric range, centered neutral: collapses to plain linear', () {
      const config = AnalogJoystickConfig(
        minValue: -100,
        maxValue: 100,
        neutralValue: 0,
      );
      expect(config.signedToValue(1.0), 100.0);
      expect(config.signedToValue(-1.0), -100.0);
      expect(config.signedToValue(0.0), 0.0);
      expect(config.signedToValue(0.5), 50.0);
      expect(config.signedToValue(-0.5), -50.0);
    });

    test('off-center neutral (one-sided): negative raw still resolves to '
        'neutral, never below it', () {
      // Mirrors the O-T analog slider shape: neutral sits at minValue, so a
      // joystick/slider configured this way should never report anything
      // below its own neutral even for negative raw input.
      const config = AnalogJoystickConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 0,
      );
      expect(config.signedToValue(1.0), 100.0);
      expect(config.signedToValue(0.5), 50.0);
      expect(config.signedToValue(0.0), 0.0);
      expect(config.signedToValue(-1.0), 0.0);
      expect(config.signedToValue(-0.5), 0.0);
    });

    test('asymmetric neutral scales each side independently', () {
      // neutral at 25% of the way into [0, 100] (== 25): +1 -> 100 (75 away),
      // -1 -> 0 (25 away) -- the two sides are NOT mirror images of a
      // midpoint-centered mapping.
      const config = AnalogJoystickConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 25,
      );
      expect(config.signedToValue(1.0), 100.0);
      expect(config.signedToValue(-1.0), 0.0);
      expect(config.signedToValue(0.0), 25.0);
    });

    test('raw is clamped to [-1, 1] before mapping', () {
      const config = AnalogJoystickConfig(
        minValue: -100,
        maxValue: 100,
        neutralValue: 0,
        stepSize: 0.01,
      );
      expect(config.signedToValue(5.0), 100.0);
      expect(config.signedToValue(-5.0), -100.0);
    });
  });

  group('AnalogRangeMixin.normalizedValueFor / valueForNormalized — '
      'absolute track-position mapping', () {
    const config = AnalogSliderConfig(minValue: 0, maxValue: 200);

    test('round-trips a mid-range value', () {
      final t = config.normalizedValueFor(50);
      expect(t, closeTo(0.25, 1e-9));
      expect(config.valueForNormalized(t), 50.0);
    });

    test('0 and 1 map to minValue and maxValue', () {
      expect(config.valueForNormalized(0.0), 0.0);
      expect(config.valueForNormalized(1.0), 200.0);
      expect(config.normalizedValueFor(0), 0.0);
      expect(config.normalizedValueFor(200), 1.0);
    });

    test('out-of-range t is clamped', () {
      expect(config.valueForNormalized(-1.0), 0.0);
      expect(config.valueForNormalized(2.0), 200.0);
    });
  });

  group('AnalogRangeMixin.analogWirePayload — "min,max,value" formatting', () {
    test('integer step size formats with zero decimal places', () {
      const config = AnalogJoystickConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
      );
      expect(config.analogWirePayload(42.7), '0,100,43');
    });

    test('fractional step size drives decimal places', () {
      const config = AnalogSliderConfig(
        minValue: 0,
        maxValue: 10,
        stepSize: 0.5,
      );
      expect(config.analogWirePayload(3.3), '0.0,10.0,3.5');
    });

    test('value is clamped into [minValue, maxValue]', () {
      const config = AnalogJoystickConfig(
        minValue: -50,
        maxValue: 50,
        stepSize: 1,
      );
      expect(config.analogWirePayload(999), '-50,50,50');
      expect(config.analogWirePayload(-999), '-50,50,-50');
    });

    test('AnalogJoystickConfig.wirePayload matches analogWirePayload on a '
        'normalized copy', () {
      const config = AnalogJoystickConfig(
        minValue: 0,
        maxValue: 100,
        stepSize: 1,
      );
      expect(config.wirePayload(55), '0,100,55');
      // Also satisfies the shared AnalogWireConfig contract used by
      // CraneController.setAnalogButtonValue.
      const AnalogWireConfig asInterface = config;
      expect(asInterface.wirePayload(55), '0,100,55');
    });
  });

  group('AnalogJoystickConfig.normalized() — sanitizes invalid input', () {
    test('inverted min/max is corrected', () {
      const config = AnalogJoystickConfig(minValue: 100, maxValue: -100);
      final normalized = config.normalized();
      expect(normalized.minValue < normalized.maxValue, isTrue);
    });

    test('non-positive step falls back to 1.0', () {
      const config = AnalogJoystickConfig(stepSize: 0);
      expect(config.normalized().stepSize, 1.0);
    });

    test('NaN neutral falls back to range midpoint', () {
      const config = AnalogJoystickConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: double.nan,
      );
      expect(config.normalized().neutralValue, 50.0);
    });

    test('deadZone is clamped to [0, 0.9]', () {
      const config = AnalogJoystickConfig(deadZone: 5.0);
      expect(config.normalized().deadZone, 0.9);
    });
  });

  group('AnalogSliderConfig.isOneSided', () {
    test('neutral at minValue is one-sided (O-T)', () {
      const config = AnalogSliderConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 0,
      );
      expect(config.isOneSided, isTrue);
    });

    test('neutral at maxValue is also one-sided', () {
      const config = AnalogSliderConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 100,
      );
      expect(config.isOneSided, isTrue);
    });

    test('neutral strictly between min and max is two-sided (T-O-T)', () {
      const config = AnalogSliderConfig(
        minValue: -100,
        maxValue: 100,
        neutralValue: 0,
      );
      expect(config.isOneSided, isFalse);
    });
  });

  group('JSON round-trip', () {
    test('AnalogJoystickConfig preserves every field including enums', () {
      const config = AnalogJoystickConfig(
        minValue: -50,
        maxValue: 50,
        neutralValue: 10,
        stepSize: 0.5,
        deadZone: 0.2,
        springReturnEnabled: false,
        orientation: AnalogJoystickOrientation.horizontal,
        outputAxis: AnalogJoystickOutputAxis.y,
        invert: true,
        outputEnabled: true,
        unit: 'deg',
      );
      final restored = AnalogJoystickConfig.fromJson(config.toJson());
      expect(restored, config);
    });

    test('AnalogSliderConfig preserves every field including enums', () {
      const config = AnalogSliderConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 50,
        stepSize: 2,
        springReturnEnabled: false,
        orientation: AnalogSliderOrientation.horizontal,
        invert: true,
        outputEnabled: true,
        unit: 'mm',
      );
      final restored = AnalogSliderConfig.fromJson(config.toJson());
      expect(restored, config);
    });

    test('fromCustomProperties round-trips through applyToCustomProperties', () {
      const config = AnalogSliderConfig(
        minValue: 0,
        maxValue: 100,
        neutralValue: 0,
        outputEnabled: true,
      );
      final properties = config.applyToCustomProperties(const {
        'someOtherKey': 'untouched',
      });
      expect(properties['someOtherKey'], 'untouched');
      final restored = AnalogSliderConfig.fromCustomProperties(properties);
      expect(restored, config);
    });

    test('missing key falls back to defaults', () {
      final config = AnalogJoystickConfig.fromCustomProperties(const {});
      expect(config, const AnalogJoystickConfig());
    });
  });
}
