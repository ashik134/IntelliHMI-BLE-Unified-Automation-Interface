// kButtonTypeStrategies is a plain Map, not an exhaustive switch — unlike
// button_logical_state.dart's/button_type_strategy.dart's compiler-enforced
// switches, the compiler will happily let a new ButtonType value go
// unregistered here. ConfigurableButton.build() looks it up with `!`
// (kButtonTypeStrategies[config.type]!), so a missing entry is a silent
// runtime crash the first time that type is actually rendered, not a build
// failure. This guards against that.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';

void main() {
  test('every ButtonType has a registered strategy', () {
    for (final type in ButtonType.values) {
      expect(
        kButtonTypeStrategies.containsKey(type),
        isTrue,
        reason: '$type is missing from kButtonTypeStrategies',
      );
    }
  });

  test('every registered strategy reports the ButtonType it is keyed under', () {
    kButtonTypeStrategies.forEach((type, strategy) {
      expect(
        strategy.type,
        type,
        reason:
            'kButtonTypeStrategies[$type] is a strategy for '
            '${strategy.type} instead',
      );
    });
  });
}
