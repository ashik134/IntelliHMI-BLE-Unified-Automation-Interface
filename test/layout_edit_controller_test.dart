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
import 'package:rev_crane_control_ops/models/control_orientation.dart';
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

  test(
    'orientation edit on a multi-zone slider swaps its grid allocation',
    () async {
      // Multi-zone sliders are orientation-supported (not a structural-
      // rotation exception) — see ButtonConfig.supportsOrientation. Rotation
      // must have zero effect on this type going forward.
      await editCtrl.enter();
      final result = editCtrl.addButton(
        const ButtonConfig(
          id: 'zones',
          type: ButtonType.bidirectionalSlider5Step,
          plcMapping: PlcOutputVariant.df2,
        ),
      );
      expect(result.isValid, isTrue);
      var slider = editCtrl.draft.resolvedButtons['zones']!;
      expect((slider.gridColumnSpan, slider.gridRowSpan), (2, 1));

      editCtrl.updateButton(
        'zones',
        (button) => button.copyWith(
          customProperties: ButtonConfig.applyOrientation(
            button.type,
            button.customProperties,
            ControlOrientation.vertical,
          ),
        ),
      );
      slider = editCtrl.draft.resolvedButtons['zones']!;
      expect(
        ButtonConfig.orientationOf(slider.type, slider.customProperties),
        ControlOrientation.vertical,
      );
      expect((slider.gridColumnSpan, slider.gridRowSpan), (1, 2));
      expect(editCtrl.lastValidation.isValid, isTrue);

      editCtrl.updateButton(
        'zones',
        (button) => button.copyWith(rotation: ButtonRotation.deg90),
      );
      slider = editCtrl.draft.resolvedButtons['zones']!;
      expect(
        (slider.gridColumnSpan, slider.gridRowSpan),
        (1, 2),
        reason: 'rotation must be inert for an orientation-supported type',
      );

      editCtrl.updateButton(
        'zones',
        (button) => button.copyWith(
          customProperties: ButtonConfig.applyOrientation(
            button.type,
            button.customProperties,
            ControlOrientation.horizontal,
          ),
        ),
      );
      slider = editCtrl.draft.resolvedButtons['zones']!;
      expect((slider.gridColumnSpan, slider.gridRowSpan), (2, 1));
      expect(editCtrl.lastValidation.isValid, isTrue);
    },
  );

  test(
    'rotating a Multi-Step Spring-Return Slider swaps its grid allocation '
    'and 360 behaves the same as 0',
    () async {
      // sliderButton is one of the two dedicated structural-rotation
      // exceptions — see ButtonConfig.supportsStructuralRotation.
      await editCtrl.enter();
      final result = editCtrl.addButton(
        const ButtonConfig(
          id: 'step',
          type: ButtonType.sliderButton,
          plcMapping: PlcOutputVariant.df2,
        ),
      );
      expect(result.isValid, isTrue);
      var slider = editCtrl.draft.resolvedButtons['step']!;
      expect((slider.gridColumnSpan, slider.gridRowSpan), (1, 2));

      editCtrl.updateButton(
        'step',
        (button) => button.copyWith(rotation: ButtonRotation.deg90),
      );
      slider = editCtrl.draft.resolvedButtons['step']!;
      expect(slider.rotation, ButtonRotation.deg90);
      expect((slider.gridColumnSpan, slider.gridRowSpan), (2, 1));
      expect(editCtrl.lastValidation.isValid, isTrue);

      editCtrl.updateButton(
        'step',
        (button) => button.copyWith(rotation: ButtonRotation.deg270),
      );
      slider = editCtrl.draft.resolvedButtons['step']!;
      expect((slider.gridColumnSpan, slider.gridRowSpan), (2, 1));
      expect(editCtrl.lastValidation.isValid, isTrue);

      // "360°" is offered in the UI as a separate option but applies the
      // same ButtonRotation.none as "0°" — see GeneralTab.
      editCtrl.updateButton(
        'step',
        (button) => button.copyWith(rotation: ButtonRotation.none),
      );
      slider = editCtrl.draft.resolvedButtons['step']!;
      expect((slider.gridColumnSpan, slider.gridRowSpan), (1, 2));
      expect(editCtrl.lastValidation.isValid, isTrue);
    },
  );

  test(
    'an orientation edit that would collide displaces only the unlocked '
    'neighbor to the nearest free cell',
    () async {
      await editCtrl.enter();
      editCtrl.addButton(
        const ButtonConfig(
          id: 'zones',
          type: ButtonType.bidirectionalSlider5Step,
          plcMapping: PlcOutputVariant.df2,
        ),
      );
      final zonesBefore = editCtrl.draft.resolvedButtons['zones']!;
      expect((zonesBefore.gridX, zonesBefore.gridY), (0, 0));
      expect((zonesBefore.gridColumnSpan, zonesBefore.gridRowSpan), (2, 1));

      editCtrl.addButton(_sampleButton('neighbor'));
      final neighborBefore = editCtrl.draft.resolvedButtons['neighbor']!;
      expect(
        (neighborBefore.gridX, neighborBefore.gridY),
        (0, 1),
        reason: 'first free slot after the 2x1 slider at (0,0)-(1,0)',
      );

      // Flipping to vertical shrinks "zones" to 1x2 at (0,0)-(0,1), which
      // now overlaps "neighbor" at (0,1).
      editCtrl.updateButton(
        'zones',
        (button) => button.copyWith(
          customProperties: ButtonConfig.applyOrientation(
            button.type,
            button.customProperties,
            ControlOrientation.vertical,
          ),
        ),
      );

      final zonesAfter = editCtrl.draft.resolvedButtons['zones']!;
      expect((zonesAfter.gridColumnSpan, zonesAfter.gridRowSpan), (1, 2));
      final neighborAfter = editCtrl.draft.resolvedButtons['neighbor']!;
      expect(
        (neighborAfter.gridX, neighborAfter.gridY) ==
            (neighborBefore.gridX, neighborBefore.gridY),
        isFalse,
        reason: 'the unlocked neighbor must have been displaced',
      );
      expect(editCtrl.lastValidation.isValid, isTrue);
      expect(editCtrl.placementError, isNull);
    },
  );

  test(
    'an orientation edit that would displace a locked neighbor is rejected '
    'and the draft is left untouched',
    () async {
      await editCtrl.enter();
      editCtrl.addButton(
        const ButtonConfig(
          id: 'zones',
          type: ButtonType.bidirectionalSlider5Step,
          plcMapping: PlcOutputVariant.df2,
        ),
      );
      editCtrl.addButton(_sampleButton('neighbor'));
      editCtrl.updateButton(
        'neighbor',
        (button) => button.copyWith(locked: true),
      );

      final zonesBefore = editCtrl.draft.resolvedButtons['zones']!;
      final neighborBefore = editCtrl.draft.resolvedButtons['neighbor']!;

      editCtrl.updateButton(
        'zones',
        (button) => button.copyWith(
          customProperties: ButtonConfig.applyOrientation(
            button.type,
            button.customProperties,
            ControlOrientation.vertical,
          ),
        ),
      );

      expect(
        editCtrl.draft.resolvedButtons['zones'],
        zonesBefore,
        reason: 'a rejected orientation change must leave the draft exactly '
            'as it was',
      );
      expect(editCtrl.draft.resolvedButtons['neighbor'], neighborBefore);
      expect(editCtrl.placementError, isNotNull);
    },
  );

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

    test(
      'exit drops a page left empty by editing and remaps later pages down',
      () async {
        await editCtrl.enter();
        // Default grid is 2x3 (6 slots): six 1x1 buttons exactly fill page
        // 0, so the seventh spills onto a fresh page 1.
        for (var i = 0; i < 6; i++) {
          editCtrl.addButton(_sampleButton('p0_$i'));
        }
        editCtrl.addButton(_sampleButton('p1'));
        expect(editCtrl.draft.resolvedButtons['p1']!.pageIndex, 1);
        expect(editCtrl.draft.controlPageCount, 2);

        // Emptying page 1 without leaving Edit Mode — deleteButton never
        // compacts on its own (see buildButtonDelete's doc comment), so the
        // now-blank page 1 stays in controlPageCount until Done is pressed.
        editCtrl.deleteButton('p1');
        expect(editCtrl.draft.controlPageCount, 2);

        final result = await editCtrl.exit();
        expect(result.isValid, isTrue);
        expect(editCtrl.draft.controlPageCount, 1);
        expect(editCtrl.draft.resolvedButtons.containsKey('p1'), isFalse);
        for (var i = 0; i < 6; i++) {
          expect(editCtrl.draft.resolvedButtons['p0_$i']!.pageIndex, 0);
        }
      },
    );

    test('exit keeps the required base page even when it is empty', () async {
      await editCtrl.enter();
      final result = await editCtrl.exit();
      expect(result.isValid, isTrue);
      expect(editCtrl.draft.controlPageCount, 1);
    });

    test(
      'exit re-points a mounted control screen away from a page it just dropped',
      () async {
        await editCtrl.enter();
        for (var i = 0; i < 6; i++) {
          editCtrl.addButton(_sampleButton('p0_$i'));
        }
        editCtrl.addButton(_sampleButton('p1'));
        editCtrl.deleteButton('p1');

        final navigatedTo = <int>[];
        editCtrl.registerPlacementSurface(
          'owner',
          PlacementSurface(
            canvasRect: () => _canvasRect,
            // Operator was still sitting on page 1 (now empty) when Done
            // was pressed.
            currentPageIndex: () => 1,
            navigateToPage: navigatedTo.add,
          ),
        );

        final result = await editCtrl.exit();
        expect(result.isValid, isTrue);
        expect(navigatedTo, [0]);
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

  group('undo / redo', () {
    test('canUndo/canRedo are both false right after enter', () async {
      await editCtrl.enter();
      expect(editCtrl.canUndo, isFalse);
      expect(editCtrl.canRedo, isFalse);
    });

    test('undo reverts the most recent completed change', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);

      editCtrl.undo();

      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
      expect(editCtrl.canUndo, isFalse);
      expect(editCtrl.canRedo, isTrue);
    });

    test('redo reapplies the most recently undone change', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      editCtrl.undo();

      editCtrl.redo();

      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);
      expect(editCtrl.canUndo, isTrue);
      expect(editCtrl.canRedo, isFalse);
    });

    test('undo walks back multiple independent changes one at a time', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      editCtrl.addButton(_sampleButton('b'));
      editCtrl.deleteButton('a');
      final buttons = editCtrl.draft.resolvedButtons;
      expect(buttons.containsKey('a'), isFalse);
      expect(buttons.containsKey('b'), isTrue);

      editCtrl.undo(); // undo the delete of 'a'
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);
      expect(editCtrl.draft.resolvedButtons.containsKey('b'), isTrue);

      editCtrl.undo(); // undo adding 'b'
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);
      expect(editCtrl.draft.resolvedButtons.containsKey('b'), isFalse);

      editCtrl.undo(); // undo adding 'a'
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
      expect(editCtrl.canUndo, isFalse);
    });

    test(
      'making a new change after undo clears the redo history',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('a'));
        editCtrl.undo();
        expect(editCtrl.canRedo, isTrue);

        editCtrl.addButton(_sampleButton('b'));

        expect(editCtrl.canRedo, isFalse);
        expect(editCtrl.draft.resolvedButtons.containsKey('b'), isTrue);
      },
    );

    test('undo/redo cover widget deletion', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      editCtrl.deleteButton('a');
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);

      editCtrl.undo();
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isTrue);

      editCtrl.redo();
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
    });

    test('undo/redo cover a grid layout change', () async {
      await editCtrl.enter();
      final original = editCtrl.draft.gridLayout;
      editCtrl.applyGridLayout(GridLayoutOption.fourByFour);
      expect(editCtrl.draft.gridLayout, GridLayoutOption.fourByFour);

      editCtrl.undo();
      expect(editCtrl.draft.gridLayout, original);

      editCtrl.redo();
      expect(editCtrl.draft.gridLayout, GridLayoutOption.fourByFour);
    });

    test(
      'undo/redo cover the widget movement + addition reflow from a '
      'catalogue drop',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('occupant')); // lands at (0,0)
        editCtrl.registerPlacementSurface(Object(), _fixedSurface());
        _beginPlacement(editCtrl);
        editCtrl.handleCatalogueDrop(
          globalDropOffset: _offsetForCell(0, 0),
          previewSize: _previewSize,
        );
        editCtrl.commitSettledPlacement();

        final afterPlacement = editCtrl.draft;
        final occupantAfter = afterPlacement.resolvedButtons['occupant']!;
        expect(
          occupantAfter.pageIndex == 0 &&
              occupantAfter.gridX == 0 &&
              occupantAfter.gridY == 0,
          isFalse,
        );

        editCtrl.undo();

        final occupantRestored = editCtrl.draft.resolvedButtons['occupant']!;
        expect(occupantRestored.gridX, 0);
        expect(occupantRestored.gridY, 0);
        expect(
          editCtrl.draft.resolvedButtons.keys.any(
            (id) => id.startsWith('placed_'),
          ),
          isFalse,
        );

        editCtrl.redo();
        expect(editCtrl.draft, afterPlacement);
      },
    );

    test(
      'a history batch coalesces many mutations (e.g. slider drag frames) '
      'into a single undo entry',
      () async {
        await editCtrl.enter();
        editCtrl.addButton(_sampleButton('a'));
        final beforeBatch = editCtrl.draft;

        editCtrl.beginHistoryBatch();
        for (var radius = 1; radius <= 5; radius++) {
          editCtrl.updateButton(
            'a',
            (b) => b.copyWith(
              style: b.style.copyWith(cornerRadius: radius.toDouble()),
            ),
          );
        }
        expect(
          editCtrl.draft.resolvedButtons['a']!.style.cornerRadius,
          5.0,
        );
        // Nothing is pushed onto the undo stack until the batch ends.
        editCtrl.endHistoryBatch();

        editCtrl.undo();
        // One undo restores the pre-batch state directly, not one of the
        // five intermediate slider frames.
        expect(editCtrl.draft, beforeBatch);
      },
    );

    test('an empty history batch pushes no entry', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      final before = editCtrl.draft;

      editCtrl.beginHistoryBatch();
      editCtrl.endHistoryBatch();

      expect(editCtrl.draft, before);
      // canUndo still reflects only the earlier addButton entry.
      editCtrl.undo();
      expect(editCtrl.draft.resolvedButtons.containsKey('a'), isFalse);
      expect(editCtrl.canUndo, isFalse);
    });

    test('history is bounded to avoid unlimited memory growth', () async {
      await editCtrl.enter();
      for (var i = 0; i < 60; i++) {
        editCtrl.addButton(_sampleButton('btn$i'));
      }
      var undoCount = 0;
      while (editCtrl.canUndo) {
        editCtrl.undo();
        undoCount++;
      }
      expect(undoCount, 50);
    });

    test('undo/redo are unavailable mid-placement drag', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      expect(editCtrl.canUndo, isTrue);

      editCtrl.registerPlacementSurface(Object(), _fixedSurface());
      _beginPlacement(editCtrl);
      expect(editCtrl.canUndo, isFalse);

      editCtrl.cancelCataloguePlacement();
      expect(editCtrl.canUndo, isTrue);
    });

    test('enter() resets history from a prior edit session', () async {
      await editCtrl.enter();
      editCtrl.addButton(_sampleButton('a'));
      await editCtrl.exit();

      await editCtrl.enter();
      expect(editCtrl.canUndo, isFalse);
      expect(editCtrl.canRedo, isFalse);
    });
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
