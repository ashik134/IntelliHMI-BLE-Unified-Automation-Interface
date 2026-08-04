// Pure-model regression guard for MultiZoneSliderConfig: JSON round-trip,
// defaults matching the widget's original hardcoded constants (see
// multi_zone_slider_button.dart's kMultiZoneSliderDefaultDeadZone/
// kMultiZoneSliderDefaultFarZone), and normalization clamping.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/multi_zone_slider_config.dart';

void main() {
  test('defaults match the widget\'s original hardcoded thresholds', () {
    const config = MultiZoneSliderConfig();
    expect(config.deadZoneFraction, 0.12);
    expect(config.farZoneFraction, 0.62);
    expect(config.startLabel, isNull);
    expect(config.endLabel, isNull);
  });

  test('toJson/fromJson round-trips every field', () {
    const config = MultiZoneSliderConfig(
      startLabel: 'Slow',
      endLabel: 'Fast',
      deadZoneFraction: 0.2,
      farZoneFraction: 0.7,
    );
    final restored = MultiZoneSliderConfig.fromJson(config.toJson());
    expect(restored, config);
  });

  test('fromJson on an empty map falls back to defaults', () {
    final restored = MultiZoneSliderConfig.fromJson(const {});
    expect(restored, const MultiZoneSliderConfig());
  });

  test('blank labels normalize to null (no empty-string labels persisted)', () {
    final config = const MultiZoneSliderConfig(
      startLabel: '   ',
      endLabel: '',
    ).normalized();
    expect(config.startLabel, isNull);
    expect(config.endLabel, isNull);
  });

  test('normalized() clamps out-of-range thresholds into bounds', () {
    final config = const MultiZoneSliderConfig(
      deadZoneFraction: -1,
      farZoneFraction: 99,
    ).normalized();
    expect(
      config.deadZoneFraction,
      inInclusiveRange(
        MultiZoneSliderConfig.minDeadZoneFraction,
        MultiZoneSliderConfig.maxDeadZoneFraction,
      ),
    );
    expect(
      config.farZoneFraction,
      inInclusiveRange(
        MultiZoneSliderConfig.minFarZoneFraction,
        MultiZoneSliderConfig.maxFarZoneFraction,
      ),
    );
  });

  test('normalized() keeps farZone strictly above deadZone', () {
    final config = const MultiZoneSliderConfig(
      deadZoneFraction: 0.35,
      farZoneFraction: 0.35,
    ).normalized();
    expect(config.farZoneFraction, greaterThan(config.deadZoneFraction));
  });

  test('applyToCustomProperties/fromCustomProperties round-trips through a '
      'ButtonConfig-shaped customProperties map', () {
    const config = MultiZoneSliderConfig(startLabel: 'Left', endLabel: 'Right');
    final properties = config.applyToCustomProperties(const {'other': 1});
    expect(properties['other'], 1);
    final restored = MultiZoneSliderConfig.fromCustomProperties(properties);
    expect(restored.startLabel, 'Left');
    expect(restored.endLabel, 'Right');
  });

  test('fromCustomProperties on an unrelated map returns defaults', () {
    final restored = MultiZoneSliderConfig.fromCustomProperties(const {});
    expect(restored, const MultiZoneSliderConfig());
  });
}
