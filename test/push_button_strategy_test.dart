import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart'
    show PushButtonWiringConfig;
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/widgets/buttons/industrial_spring_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/push_button_strategy.dart';

// Regression coverage for: push buttons visually activate but never dispatch
// a PLC command. Root cause was PushButtonStrategy never wiring
// IndustrialSpringButton.onChanged, which is the only hook a latching push
// button uses to report its toggled value — so latching buttons flipped
// their own local visual state but silently dropped onCommand.

void main() {
  group('PushButtonStrategy', () {
    testWidgets(
      'spring-return: press sends ACTIVE (slow), release sends IDLE',
      (tester) async {
        final commands = <({String id, ControlState state})>[];
        final config = ButtonConfig(
          id: ControlRole.hoistUp.name,
          type: ButtonType.pushButton,
          plcMapping: ControlRole.hoistUp.plcMapping!,
          role: ControlRole.hoistUp,
          label: 'UP',
          behavior: const ButtonBehaviorConfig(
            wiring: PushButtonWiringConfig.offMomentary, // spring-return
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => const PushButtonStrategy().build(
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
        );

        final gesture = await tester.startGesture(
          tester.getCenter(find.byType(IndustrialSpringButton)),
        );
        await tester.pump();

        expect(
          commands,
          contains((id: ControlRole.hoistUp.name, state: ControlState.slow)),
          reason: 'pointer down on a spring-return push button must send ACTIVE',
        );

        await gesture.up();
        await tester.pump();

        expect(
          commands.last,
          (id: ControlRole.hoistUp.name, state: ControlState.idle),
          reason: 'release must send IDLE',
        );
      },
    );

    testWidgets(
      'latching: tap ON sends ACTIVE, tap OFF sends IDLE',
      (tester) async {
        final commands = <({String id, ControlState state})>[];
        var externalActive = false;

        Widget buildTree() => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final config = ButtonConfig(
                  id: ControlRole.hoistDown.name,
                  type: ButtonType.pushButton,
                  plcMapping: ControlRole.hoistDown.plcMapping!,
                  role: ControlRole.hoistDown,
                  label: 'DOWN',
                  behavior: const ButtonBehaviorConfig(
                    wiring: PushButtonWiringConfig.offLatched, // latching
                  ),
                );
                return const PushButtonStrategy().build(
                  context: context,
                  config: config,
                  activeState: externalActive
                      ? ControlState.slow
                      : ControlState.idle,
                  isDisabled: false,
                  onCommand: (id, state) =>
                      commands.add((id: id, state: state)),
                );
              },
            ),
          ),
        );

        await tester.pumpWidget(buildTree());

        // Tap ON.
        await tester.tap(find.byType(IndustrialSpringButton));
        await tester.pump();

        expect(
          commands,
          contains((id: ControlRole.hoistDown.name, state: ControlState.slow)),
          reason:
              'tapping a latching push button ON must send ACTIVE via onChanged '
              '(this was the missing wiring that caused no PLC output)',
        );

        externalActive = true;
        await tester.pumpWidget(buildTree());
        await tester.pump();

        // Tap OFF.
        await tester.tap(find.byType(IndustrialSpringButton));
        await tester.pump();

        expect(
          commands.last,
          (id: ControlRole.hoistDown.name, state: ControlState.idle),
          reason: 'tapping a latching push button OFF must send IDLE',
        );
      },
    );
  });
}
