// Renders each new analog control type, at every ButtonRotation, through
// the real production entry point (ConfigurableButton, which applies the
// outer Transform.rotate exactly like the live control screens do) inside a
// tightly bounded box matching a typical grid-cell size. Asserts no
// exception is thrown — in particular no RenderFlex overflow, which is
// exactly the failure mode a rotated label with an un-swapped layout box
// would produce. This does not assert pixel-perfect visual upright-ness
// (that needs a golden test / manual check), but it does catch the overflow
// half of "labels shouldn't rotate and don't cause overflow" for every
// rotation the customization UI allows.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/configurable_button.dart';

void main() {
  final typesUnderTest = [
    ButtonType.analogJoystick1D,
    ButtonType.analogJoystick2D,
    ButtonType.analogSliderOT,
    ButtonType.analogSliderTOT,
    // Baseline: pre-existing types that already used ControlButtonLabelIcon
    // before this change, to prove the fix didn't regress them either.
    ButtonType.pushButton,
    ButtonType.toggle,
  ];

  for (final type in typesUnderTest) {
    for (final rotation in ButtonRotation.values) {
      testWidgets('$type at $rotation renders with no overflow/exception', (
        tester,
      ) async {
        final config = ButtonConfig(
          id: 'rotation_test_${type.name}_${rotation.name}',
          type: type,
          plcMapping: PlcOutputVariant.df2,
          label: 'A Reasonably Long Label',
          rotation: rotation,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 140,
                  height: 96,
                  child: ConfigurableButton(
                    config: config,
                    activeState: ControlState.idle,
                    isDisabled: false,
                    onCommand: (_, _) {},
                    onStateIdCommand: (_, _) {},
                    onAnalogCommand: (_, _) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
      });
    }
  }
}
