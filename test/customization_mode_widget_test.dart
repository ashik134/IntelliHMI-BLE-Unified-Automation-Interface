// Exercises the Customization Mode UI end-to-end against the real
// ControlScreen widget tree — no BLE hardware needed, since CraneController
// is constructed fresh (never connected) and every control screen affordance
// used here (AppBar action, edit tiles, bottom sheet, Apply/Discard bar)
// only depends on connection/e-stop state that defaults safely to
// disconnected/idle.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/screens/plc14_control_screen.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_mode_bar.dart';

Widget _harness() {
  final craneController = CraneController();
  final layoutSettingsController = LayoutSettingsController();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: craneController),
      ChangeNotifierProvider.value(value: layoutSettingsController),
      ChangeNotifierProxyProvider2<
        CraneController,
        LayoutSettingsController,
        CustomizationModeController
      >(
        create: (_) => CustomizationModeController(
          layoutSettings: layoutSettingsController,
          craneController: craneController,
        ),
        update: (_, _, _, previous) => previous!,
      ),
    ],
    child: const MaterialApp(home: ControlScreen()),
  );
}

void main() {
  testWidgets(
    'entering Customization Mode shows the Apply/Discard bar and edit badges',
    (tester) async {
      await tester.pumpWidget(_harness());
      await tester.pump();
      expect(tester.takeException(), isNull);

      // Normal mode: no customization bar, tune icon present.
      expect(find.byType(CustomizationModeBar), findsNothing);
      final customizeAction = find.byTooltip('Customize Layout');
      expect(customizeAction, findsOneWidget);

      await tester.tap(customizeAction);
      await tester.pump();
      await tester.pump(); // second pump lets stopAllMotion()'s Future resolve

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomizationModeBar), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      // The two hoist buttons should now show a Customize (pencil) badge each.
      expect(find.byIcon(Icons.edit_rounded), findsNWidgets(2));

      // Opening a per-button edit sheet shouldn't throw and should show its tabs.
      // ControlScreen runs an infinite pulse animation, so pumpAndSettle would
      // never converge — advance a few fixed frames instead.
      await tester.tap(find.byIcon(Icons.edit_rounded).first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.text('TYPE'), findsOneWidget);
      expect(find.text('APPEARANCE'), findsOneWidget);

      // Close the sheet, then discard out of Customization Mode.
      await tester.tap(find.byIcon(Icons.close_rounded).first);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.tap(find.text('Discard'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(CustomizationModeBar), findsNothing);
    },
  );
}
