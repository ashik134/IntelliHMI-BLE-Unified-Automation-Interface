// Verifies PLC14/PLC21's 4-field wire-format handling for the generic
// PLC-output-variant model:
//   (a) wire-level truncation already works — a composed PlcOutputCommand
//       serializes to only [estop, up, down, fastUd] for PLC14/21, silently
//       dropping any of a5..a10 even if a button somehow referenced them
//       (e.g. a hand-edited/imported layout) — no crash, no protocol
//       violation, and the packet length/format is unchanged.
//   (b) the edit-sheet-level restriction (selectableVariantsFor) additionally
//       prevents a user from ever configuring a5..a10 in the first place
//       when editing a PLC14/PLC21-bucket layout, so the truncation case
//       above should only ever arise from external data, never from normal
//       in-app editing.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

void main() {
  group('selectableVariantsFor', () {
    test('PLC38 bucket exposes the full a2..a10 range (9 variants)', () {
      final variants = selectableVariantsFor(LayoutBucket.plc38);
      expect(variants.length, 9);
      expect(variants.contains(PlcMapping.estop), isFalse);
      expect(variants.toSet(), PlcMapping.values.toSet()..remove(PlcMapping.estop));
    });

    test('PLC14 bucket restricts selection to exactly up/down/fastUd '
        '(a2/a3/a4)', () {
      final variants = selectableVariantsFor(LayoutBucket.plc14);
      expect(variants.toSet(), {
        PlcMapping.up,
        PlcMapping.down,
        PlcMapping.fastUd,
      });
    });

    test('PLC21 bucket restricts selection identically to PLC14', () {
      final variants = selectableVariantsFor(LayoutBucket.plc21);
      expect(variants.toSet(), {
        PlcMapping.up,
        PlcMapping.down,
        PlcMapping.fastUd,
      });
    });

    test('a1/E-STOP is never selectable in any bucket', () {
      for (final bucket in LayoutBucket.values) {
        expect(
          selectableVariantsFor(bucket).contains(PlcMapping.estop),
          isFalse,
          reason: '$bucket must never expose estop as user-selectable',
        );
      }
    });
  });

  group('wire-level truncation for PLC14 (4-field format)', () {
    test(
      'a composed command with left/right/forward/reverse/fastLr/fastFb set '
      '(simulating a hand-edited layout referencing a5..a10) still '
      'serializes to the standard 4-field PLC14 format, silently dropping '
      'the out-of-range fields',
      () {
        final cmd = PlcOutputCommand.compose(
          estop: false,
          up: true,
          down: false,
          fastUd: true,
          left: true,
          right: false,
          fastLr: true,
          forward: true,
          reverse: false,
          fastFb: true,
        );
        expect(cmd.wireFormatFor(PlcType.plc14), '[0,1,0,1]');
      },
    );

    test('PLC14 wire format never exceeds 4 fields regardless of how many '
        'of the 9 non-estop variants are active', () {
      final cmd = PlcOutputCommand.compose(
        estop: false,
        up: true,
        down: true,
        fastUd: true,
        left: true,
        right: true,
        fastLr: true,
        forward: true,
        reverse: true,
        fastFb: true,
      );
      final wire = cmd.wireFormatFor(PlcType.plc14);
      final fieldCount = wire.replaceAll(RegExp(r'[\[\]]'), '').split(',').length;
      expect(fieldCount, 4);
    });

    test('PLC38 wire format always emits the full 10 fields, unaffected by '
        'this refactor', () {
      final cmd = PlcOutputCommand.idle();
      final wire = cmd.wireFormatFor(PlcType.plc38);
      final fieldCount = wire.replaceAll(RegExp(r'[\[\]]'), '').split(',').length;
      expect(fieldCount, 10);
    });

    test('idle command emits the unchanged 4-field idle format for PLC14', () {
      expect(PlcOutputCommand.idle().wireFormatFor(PlcType.plc14), '[0,0,0,0]');
    });
  });
}
