import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

// Fixed canvas so a cell's pixel center maps back to an exact, unambiguous
// grid anchor: 2 columns x 3 rows -> 100x100 cells over a 200x300 canvas.
const _canvasRect = Rect.fromLTWH(0, 0, 200, 300);

Offset _cellCenter(int col, int row) => Offset(col * 100 + 50, row * 100 + 50);

ButtonConfig _button(
  String id, {
  required int page,
  required int x,
  required int y,
  int colSpan = 1,
  int rowSpan = 1,
}) => ButtonConfig(
  id: id,
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  pageIndex: page,
  gridX: x,
  gridY: y,
  gridColumns: colSpan,
  gridRows: rowSpan,
);

InsertionPreview? _predict({
  required Map<String, ButtonConfig> buttons,
  required int colSpan,
  required int rowSpan,
  required int currentPageIndex,
  required int existingPageCount,
  required int targetCol,
  required int targetRow,
}) => predictInsertionLayout(
  buttons: buttons,
  colSpan: colSpan,
  rowSpan: rowSpan,
  currentPageIndex: currentPageIndex,
  existingPageCount: existingPageCount,
  canvasRect: _canvasRect,
  dropCenter: _cellCenter(targetCol, targetRow),
);

void main() {
  group('predictInsertionLayout', () {
    test('free target requires no candidates and scores zero', () {
      final buttons = {'E': _button('E', page: 0, x: 1, y: 2)};
      final preview = _predict(
        buttons: buttons,
        colSpan: 1,
        rowSpan: 1,
        currentPageIndex: 0,
        existingPageCount: 1,
        targetCol: 0,
        targetRow: 0,
      )!;

      expect(preview.movedButtons, isEmpty);
      expect(preview.disruptionScore, 0);
      expect(preview.target.gridX, 0);
      expect(preview.target.gridY, 0);
    });

    test(
      'single overlap displaces to the nearest free cell on the same page',
      () {
        final buttons = {'E': _button('E', page: 0, x: 0, y: 0)};
        final preview = _predict(
          buttons: buttons,
          colSpan: 1,
          rowSpan: 1,
          currentPageIndex: 0,
          existingPageCount: 1,
          targetCol: 0,
          targetRow: 0,
        )!;

        expect(preview.movedButtons.keys, {'E'});
        final placement = preview.movedButtons['E']!;
        // Slot1 (col1,row0) and slot2 (col0,row1) are equidistant from E's
        // own original (0,0); the tie-break is the lower slot index, i.e.
        // slot1.
        expect(placement.pageIndex, 0);
        expect(placement.gridX, 1);
        expect(placement.gridY, 0);
      },
    );

    test(
      'creates a brand-new page when the only existing page is completely full',
      () {
        final buttons = {
          for (var slot = 0; slot < 6; slot++)
            'A$slot': _button(
              'A$slot',
              page: 0,
              x: slot % ButtonConfig.controlGridColumns,
              y: slot ~/ ButtonConfig.controlGridColumns,
            ),
        };
        final preview = _predict(
          buttons: buttons,
          colSpan: 1,
          rowSpan: 1,
          currentPageIndex: 0,
          existingPageCount: 1,
          targetCol: 0,
          targetRow: 0,
        )!;

        expect(preview.movedButtons.keys, {'A0'});
        final placement = preview.movedButtons['A0']!;
        expect(placement.pageIndex, 1);
        expect(placement.gridX, 0);
        expect(placement.gridY, 0);
        // Only one brand-new page was needed, not more.
        expect(
          preview.movedButtons.values.every((p) => p.pageIndex <= 1),
          isTrue,
        );
      },
    );

    test(
      'deterministic multi-widget eviction order for a 2x2 drop onto four 1x1 '
      'occupants, improved by the local hill-climb pass',
      () {
        final buttons = {
          'A': _button('A', page: 0, x: 0, y: 0),
          'B': _button('B', page: 0, x: 1, y: 0),
          'C': _button('C', page: 0, x: 0, y: 1),
          'D': _button('D', page: 0, x: 1, y: 1),
        };
        final preview = _predict(
          buttons: buttons,
          colSpan: 2,
          rowSpan: 2,
          currentPageIndex: 0,
          existingPageCount: 1,
          targetCol: 0,
          targetRow: 0,
        )!;

        expect(preview.movedButtons.keys, {'A', 'B', 'C', 'D'});
        // The greedy eviction pass (each widget claiming the free cell
        // nearest its OWN original position, in reading order) would send A
        // and B to the two free page-0 cells and spill C and D onto a new
        // page. The bounded local-improvement pass then finds a strictly
        // less-disruptive swap: C and D (already on page 0) settle into the
        // two vacated cells instead, so it is A and B — not C and D — that
        // end up on the new page. Either pairing moves the same four
        // widgets by the same total distance, but keeping C/D in place and
        // moving A/B instead reads identically here; what the swap actually
        // improves is which widgets incur the page-change cost, which
        // legitimately differs by original page context in the general
        // case. See the score assertion below for the concrete improvement.
        expect(preview.movedButtons['A'], _placementOf(page: 1, x: 0, y: 0));
        expect(preview.movedButtons['B'], _placementOf(page: 1, x: 1, y: 0));
        expect(preview.movedButtons['C'], _placementOf(page: 0, x: 0, y: 2));
        expect(preview.movedButtons['D'], _placementOf(page: 0, x: 1, y: 2));

        // The naive (pre-hill-climb) greedy assignment scores 2956 by the
        // same weights predictInsertionLayout uses internally (100/widget +
        // 1000 for each of the 2 page changes + 500 for the new page + 40
        // for same-page distance + 16 reading-order penalty). The
        // local-improvement pass must strictly beat that.
        expect(preview.disruptionScore, lessThan(2956));

        // The result must always be collision-free by construction.
        final merged = {...buttons};
        for (final entry in preview.movedButtons.entries) {
          final original = buttons[entry.key]!;
          merged[entry.key] = original.copyWith(
            pageIndex: entry.value.pageIndex,
            gridX: entry.value.gridX,
            gridY: entry.value.gridY,
          );
        }
        merged['__target__'] = _button(
          '__target__',
          page: preview.target.pageIndex,
          x: preview.target.gridX,
          y: preview.target.gridY,
          colSpan: preview.target.colSpan,
          rowSpan: preview.target.rowSpan,
        );
        expect(validateGridOccupancy(merged), isEmpty);
      },
    );

    test(
      'a row-major reflow that avoids a new page out-scores direct '
      'displacement that would need one',
      () {
        // Page 0: X (2x1, the direct overlap target) plus Y and Z scattered
        // so X cannot fit anywhere else on page 0 once evicted.
        final buttons = {
          'X': _button('X', page: 0, x: 0, y: 0, colSpan: 2, rowSpan: 1),
          'Y': _button('Y', page: 0, x: 0, y: 1),
          'Z': _button('Z', page: 0, x: 1, y: 2),
          // Page 1: one widget in every row, all in column 0, so no row has
          // a free horizontal pair -> direct displacement can't land X here
          // either and would be forced onto a brand-new page 2.
          'W': _button('W', page: 1, x: 0, y: 0),
          'V': _button('V', page: 1, x: 0, y: 1),
          'U': _button('U', page: 1, x: 0, y: 2),
        };
        final preview = _predict(
          buttons: buttons,
          colSpan: 2,
          rowSpan: 1,
          currentPageIndex: 0,
          existingPageCount: 2,
          targetCol: 0,
          targetRow: 0,
        )!;

        expect(preview.strategy, InsertionStrategy.rowMajorReflow);
        // Reflow keeps everything within the two pages that already exist —
        // exactly the "free to move non-overlapping widgets if it produces
        // a better layout" case direct displacement alone cannot reach.
        expect(
          preview.movedButtons.values.every((p) => p.pageIndex <= 1),
          isTrue,
        );
        // X — the widget actually sitting under the drop — stays on page 0
        // instead of being exiled to a new page, which is what a plain
        // direct-displacement-only engine would have had to do here.
        expect(preview.movedButtons['X']?.pageIndex, 0);

        final merged = {...buttons};
        for (final entry in preview.movedButtons.entries) {
          final original = buttons[entry.key]!;
          merged[entry.key] = original.copyWith(
            pageIndex: entry.value.pageIndex,
            gridX: entry.value.gridX,
            gridY: entry.value.gridY,
          );
        }
        merged['__target__'] = _button(
          '__target__',
          page: preview.target.pageIndex,
          x: preview.target.gridX,
          y: preview.target.gridY,
          colSpan: preview.target.colSpan,
          rowSpan: preview.target.rowSpan,
        );
        expect(validateGridOccupancy(merged), isEmpty);
      },
    );
  });
}

GridPlacement _placementOf({required int page, required int x, required int y}) =>
    GridPlacement(pageIndex: page, gridX: x, gridY: y);
