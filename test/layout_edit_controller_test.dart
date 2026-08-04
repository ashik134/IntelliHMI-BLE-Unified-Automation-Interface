import 'package:flutter/painting.dart' show Offset, Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/button_behavior_config.dart';
import 'package:rev_crane_control_ops/models/button_catalog_entry.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/grid_layout_option.dart';
import 'package:rev_crane_control_ops/models/mutual_exclusion_config.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/services/layout_template_service.dart';

ButtonConfig _sampleButton(String id) => ButtonConfig(
  id: id,
  type: ButtonType.pushButton,
  plcMapping: PlcOutputVariant.df2,
  label: 'Test Button',
);

// Fixed canvas so a cell's pixel center maps back to an exact, unambiguous
// grid anchor — same convention as control_grid_utils_test.dart: 2 columns x
// 3 rows -> 100x100 cells over a 200x300 canvas.
const _canvasRect = Rect.fromLTWH(0, 0, 200, 300);
const _previewSize = Size(80, 80);

const _testCatalogEntry = CatalogEntry(
  category: CatalogCategory.digitalControls,
  group: 'Test',
  name: 'Test Button',
  description: 'Test',
  tags: [],
  buttonType: ButtonType.pushButton,
  previewSize: _previewSize,
);

/// The feedback avatar's top-left ([handleCatalogueDrop]/
/// [LayoutEditController.updatePlacementPreview]'s own coordinate space) so
/// its center lands exactly on grid cell (col, row).
Offset _offsetForCell(int col, int row) {
  final center = Offset(col * 100 + 50, row * 100 + 50);
  return center - Offset(_previewSize.width / 2, _previewSize.height / 2);
}

PlacementSurface _fixedSurface({int pageIndex = 0}) => PlacementSurface(
  canvasRect: () => _canvasRect,
  currentPageIndex: () => pageIndex,
  navigateToPage: (_) {},
);

/// Drives the same browsingCatalogue -> liftingCatalogueWidget ->
/// placingWidget sequence the real Widgets catalogue drives, so tests reach
/// placingWidget the same way production code does.
void _beginPlacement(LayoutEditController ctrl) {
  ctrl.enterCatalogueBrowsing();
  ctrl.beginCatalogueLift(_testCatalogEntry);
  ctrl.confirmPlacementStarted();
}

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

  test(
    "applyTemplate preserves the draft's current gridLayout instead of "
    'resetting it to default',
    () async {
      await editCtrl.enter();
      editCtrl.applyGridLayout(GridLayoutOption.threeByThree);
      final template = const LayoutTemplateService().templates.first;
      editCtrl.applyTemplate(template);
      expect(editCtrl.draft.gridLayout, GridLayoutOption.threeByThree);
    },
  );

  group('applyGridLayout', () {
    test('is a no-op when re-applying the currently active option', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final draftBefore = editCtrl.draft;
      editCtrl.applyGridLayout(GridLayoutOption.twoByThree);
      expect(editCtrl.draft, draftBefore);
    });

    test('switches the draft to the new shape', () async {
      await editCtrl.enter();
      editCtrl.applyGridLayout(GridLayoutOption.fourByFour);
      expect(editCtrl.draft.gridLayout, GridLayoutOption.fourByFour);
    });

    test(
      'reflows buttons that no longer fit a smaller grid instead of leaving '
      'them out of bounds',
      () async {
        await editCtrl.enter();
        editCtrl.applyGridLayout(GridLayoutOption.fourByFour);
        // Row-major placement on a 4-wide grid: a,b,c,d fill row 0
        // (cols 0-3), e starts row 1 — none of this fits a 2x2 grid.
        for (final id in ['a', 'b', 'c', 'd', 'e']) {
          editCtrl.addButton(_sampleButton(id));
        }

        editCtrl.applyGridLayout(GridLayoutOption.twoByTwo);

        expect(editCtrl.draft.gridLayout, GridLayoutOption.twoByTwo);
        final buttons = editCtrl.draft.resolvedButtons;
        // Nothing was dropped — repair relocates, it never deletes.
        expect(buttons.keys.toSet(), {
          'estop',
          'resetEstop',
          'a',
          'b',
          'c',
          'd',
          'e',
        });
        for (final button in buttons.values) {
          if (button.role != null || !button.visible) continue;
          expect(button.gridX + button.gridColumnSpan <= 2, isTrue);
          expect(button.gridY + button.gridRowSpan <= 2, isTrue);
        }
        // Only 4 slots exist per page on a 2x2 grid, so the 5th button must
        // have spilled onto a new page rather than overlapping another.
        expect(
          buttons.values.any((b) => b.role == null && b.pageIndex > 0),
          isTrue,
        );
      },
    );
  });

  group('grid layout persistence', () {
    test(
      'a non-default grid layout, and buttons placed beyond the legacy 2x3 '
      'footprint, survive save() + a fresh cold-start load()',
      () async {
        await editCtrl.enter();
        editCtrl.applyGridLayout(GridLayoutOption.fourByFour);
        // First two buttons fill columns 0-1 of row 0; the third lands at
        // column 2 — already outside the legacy fixed 2-column grid's
        // bounds, so this is a direct regression check for
        // LayoutSettingsController repairing against the WRONG (static)
        // grid on load.
        editCtrl.addButton(_sampleButton('a'));
        editCtrl.addButton(_sampleButton('b'));
        editCtrl.addButton(_sampleButton('c'));

        final saveResult = await editCtrl.save();
        expect(saveResult.isValid, isTrue);

        // A fresh controller reading from the same (mock) SharedPreferences
        // store simulates a full cold start/app relaunch.
        final freshSettings = LayoutSettingsController();
        await freshSettings.load();
        final reloaded = freshSettings.configFor(editCtrl.activeBucket);

        expect(reloaded.gridLayout, GridLayoutOption.fourByFour);
        final c = reloaded.resolvedButtons['c']!;
        expect(c.gridX, 2);
        expect(c.gridY, 0);
      },
    );
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

  group('placement preview', () {
    test(
      'updatePlacementPreview populates previewLayoutCfg without touching draft',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('occupant')); // lands at (0,0)
        final draftBefore = editCtrl.draft;

        editCtrl.registerPlacementSurface(Object(), _fixedSurface());
        _beginPlacement(editCtrl);
        editCtrl.updatePlacementPreview(
          globalOffset: _offsetForCell(0, 0),
          previewSize: _previewSize,
        );

        expect(editCtrl.draft, draftBefore);
        expect(editCtrl.previewLayoutCfg, isNot(draftBefore));
        final moved = editCtrl.previewLayoutCfg.resolvedButtons['occupant']!;
        expect(
          moved.pageIndex == 0 && moved.gridX == 0 && moved.gridY == 0,
          isFalse,
        );
      },
    );

    test('cancelCataloguePlacement restores previewLayoutCfg to draft', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('occupant'));
      editCtrl.registerPlacementSurface(Object(), _fixedSurface());
      _beginPlacement(editCtrl);
      editCtrl.updatePlacementPreview(
        globalOffset: _offsetForCell(0, 0),
        previewSize: _previewSize,
      );
      expect(editCtrl.previewLayoutCfg, isNot(editCtrl.draft));

      editCtrl.cancelCataloguePlacement();

      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
      expect(editCtrl.previewLayoutCfg, editCtrl.draft);
    });

    test(
      'commitSettledPlacement applies both the new button and any settling '
      'moves in one step',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('occupant'));
        editCtrl.registerPlacementSurface(Object(), _fixedSurface());
        _beginPlacement(editCtrl);

        editCtrl.handleCatalogueDrop(
          globalDropOffset: _offsetForCell(0, 0),
          previewSize: _previewSize,
        );
        expect(
          editCtrl.interactionMode,
          CustomizationInteractionMode.settlingWidget,
        );

        editCtrl.commitSettledPlacement();

        expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
        final buttons = editCtrl.draft.resolvedButtons;

        // The occupant that was sitting at (0,0) must have relocated
        // elsewhere in the SAME draft-mutating step, not just in the
        // (now-cleared) preview.
        final occupant = buttons['occupant']!;
        expect(
          occupant.pageIndex == 0 &&
              occupant.gridX == 0 &&
              occupant.gridY == 0,
          isFalse,
        );

        // The new button must have landed exactly at the target cell.
        final placedIds = buttons.keys.where((id) => id.startsWith('placed_'));
        expect(placedIds, hasLength(1));
        final placed = buttons[placedIds.first]!;
        expect(placed.pageIndex, 0);
        expect(placed.gridX, 0);
        expect(placed.gridY, 0);
      },
    );
  });

  group('resetButtonToDefault', () {
    test(
      'with a valid catalogEntryId, restores that exact entry\'s style/'
      'behavior/customProperties/label/rotation — not just anything sharing '
      'the same ButtonType',
      () async {
        await editCtrl.enter();
        final entry = kWidgetCatalog.firstWhere(
          (e) => e.name == 'Latching Push Button',
        );
        final customized = entry.buildPreviewConfig().copyWith(
          id: 'a',
          catalogEntryId: entry.id,
          label: 'Renamed',
          style: const ButtonStyleConfig(cornerRadius: 30),
          behavior: entry.behavior.copyWith(debounceMs: 500),
          rotation: ButtonRotation.deg180,
          icon: null,
          iconKey: 'bolt',
          stateMappings: const {
            'active': ButtonStateOutputMapping(
              stateId: 'active',
              activeVariants: {PlcOutputVariant.df3},
            ),
          },
          mutualExclusion: const MutualExclusionConfig(
            excludedButtonIds: {'other'},
          ),
        );
        editCtrl.addButton(customized);

        editCtrl.resetButtonToDefault('a');
        final result = editCtrl.draft.resolvedButtons['a']!;

        expect(result.label, entry.name);
        expect(result.style, const ButtonStyleConfig());
        expect(result.behavior, entry.behavior);
        expect(result.customProperties, entry.customProperties);
        expect(result.rotation, ButtonRotation.none);
        expect(result.icon, isNull);
        expect(result.iconKey, isNull);

        // Never touched — an appearance reset must never silently change
        // PLC wiring or safety interlocks.
        expect(result.stateMappings, customized.stateMappings);
        expect(result.mutualExclusion, customized.mutualExclusion);
      },
    );

    test(
      'with no catalogEntryId, resets style only — behavior/customProperties/'
      'label are left untouched since the origin variant is unknown',
      () async {
        await editCtrl.enter();
        final customized = _sampleButton('a').copyWith(
          label: 'Renamed',
          style: const ButtonStyleConfig(cornerRadius: 30),
          behavior: const ButtonBehaviorConfig(debounceMs: 500),
        );
        editCtrl.addButton(customized);

        editCtrl.resetButtonToDefault('a');
        final result = editCtrl.draft.resolvedButtons['a']!;

        expect(result.style, const ButtonStyleConfig());
        expect(result.label, 'Renamed');
        expect(result.behavior, customized.behavior);
      },
    );

    test('is a no-op for an unknown id', () async {
      await editCtrl.enter();
      final draftBefore = editCtrl.draft;
      editCtrl.resetButtonToDefault('does-not-exist');
      expect(editCtrl.draft, draftBefore);
    });
  });
}
