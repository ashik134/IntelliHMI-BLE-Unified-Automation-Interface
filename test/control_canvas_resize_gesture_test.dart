import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_canvas.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regression coverage for the PageView-vs-resize-handle gesture conflict:
// both a page swipe and an edge-handle resize start from a horizontal (or
// vertical) drag on the same canvas, and the handle sits INSIDE the
// PageView's own itemBuilder, so without _ControlCanvasState's pointer-down
// scroll lock (see its _resizeScrollLocked doc comment), the PageView's own
// drag recognizer can win the gesture arena and swipe the page mid-resize —
// violating LayoutEditController's documented rule that a resize never
// leaves the widget's current page.
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ControlLayoutConfig twoPageLayout() => const ControlLayoutConfig(
    buttonsAreAuthoritative: true,
    controlPageCount: 2,
    buttons: <String, ButtonConfig>{
      'resizable': ButtonConfig(
        id: 'resizable',
        type: ButtonType.pushButton,
        plcMapping: PlcOutputVariant.df1,
        label: 'Resizable',
        gridX: 0,
        gridY: 0,
      ),
    },
  );

  Future<GlobalKey> pumpCanvas(
    WidgetTester tester, {
    required PageController pageController,
    ButtonResizeStartCallback? onResizeStart,
    ButtonResizeUpdateCallback? onResizeUpdate,
    ButtonResizeStartCallback? onResizeEnd,
  }) async {
    final canvasKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: canvasKey,
            child: ControlCanvas(
              layoutCfg: twoPageLayout(),
              isEditing: true,
              pageController: pageController,
              selectedButtonId: 'resizable',
              activeStateFor: (_) => ControlState.idle,
              isDisabled: (_) => true,
              onCommand: (_, _) {},
              onResizeStart: onResizeStart ?? (_, _) {},
              onResizeUpdate: onResizeUpdate ?? (_, _, _, _) {},
              onResizeEnd: onResizeEnd ?? (_, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return canvasKey;
  }

  testWidgets(
    'dragging a left/right resize handle resizes the widget without changing '
    "PageController.page (the fix's core claim)",
    (tester) async {
      final pageController = PageController();
      var resizeStarted = false;
      var resizeUpdated = false;
      await pumpCanvas(
        tester,
        pageController: pageController,
        onResizeStart: (_, _) => resizeStarted = true,
        onResizeUpdate: (_, _, _, _) => resizeUpdated = true,
      );

      // Locate a left/right handle by its wiring rather than hand-computed
      // pixel geometry: _ResizeHandleState.build() only wires
      // onHorizontalDragStart for a left/right handle (top/bottom wire
      // onVerticalDragStart instead — see its axis-inversion doc comment),
      // so this predicate is unambiguous. Two matches exist (left, right);
      // either proves the fix, so just take the first.
      final handleFinder = find
          .byWidgetPredicate(
            (w) => w is GestureDetector && w.onHorizontalDragStart != null,
          )
          .first;
      final handlePoint = tester.getCenter(handleFinder);

      final gesture = await tester.startGesture(handlePoint);
      await tester.pump(const Duration(milliseconds: 16));
      // A horizontal drag is exactly the direction the PageView's own
      // recognizer competes for — if the lock weren't in place, this is the
      // movement that would flip the page instead of resizing.
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();

      expect(resizeStarted, isTrue);
      expect(resizeUpdated, isTrue);
      expect(pageController.page, 0.0);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pageController.page, 0.0);
    },
  );

  testWidgets(
    'dragging empty canvas space still swipes to the next page',
    (tester) async {
      final pageController = PageController();
      final canvasKey = await pumpCanvas(
        tester,
        pageController: pageController,
      );

      final canvasRect = tester.getRect(find.byKey(canvasKey));
      // Bottom-right corner of the canvas: outside the selected widget's
      // cell (0, 0) and its resize handles entirely, so this drag must be
      // routed to the PageView untouched.
      final emptyPoint = Offset(canvasRect.right - 10, canvasRect.bottom - 10);

      await tester.dragFrom(
        emptyPoint,
        Offset(-canvasRect.width * 0.6, 0),
      );
      await tester.pumpAndSettle();

      expect(pageController.page, 1.0);
    },
  );
}
