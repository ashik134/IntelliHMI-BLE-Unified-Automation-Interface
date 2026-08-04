// Regression guard for LayoutValidationService.validateButtonConfig,
// focused on the two areas this feature branch touches:
//   - mutual-exclusion symmetry (pre-existing logic, exercised here for the
//     first time in a dedicated test file)
//   - range checks for the three new ButtonBehaviorConfig fields
//     (debounceMs/longPressRequiredMs/pressAnimationStrength), mirroring the
//     existing cosmetic-style range checks in validateRoleStyle.
//
// Every button below is `visible: false` to skip grid-placement checks
// entirely (see validateButtonConfig's skipPlacementValidation) — these
// tests are only about mutual exclusion / behavior bounds, not placement.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/services/layout_validation_service.dart';

const _validator = LayoutValidationService();

ButtonConfig _button(
  String id, {
  MutualExclusionConfig mutualExclusion = const MutualExclusionConfig(),
  ButtonBehaviorConfig behavior = const ButtonBehaviorConfig(),
}) => ButtonConfig(
  id: id,
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  label: id,
  visible: false,
  mutualExclusion: mutualExclusion,
  behavior: behavior,
);

void main() {
  group('mutual exclusion', () {
    test('symmetric exclusion (both sides list each other) is valid', () {
      final a = _button(
        'a',
        mutualExclusion: const MutualExclusionConfig(excludedButtonIds: {'b'}),
      );
      final b = _button(
        'b',
        mutualExclusion: const MutualExclusionConfig(excludedButtonIds: {'a'}),
      );
      final result = _validator.validateButtonConfig(a, {'a': a, 'b': b});
      expect(result.isValid, isTrue);
    });

    test('asymmetric exclusion (only one side lists the other) is invalid', () {
      final a = _button(
        'a',
        mutualExclusion: const MutualExclusionConfig(excludedButtonIds: {'b'}),
      );
      final b = _button('b');
      final result = _validator.validateButtonConfig(a, {'a': a, 'b': b});
      expect(result.isValid, isFalse);
      expect(result.errors.single, contains('reverse'));
    });

    test('a button cannot exclude itself', () {
      final a = _button(
        'a',
        mutualExclusion: const MutualExclusionConfig(excludedButtonIds: {'a'}),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('cannot exclude itself')));
    });

    test('excluding an unknown button id is invalid', () {
      final a = _button(
        'a',
        mutualExclusion: const MutualExclusionConfig(
          excludedButtonIds: {'ghost'},
        ),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('unknown button')));
    });
  });

  group('ButtonBehaviorConfig range checks', () {
    test('in-range debounce/long-press/press-animation values are valid', () {
      final a = _button(
        'a',
        behavior: const ButtonBehaviorConfig(
          debounceMs: 200,
          longPressRequiredMs: 500,
          pressAnimationStrength: 0.5,
        ),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isTrue);
    });

    test('debounceMs above the max is rejected', () {
      final a = _button(
        'a',
        behavior: const ButtonBehaviorConfig(
          debounceMs: ButtonBehaviorConfig.maxDebounceMs + 1,
        ),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('debounce')));
    });

    test('longPressRequiredMs above the max is rejected', () {
      final a = _button(
        'a',
        behavior: const ButtonBehaviorConfig(
          longPressRequiredMs: ButtonBehaviorConfig.maxLongPressRequiredMs + 1,
        ),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('long-press')));
    });

    test('pressAnimationStrength outside [0, 1] is rejected', () {
      final a = _button(
        'a',
        behavior: const ButtonBehaviorConfig(pressAnimationStrength: 1.5),
      );
      final result = _validator.validateButtonConfig(a, {'a': a});
      expect(result.isValid, isFalse);
      expect(result.errors, contains(contains('press animation')));
    });
  });
}
