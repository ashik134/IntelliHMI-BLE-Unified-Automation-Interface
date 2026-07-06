import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/widgets/buttons/cross_travel_strategy.dart';

void main() {
  testWidgets(
    '3-zone cross-travel left slider: left drag emits traverseLeft slow, right drag emits traverseLeftFast slow, release clears both',
    (tester) async {
      final commands = <({String id, ControlState state})>[];
      final config = ButtonConfig(
        id: ControlRole.traverseLeft.name,
        type: ButtonType.crossTravelSlowOnly,
        plcMapping: ControlRole.traverseLeft.plcMapping!,
        role: ControlRole.traverseLeft,
        label: 'LEFT',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 320,
                  height: 140,
                  child: const CrossTravelSlowOnlyStrategy().build(
                    context: context,
                    config: config,
                    activeState: ControlState.idle,
                    isDisabled: false,
                    onCommand: (id, state) =>
                        commands.add((id: id, state: state)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag RIGHT → should emit kTraverseLeftFastKey (fast_lr modifier), NOT traverseRight.
      await tester.drag(find.byType(GestureDetector), const Offset(200, 0));
      await tester.pump();

      expect(
        commands,
        contains((id: kTraverseLeftFastKey, state: ControlState.slow)),
      );
      expect(
        commands.where((c) => c.id == ControlRole.traverseRight.name),
        isEmpty,
        reason: 'left slider must not activate the right direction',
      );
      expect(commands.where((c) => c.state == ControlState.fast), isEmpty);

      // On release both owned keys must be cleared.
      expect(commands.takeLast(2).toList(), [
        (id: ControlRole.traverseLeft.name, state: ControlState.idle),
        (id: kTraverseLeftFastKey, state: ControlState.idle),
      ]);
    },
  );

  testWidgets(
    '3-zone cross-travel right slider: right drag emits traverseRight slow, left drag emits traverseRightFast slow, release clears both',
    (tester) async {
      final commands = <({String id, ControlState state})>[];
      final config = ButtonConfig(
        id: ControlRole.traverseRight.name,
        type: ButtonType.crossTravelSlowOnly,
        plcMapping: ControlRole.traverseRight.plcMapping!,
        role: ControlRole.traverseRight,
        label: 'RIGHT',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: SizedBox(
                  width: 320,
                  height: 140,
                  child: const CrossTravelSlowOnlyStrategy().build(
                    context: context,
                    config: config,
                    activeState: ControlState.idle,
                    isDisabled: false,
                    onCommand: (id, state) =>
                        commands.add((id: id, state: state)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Drag LEFT → should emit kTraverseRightFastKey (fast_lr modifier), NOT traverseLeft.
      await tester.drag(find.byType(GestureDetector), const Offset(-200, 0));
      await tester.pump();

      expect(
        commands,
        contains((id: kTraverseRightFastKey, state: ControlState.slow)),
      );
      expect(
        commands.where((c) => c.id == ControlRole.traverseLeft.name),
        isEmpty,
        reason: 'right slider must not activate the left direction',
      );
      expect(commands.where((c) => c.state == ControlState.fast), isEmpty);

      // On release both owned keys must be cleared.
      expect(commands.takeLast(2).toList(), [
        (id: kTraverseRightFastKey, state: ControlState.idle),
        (id: ControlRole.traverseRight.name, state: ControlState.idle),
      ]);
    },
  );
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final list = toList();
    return list.skip(list.length - count);
  }
}
