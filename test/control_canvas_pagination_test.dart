import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/core/theme/app_colors.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_canvas.dart';

void main() {
  testWidgets('arrows navigate pages and hide at the canvas boundaries', (
    tester,
  ) async {
    await tester.pumpWidget(const _PaginationHarness(isEditing: false));

    expect(
      find.byKey(const ValueKey('control_canvas_previous_page')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('control_canvas_next_page')),
      findsOneWidget,
    );
    expect(_dotColor(tester, 0), AppColors.selectionViolet);
    expect(_dotColor(tester, 1), AppColors.darkTextSub.withAlpha(60));

    await tester.tap(find.byKey(const ValueKey('control_canvas_next_page')));
    await tester.pumpAndSettle();

    expect(_dotColor(tester, 1), AppColors.selectionViolet);
    expect(
      find.byKey(const ValueKey('control_canvas_previous_page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('control_canvas_next_page')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('control_canvas_next_page')));
    await tester.pumpAndSettle();

    expect(_dotColor(tester, 2), AppColors.selectionViolet);
    expect(
      find.byKey(const ValueKey('control_canvas_previous_page')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('control_canvas_next_page')),
      findsNothing,
    );
  });

  testWidgets('existing edit and live page-scroll physics are preserved', (
    tester,
  ) async {
    await tester.pumpWidget(const _PaginationHarness(isEditing: false));
    expect(_pageView(tester).physics, isA<NeverScrollableScrollPhysics>());

    await tester.pumpWidget(const _PaginationHarness(isEditing: true));
    expect(_pageView(tester).physics, isA<PageScrollPhysics>());

    await tester.drag(
      find.byKey(const ValueKey('control_canvas_page_view')),
      const Offset(-320, 0),
    );
    await tester.pumpAndSettle();

    expect(_dotColor(tester, 1), AppColors.selectionViolet);
  });

  for (final style in CanvasPageTransitionStyle.values) {
    testWidgets('${style.displayName} transition navigates between pages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _PaginationHarness(isEditing: true, transitionStyle: style),
      );

      if (style == CanvasPageTransitionStyle.slide) {
        expect(
          find.byKey(
            ValueKey('control_canvas_page_effect_${style.name}_0'),
          ),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(
            ValueKey('control_canvas_page_effect_${style.name}_0'),
          ),
          findsOneWidget,
        );
      }

      await tester.drag(
        find.byKey(const ValueKey('control_canvas_page_view')),
        const Offset(-320, 0),
      );
      await tester.pumpAndSettle();

      expect(_dotColor(tester, 1), AppColors.selectionViolet);
      expect(tester.takeException(), isNull);
    });
  }
}

PageView _pageView(WidgetTester tester) => tester.widget<PageView>(
  find.byKey(const ValueKey('control_canvas_page_view')),
);

Color? _dotColor(WidgetTester tester, int index) {
  final dot = tester.widget<AnimatedContainer>(
    find.byKey(ValueKey('control_canvas_page_dot_$index')),
  );
  return (dot.decoration as BoxDecoration).color;
}

class _PaginationHarness extends StatelessWidget {
  const _PaginationHarness({
    required this.isEditing,
    this.transitionStyle = CanvasPageTransitionStyle.slide,
  });

  final bool isEditing;
  final CanvasPageTransitionStyle transitionStyle;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 280,
            child: ControlCanvas(
              layoutCfg: const ControlLayoutConfig(
                controlPageCount: 3,
                buttonsAreAuthoritative: true,
              ),
              isEditing: isEditing,
              activeStateFor: (_) => ControlState.idle,
              isDisabled: (_) => false,
              onCommand: (_, _) {},
              pageTransitionStyle: transitionStyle,
            ),
          ),
        ),
      ),
    );
  }
}
