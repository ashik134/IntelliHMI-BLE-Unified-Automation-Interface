import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties_sheet.dart';

class _RecordingNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Delete Widget removes only the draft instance and keeps the control route',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final layoutSettings = LayoutSettingsController();
      final craneController = CraneController();
      final editController = LayoutEditController(
        layoutSettings: layoutSettings,
        craneController: craneController,
      );
      await editController.enter();

      const deletedId = 'delete-from-properties';
      final addResult = editController.addButton(
        const ButtonConfig(
          id: deletedId,
          type: ButtonType.pushButton,
          plcMapping: PlcOutputVariant.df2,
          label: 'Delete me',
        ),
      );
      expect(addResult.isValid, isTrue);

      final draftBeforeDelete = editController.draft;
      final committedBeforeDelete = layoutSettings.configFor(
        editController.activeBucket,
      );
      final expectedRemainingButtons = {...draftBeforeDelete.resolvedButtons}
        ..remove(deletedId);
      final observer = _RecordingNavigatorObserver();

      await tester.pumpWidget(
        ChangeNotifierProvider<LayoutEditController>.value(
          value: editController,
          child: MaterialApp(
            navigatorObservers: [observer],
            home: Scaffold(
              body: Builder(
                builder: (scanContext) => Column(
                  children: [
                    const Text('Scan Devices route'),
                    ElevatedButton(
                      key: const ValueKey('open-control-route'),
                      onPressed: () {
                        Navigator.of(scanContext).push<void>(
                          MaterialPageRoute<void>(
                            builder: (controlContext) => Scaffold(
                              body: Column(
                                children: [
                                  const Text('Customization canvas'),
                                  ElevatedButton(
                                    key: const ValueKey('open-properties'),
                                    onPressed: () => showWidgetPropertiesSheet(
                                      controlContext,
                                      deletedId,
                                    ),
                                    child: const Text('Properties'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open control'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-control-route')));
      await tester.pumpAndSettle();
      expect(find.text('Customization canvas'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('open-properties')));
      await tester.pumpAndSettle();
      expect(find.text('Widget Properties'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Delete Widget'), findsOneWidget);
      await tester.tap(find.text('Delete Widget'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(editController.draft.resolvedButtons, expectedRemainingButtons);
      expect(editController.selectedButtonId, isNull);
      expect(
        layoutSettings.configFor(editController.activeBucket),
        committedBeforeDelete,
        reason: 'Delete must remain an editable-draft mutation until save.',
      );
      expect(find.text('Widget Properties'), findsNothing);
      expect(find.text('Customization canvas'), findsOneWidget);
      expect(find.text('Scan Devices route'), findsNothing);
      expect(
        observer.popCount,
        1,
        reason: 'Only the properties bottom sheet may be popped.',
      );
    },
  );
}
