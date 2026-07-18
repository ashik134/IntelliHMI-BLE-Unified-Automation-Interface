import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_canvas.dart';

Widget _harness(CustomizationModeController customCtrl) {
  return MultiProvider(
    providers: [ChangeNotifierProvider.value(value: customCtrl)],
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: Consumer<CustomizationModeController>(
            builder: (context, ctrl, _) => CustomizationCanvas(
              layoutCfg: ctrl.draft,
              roles: const [ControlRole.hoistUp, ControlRole.hoistDown],
              onEditRole: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

Future<CustomizationModeController> _controller() async {
  final craneController = CraneController();
  final layoutSettingsController = LayoutSettingsController();
  final customCtrl = CustomizationModeController(
    layoutSettings: layoutSettingsController,
    craneController: craneController,
  );
  await customCtrl.enter();
  return customCtrl;
}

Future<void> _dragButtonToSlot(
  WidgetTester tester, {
  required String buttonId,
  required int targetSlot,
}) async {
  final from = tester.getCenter(find.byKey(ValueKey(buttonId)));
  final to = tester.getCenter(find.byKey(ValueKey('control_slot_$targetSlot')));
  final gesture = await tester.startGesture(from);
  await tester.pump(const Duration(milliseconds: 650));
  await gesture.moveTo(to);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dragging onto an occupied slot swaps button slot indices', (
    tester,
  ) async {
    final customCtrl = await _controller();

    await tester.pumpWidget(_harness(customCtrl));
    await tester.pump();

    await _dragButtonToSlot(
      tester,
      buttonId: ControlRole.hoistUp.name,
      targetSlot: 1,
    );

    expect(customCtrl.draft.buttonFor(ControlRole.hoistUp)!.slotIndex, 1);
    expect(customCtrl.draft.buttonFor(ControlRole.hoistDown)!.slotIndex, 0);
  });

  testWidgets('slot drag does not mutate legacy canvas coordinates', (
    tester,
  ) async {
    final customCtrl = await _controller();
    final before = customCtrl.draft.buttonFor(ControlRole.hoistUp)!;

    await tester.pumpWidget(_harness(customCtrl));
    await tester.pump();

    await _dragButtonToSlot(
      tester,
      buttonId: ControlRole.hoistUp.name,
      targetSlot: 1,
    );

    final after = customCtrl.draft.buttonFor(ControlRole.hoistUp)!;
    expect(after.canvasX, before.canvasX);
    expect(after.canvasY, before.canvasY);
  });
}
