import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

void main() {
  group('ButtonStateOutputMapping', () {
    test('JSON round-trips stateId and activeVariants', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcOutputVariant.df5, PlcOutputVariant.df7},
      );
      final restored = ButtonStateOutputMapping.fromJson(mapping.toJson());
      expect(restored.stateId, 'step2');
      expect(restored.activeVariants, {
        PlcOutputVariant.df5,
        PlcOutputVariant.df7,
      });
    });

    test(
      'toJson serializes variants as PlcOutputVariant.storageKey strings, not aN',
      () {
        const mapping = ButtonStateOutputMapping(
          stateId: 'active',
          activeVariants: {PlcOutputVariant.df2},
        );
        final json = mapping.toJson();
        expect(json['activeVariants'], ['DF2']);
      },
    );

    test('empty activeVariants round-trips to an empty set', () {
      const mapping = ButtonStateOutputMapping(stateId: 'idle');
      final restored = ButtonStateOutputMapping.fromJson(mapping.toJson());
      expect(restored.activeVariants, isEmpty);
    });

    test('isValid is false when activeVariants contains estop', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'active',
        activeVariants: {PlcOutputVariant.df1},
      );
      expect(mapping.isValid, isFalse);
    });

    test('isValid is true for any non-estop variant set', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'active',
        activeVariants: {PlcOutputVariant.df2, PlcOutputVariant.df4},
      );
      expect(mapping.isValid, isTrue);
    });

    test('fromJson silently drops an estop entry from hand-edited/corrupted '
        'JSON — estop can never be smuggled into activeVariants', () {
      final restored = ButtonStateOutputMapping.fromJson({
        'stateId': 'active',
        'activeVariants': ['estop', 'up'],
      });
      expect(restored.activeVariants, {PlcOutputVariant.df2});
      expect(restored.activeVariants.contains(PlcOutputVariant.df1), isFalse);
    });

    test('fromJson ignores unrecognized variant names', () {
      final restored = ButtonStateOutputMapping.fromJson({
        'stateId': 'active',
        'activeVariants': ['not_a_real_variant', 'down'],
      });
      expect(restored.activeVariants, {PlcOutputVariant.df3});
    });

    test('copyWith replaces only the given fields', () {
      const original = ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {PlcOutputVariant.df5},
      );
      final updated = original.copyWith(activeVariants: {PlcOutputVariant.df6});
      expect(updated.stateId, 'step1');
      expect(updated.activeVariants, {PlcOutputVariant.df6});
    });

    test('equality is stateId + set-equality (order-independent)', () {
      const a = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcOutputVariant.df2, PlcOutputVariant.df4},
      );
      const b = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcOutputVariant.df4, PlcOutputVariant.df2},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality when stateId differs', () {
      const a = ButtonStateOutputMapping(stateId: 'step1');
      const b = ButtonStateOutputMapping(stateId: 'step2');
      expect(a, isNot(equals(b)));
    });

    test('inequality when activeVariants differ', () {
      const a = ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {PlcOutputVariant.df2},
      );
      const b = ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {PlcOutputVariant.df3},
      );
      expect(a, isNot(equals(b)));
    });
  });
}
