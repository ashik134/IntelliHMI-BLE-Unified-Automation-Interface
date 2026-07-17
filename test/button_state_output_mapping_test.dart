import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';

void main() {
  group('ButtonStateOutputMapping', () {
    test('JSON round-trips stateId and activeVariants', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcMapping.left, PlcMapping.fastLr},
      );
      final restored = ButtonStateOutputMapping.fromJson(mapping.toJson());
      expect(restored.stateId, 'step2');
      expect(restored.activeVariants, {PlcMapping.left, PlcMapping.fastLr});
    });

    test('toJson serializes variants as PlcMapping.name strings, not aN', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'active',
        activeVariants: {PlcMapping.up},
      );
      final json = mapping.toJson();
      expect(json['activeVariants'], ['up']);
    });

    test('empty activeVariants round-trips to an empty set', () {
      const mapping = ButtonStateOutputMapping(stateId: 'idle');
      final restored = ButtonStateOutputMapping.fromJson(mapping.toJson());
      expect(restored.activeVariants, isEmpty);
    });

    test('isValid is false when activeVariants contains estop', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'active',
        activeVariants: {PlcMapping.estop},
      );
      expect(mapping.isValid, isFalse);
    });

    test('isValid is true for any non-estop variant set', () {
      const mapping = ButtonStateOutputMapping(
        stateId: 'active',
        activeVariants: {PlcMapping.up, PlcMapping.fastUd},
      );
      expect(mapping.isValid, isTrue);
    });

    test(
      'fromJson silently drops an estop entry from hand-edited/corrupted '
      'JSON — estop can never be smuggled into activeVariants',
      () {
        final restored = ButtonStateOutputMapping.fromJson({
          'stateId': 'active',
          'activeVariants': ['estop', 'up'],
        });
        expect(restored.activeVariants, {PlcMapping.up});
        expect(restored.activeVariants.contains(PlcMapping.estop), isFalse);
      },
    );

    test('fromJson ignores unrecognized variant names', () {
      final restored = ButtonStateOutputMapping.fromJson({
        'stateId': 'active',
        'activeVariants': ['not_a_real_variant', 'down'],
      });
      expect(restored.activeVariants, {PlcMapping.down});
    });

    test('copyWith replaces only the given fields', () {
      const original = ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {PlcMapping.left},
      );
      final updated = original.copyWith(activeVariants: {PlcMapping.right});
      expect(updated.stateId, 'step1');
      expect(updated.activeVariants, {PlcMapping.right});
    });

    test('equality is stateId + set-equality (order-independent)', () {
      const a = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcMapping.up, PlcMapping.fastUd},
      );
      const b = ButtonStateOutputMapping(
        stateId: 'step2',
        activeVariants: {PlcMapping.fastUd, PlcMapping.up},
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
        activeVariants: {PlcMapping.up},
      );
      const b = ButtonStateOutputMapping(
        stateId: 'step1',
        activeVariants: {PlcMapping.down},
      );
      expect(a, isNot(equals(b)));
    });
  });
}
