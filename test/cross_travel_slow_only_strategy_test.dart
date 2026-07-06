import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/widgets/buttons/cross_travel_strategy.dart';

void main() {
  testWidgets(
    '3-zone cross-travel emits slow only and clears both directions on release',
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

      await tester.drag(find.byType(GestureDetector), const Offset(200, 0));
      await tester.pump();

      expect(
        commands,
        contains((
          id: ControlRole.traverseRight.name,
          state: ControlState.slow,
        )),
      );
      expect(commands.where((c) => c.state == ControlState.fast), isEmpty);

      expect(commands.takeLast(2).toList(), [
        (id: ControlRole.traverseLeft.name, state: ControlState.idle),
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
