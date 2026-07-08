import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/widgets/buttons/industrial_spring_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/crane_slider_button.dart';

// Regression coverage for the shared release-flicker bug: a spring-return
// control must not visually reactivate after the user releases it, even if
// the widget's externally-supplied active state (standing in for delayed PLC
// status feedback in the real app) flips back to active a moment later.

void main() {
  group('IndustrialSpringButton', () {
    testWidgets(
      'stays idle after release even when isActive flips true again afterward (stale PLC echo)',
      (tester) async {
        bool isActive = false;
        late StateSetter setParentState;

        Widget buildTree() => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setParentState = setState;
                return IndustrialSpringButton(
                  label: 'HOIST UP',
                  icon: Icons.arrow_upward,
                  isActive: isActive,
                  isSpringReturn: true,
                  onPressed: () => setState(() => isActive = true),
                  onReleased: () => setState(() => isActive = false),
                );
              },
            ),
          ),
        );

        await tester.pumpWidget(buildTree());

        final center = tester.getCenter(find.byType(IndustrialSpringButton));

        // USER_DOWN
        final gesture = await tester.startGesture(center);
        await tester.pump();
        expect(
          tester.widget<IndustrialSpringButton>(
            find.byType(IndustrialSpringButton),
          ).isActive,
          isTrue,
          reason: 'press should immediately activate',
        );

        // USER_UP
        await gesture.up();
        await tester.pump();

        // Simulate a stale/delayed PLC status echo arriving AFTER release:
        // the parent's `isActive` flips true again on its own (same State,
        // same Element — only the value changes), exactly like
        // controller.activeCommand being overwritten by an in-flight status
        // notification for the press that was already released.
        setParentState(() => isActive = true);
        await tester.pump();

        // Verify via the rendered semantics/toggled flag to keep this a
        // black-box behavioral check rather than reaching into private state.
        final semantics = tester.getSemantics(
          find.byType(IndustrialSpringButton),
        );
        expect(
          semantics.hasFlag(SemanticsFlag.isToggled),
          isFalse,
          reason:
              'a stale post-release "active" update must not reactivate the '
              'button; only a fresh pointer-down may do that',
        );
      },
    );
  });

  group('CraneSliderButton', () {
    testWidgets(
      'stays idle after release even when externalState flips active again afterward (stale PLC echo)',
      (tester) async {
        final commands = <ControlState>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 140,
                height: 260,
                child: CraneSliderButton(
                  label: 'UP',
                  icon: Icons.arrow_upward,
                  isUp: true,
                  externalState: ControlState.idle,
                  onCommandChanged: commands.add,
                ),
              ),
            ),
          ),
        );

        // Drag the slider to commit an active (slow) state, then release.
        final sliderFinder = find.byType(Slider);
        await tester.drag(sliderFinder, const Offset(0, -60));
        await tester.pumpAndSettle();

        // Confirm the release actually sent idle.
        expect(commands, isNotEmpty);
        expect(commands.last, ControlState.idle);

        // Simulate a stale/delayed PLC status echo arriving AFTER release by
        // rebuilding with externalState reporting the pre-release speed.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 140,
                height: 260,
                child: CraneSliderButton(
                  label: 'UP',
                  icon: Icons.arrow_upward,
                  isUp: true,
                  externalState: ControlState.slow, // stale PLC_STATUS_ACTIVE
                  onCommandChanged: commands.add,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final slider = tester.widget<Slider>(sliderFinder);
        expect(
          slider.value,
          0.0,
          reason:
              'a stale post-release externalState must not move the slider '
              'thumb/visual back to active; only a fresh touch may do that',
        );
      },
    );
  });
}
