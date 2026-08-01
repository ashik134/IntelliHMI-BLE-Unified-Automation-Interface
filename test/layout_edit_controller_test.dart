import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';

ButtonConfig _sampleButton(String id) => ButtonConfig(
  id: id,
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  label: 'Test Button',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LayoutSettingsController layoutSettings;
  late LayoutEditController editCtrl;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    layoutSettings = LayoutSettingsController();
    editCtrl = LayoutEditController(
      layoutSettings: layoutSettings,
      craneController: CraneController(),
    );
  });

  group('enter', () {
    test(
      'seeds the draft from the committed config and pins a bucket',
      () async {
        await editCtrl.enter();
        expect(editCtrl.isEditing, isTrue);
        expect(editCtrl.draft, layoutSettings.configFor(editCtrl.activeBucket));
      },
    );

    test('is a no-op when already editing', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final draftBeforeSecondEnter = editCtrl.draft;
      await editCtrl.enter();
      expect(editCtrl.draft, draftBeforeSecondEnter);
    });
  });

  // Every mutation method below is only ever called by the real UI after
  // enter() has seeded the draft from the committed (empty-grid) default —
  // so each test enters first, matching the invariant these methods rely on.

  group('addButton', () {
    test('places the button in the draft and selects it', () async {
      await editCtrl.enter();
      final result = editCtrl.addButton(_sampleButton('a'));
      expect(result.isValid, isTrue);
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);
      expect(editCtrl.selectedButtonId, 'a');
    });

    test('fails and leaves the draft untouched on an id collision', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final draftBefore = editCtrl.draft;
      final result = editCtrl.addButton(_sampleButton('a'));
      expect(result.isValid, isFalse);
      expect(editCtrl.draft, draftBefore);
    });
  });

  group('deleteButton', () {
    test(
      'removes the button and clears selection if it was selected',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('a'));
        final result = editCtrl.deleteButton('a');
        expect(result.isValid, isTrue);
        expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
        expect(editCtrl.selectedButtonId, isNull);
      },
    );

    test('refuses to delete a safety-role control', () async {
      // The two safety controls are always seeded with fixed ids equal to
      // their ControlRole name (see ButtonConfig.estopDefault).
      await editCtrl.enter();
      final result = editCtrl.deleteButton('estop');
      expect(result.isValid, isFalse);
    });

    test('reports not-found for an unknown id', () async {
      await editCtrl.enter();
      final result = editCtrl.deleteButton('does-not-exist');
      expect(result.isValid, isFalse);
    });
  });

  test('toggleArrangement flips exactly one arrangement field', () async {
    await editCtrl.enter();
    final before = editCtrl.draft.arrangementConfig;
    editCtrl.toggleArrangement(ArrangementToggle.sensorRow);
    final after = editCtrl.draft.arrangementConfig;
    expect(after.showSensorRow, !before.showSensorRow);
    expect(after.showLiveLEDs, before.showLiveLEDs);
    expect(after.showConnectionSubtitle, before.showConnectionSubtitle);
  });

  test('applyTemplate replaces the whole draft', () async {
    await editCtrl.enter();
    editCtrl.addButton(_sampleButton('a'));
    final template = const LayoutTemplateService().templates.first;
    editCtrl.applyTemplate(template);
    expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
  });

  group('save / exit', () {
    test('save persists the draft and stays in edit mode either way', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final result = await editCtrl.save();
      expect(result.isValid, isTrue);
      expect(
        layoutSettings
            .configFor(editCtrl.activeBucket)
            .resolvedButtons
            .containsKey('a'),
        isTrue,
      );
      expect(editCtrl.isEditing, isTrue);
    });

    test('exit leaves edit mode only on a valid save', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final result = await editCtrl.exit();
      expect(result.isValid, isTrue);
      expect(editCtrl.isEditing, isFalse);
    });

    test(
      'exit stays in edit mode and reports errors on an invalid draft',
      () async {
        await editCtrl.enter();
        editCtrl.updateDraftLabelConfig(
          editCtrl.draft.labelConfig.copyWith(estopSwipeInstruction: ''),
        );
        final result = await editCtrl.exit();
        expect(result.isValid, isFalse);
        expect(result.errors, isNotEmpty);
        expect(editCtrl.isEditing, isTrue);
      },
    );
  });
}
