// Pure-model regression guard for ToggleButtonConfig: JSON round-trip,
// defaults, and the customProperties bag pattern shared by every other
// per-type config (JoystickConfig, PotentiometerConfig, ...).

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/toggle_button_config.dart';

void main() {
  test('defaults: no overrides, neither side disabled', () {
    const config = ToggleButtonConfig();
    expect(config.leftLabel, isNull);
    expect(config.rightLabel, isNull);
    expect(config.leftIconKey, isNull);
    expect(config.rightIconKey, isNull);
    expect(config.disableLeft, isFalse);
    expect(config.disableRight, isFalse);
  });

  test('toJson/fromJson round-trips every field', () {
    const config = ToggleButtonConfig(
      leftLabel: 'Slow',
      rightLabel: 'Fast',
      leftIconKey: 'arrow_up',
      rightIconKey: 'arrow_down',
      disableLeft: true,
    );
    final restored = ToggleButtonConfig.fromJson(config.toJson());
    expect(restored, config);
  });

  test('fromJson on an empty map falls back to defaults', () {
    expect(ToggleButtonConfig.fromJson(const {}), const ToggleButtonConfig());
  });

  test('copyWith clear flags null out the target field independent of others', () {
    const config = ToggleButtonConfig(leftLabel: 'A', rightLabel: 'B');
    final cleared = config.copyWith(clearLeftLabel: true);
    expect(cleared.leftLabel, isNull);
    expect(cleared.rightLabel, 'B');
  });

  test('applyToCustomProperties/fromCustomProperties round-trips and '
      'preserves unrelated keys', () {
    const config = ToggleButtonConfig(disableRight: true);
    final properties = config.applyToCustomProperties(const {'other': 'x'});
    expect(properties['other'], 'x');
    final restored = ToggleButtonConfig.fromCustomProperties(properties);
    expect(restored.disableRight, isTrue);
    expect(restored.disableLeft, isFalse);
  });

  test('fromCustomProperties on an unrelated map returns defaults', () {
    expect(
      ToggleButtonConfig.fromCustomProperties(const {}),
      const ToggleButtonConfig(),
    );
  });
}
