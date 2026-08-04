import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

void main() {
  group('GridLayoutOption', () {
    test('twoByThree is the default and reproduces the legacy fixed grid', () {
      expect(GridLayoutOption.fallback, GridLayoutOption.twoByThree);
      expect(GridLayoutOption.twoByThree.isDefault, isTrue);
      expect(GridLayoutOption.twoByThree.columns, ButtonConfig.controlGridColumns);
      expect(GridLayoutOption.twoByThree.rows, ButtonConfig.controlGridRows);
      expect(
        GridLayoutOption.twoByThree.slotCount,
        ButtonConfig.controlSlotCount,
      );
    });

    test('slotCount and label are derived from columns/rows', () {
      expect(GridLayoutOption.fourByThree.slotCount, 12);
      expect(GridLayoutOption.fourByThree.label, '4×3');
      expect(GridLayoutOption.threeByFour.slotCount, 12);
      expect(GridLayoutOption.threeByFour.label, '3×4');
    });

    test('only twoByThree reports isDefault', () {
      for (final option in GridLayoutOption.values) {
        expect(option.isDefault, option == GridLayoutOption.twoByThree);
      }
    });

    test('fromName resolves a known name back to its enum', () {
      expect(GridLayoutOption.fromName('fourByFour'), GridLayoutOption.fourByFour);
    });

    test('fromName falls back to twoByThree for an unknown or missing name '
        '(older saved JSON without a gridLayout key)', () {
      expect(GridLayoutOption.fromName('somePresetRemovedLater'), GridLayoutOption.fallback);
      expect(GridLayoutOption.fromName(null), GridLayoutOption.fallback);
    });
  });

  group('ButtonConfig.gridColumnSpan / gridRowSpan', () {
    ButtonConfig buttonWith({int gridColumns = 1, int gridRows = 1}) => ButtonConfig(
      id: 'a',
      type: ButtonType.pushButton,
      plcMapping: PlcOutputVariant.df2,
      gridColumns: gridColumns,
      gridRows: gridRows,
    );

    test('no longer silently caps a wide span at the old static 2x3 ceiling', () {
      // Before the cleanup, an explicit 4-column span would have been
      // clamped down to 2 (ButtonConfig.controlGridColumns) regardless of
      // how wide the active GridLayoutOption actually is — real grid-math
      // call sites (control_grid_utils.dart) own the authoritative clamp
      // against the real, dynamic columns/rows instead.
      expect(buttonWith(gridColumns: 4).gridColumnSpan, 4);
      expect(buttonWith(gridRows: 4).gridRowSpan, 4);
    });

    test('still reports 1x1 for a default (unset) span', () {
      final button = buttonWith();
      expect(button.gridColumnSpan, 1);
      expect(button.gridRowSpan, 1);
    });
  });
}
