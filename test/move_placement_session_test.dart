import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_canvas.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/placement_cancel_bar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/settling_preview.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Reproduces the placement-relevant plumbing of Plc14ControlScreen's
// ControlCanvas + PlacementCancelBar + SettlingPreviewOverlay stack (same
// spirit as catalogue_placement_session_test.dart /
// intelligent_placement_session_test.dart), but drives a REAL long-press-drag
// on an ALREADY-PLACED widget instead of a catalogue card — proving
// LayoutEditController.beginMove/updateMovePreview/handleMoveDrop/
// commitMovedPlacement end-to-end through the real LongPressDraggable
// control_canvas.dart wires onto every occupied cell.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeControlHost extends StatefulWidget {
  const _FakeControlHost({required this.canvasKey});

  final GlobalKey canvasKey;

  @override
  State<_FakeControlHost> createState() => _FakeControlHostState();
}

class _FakeControlHostState extends State<_FakeControlHost> {
  late final LayoutEditController _editCtrl;

  @override
  void initState() {
    super.initState();
    _editCtrl = context.read<LayoutEditController>();
    _editCtrl.registerPlacementSurface(
      this,
      PlacementSurface(
        canvasRect: _canvasRect,
        currentPageIndex: () => 0,
        navigateToPage: (_) {},
      ),
    );
  }

  Rect _canvasRect() {
    final box =
        widget.canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void dispose() {
    _editCtrl.unregisterPlacementSurface(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _editCtrl,
      builder: (context, _) {
        final mode = _editCtrl.interactionMode;
        final movingId = _editCtrl.movingButtonId;
        final movingConfig = movingId == null
            ? null
            : _editCtrl.draft.resolvedButtons[movingId];
        final startRect = _editCtrl.settlingStartRect;
        final endRect = _editCtrl.settlingEndRect;
        final layoutCfg =
            mode == CustomizationInteractionMode.movingWidget ||
                mode == CustomizationInteractionMode.settlingMovedWidget
            ? _editCtrl.previewLayoutCfg
            : _editCtrl.draft;

        return Stack(
          children: [
            Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: SizedBox(
                      key: widget.canvasKey,
                      child: ControlCanvas(
                        layoutCfg: layoutCfg,
                        isEditing: true,
                        activeStateFor: (_) => ControlState.idle,
                        isDisabled: (_) => true,
                        onCommand: (_, __) {},
                        onMoveStart: (id) => _editCtrl.beginMove(id),
                        onMoveUpdate: (id, offset, size) =>
                            _editCtrl.updateMovePreview(
                              globalOffset: offset,
                              previewSize: size,
                            ),
                        onMoveDrop: (id, wasAccepted, offset, size) {
                          if (wasAccepted) return;
                          _editCtrl.handleMoveDrop(
                            globalDropOffset: offset,
                            previewSize: size,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (mode == CustomizationInteractionMode.movingWidget)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PlacementCancelBar(),
              ),
            if (mode == CustomizationInteractionMode.settlingMovedWidget &&
                movingConfig != null &&
                startRect != null &&
                endRect != null)
              SettlingPreviewOverlay(
                config: movingConfig,
                previewSize: endRect.size,
                startRect: startRect,
                endRect: endRect,
                onSettled: _editCtrl.commitMovedPlacement,
              ),
          ],
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Offset _cellCenter(Rect canvasRect, int col, int row) {
    final cellW = canvasRect.width / ButtonConfig.controlGridColumns;
    final cellH = canvasRect.height / ButtonConfig.controlGridRows;
    return Offset(
      canvasRect.left + (col + 0.5) * cellW,
      canvasRect.top + (row + 0.5) * cellH,
    );
  }

  Future<(LayoutEditController editCtrl, GlobalKey canvasKey)> pumpHost(
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final layoutSettings = LayoutSettingsController();
    final craneController = CraneController();
    final editCtrl = LayoutEditController(
      layoutSettings: layoutSettings,
      craneController: craneController,
    );
    await editCtrl.enter();

    // First addButton call lands at slot 0 -> (0, 0); the second lands at
    // the next free slot -> (1, 0) — buildButtonAdd's deterministic
    // first-free-slot-in-reading-order behavior on an empty grid.
    editCtrl.addButton(
      const ButtonConfig(
        id: 'occupant',
        type: ButtonType.pushButton,
        plcMapping: PlcOutputVariant.df1,
        label: 'Occupant',
      ),
    );
    editCtrl.addButton(
      const ButtonConfig(
        id: 'mover',
        type: ButtonType.pushButton,
        plcMapping: PlcOutputVariant.df2,
        label: 'Mover',
      ),
    );
    expect(editCtrl.draft.resolvedButtons['occupant']!.gridX, 0);
    expect(editCtrl.draft.resolvedButtons['occupant']!.gridY, 0);
    expect(editCtrl.draft.resolvedButtons['mover']!.gridX, 1);
    expect(editCtrl.draft.resolvedButtons['mover']!.gridY, 0);

    final canvasKey = GlobalKey();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CraneController>.value(value: craneController),
          ChangeNotifierProvider<LayoutSettingsController>.value(
            value: layoutSettings,
          ),
          ChangeNotifierProvider<LayoutEditController>.value(value: editCtrl),
        ],
        child: MaterialApp(home: _FakeControlHost(canvasKey: canvasKey)),
      ),
    );
    await tester.pumpAndSettle();
    return (editCtrl, canvasKey);
  }

  /// Long-presses 'mover' (seeded at grid cell (1, 0)) and carries it to
  /// ([targetCol], [targetRow]), stopping once the drag is fully attached to
  /// the finger and hovering the target — WITHOUT releasing, so callers can
  /// assert on the live preview before deciding to release or cancel.
  Future<TestGesture> liftAndCarryTo(
    WidgetTester tester, {
    required GlobalKey canvasKey,
    required int targetCol,
    required int targetRow,
  }) async {
    final canvasRect = tester.getRect(find.byKey(canvasKey));
    final origin = _cellCenter(canvasRect, 1, 0);

    final gesture = await tester.startGesture(origin);
    // Long-press delay (400ms, see _kMoveLongPressDelay in control_canvas.dart)
    // plus margin — unlike the catalogue flow, a canvas move has no separate
    // lifting-equivalent stage, so interactionMode is already movingWidget
    // once the delay clears.
    await tester.pump(const Duration(milliseconds: 500));

    final target = _cellCenter(canvasRect, targetCol, targetRow);
    await gesture.moveTo(target);
    await tester.pump();
    return gesture;
  }

  testWidgets(
    'long-press-drag moves an existing widget to an empty cell, preserving '
    'its id/config/mappings exactly, and settles into place on release',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);
      final originalMover = editCtrl.draft.resolvedButtons['mover']!;

      final gesture = await liftAndCarryTo(
        tester,
        canvasKey: canvasKey,
        targetCol: 1,
        targetRow: 2,
      );
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {
          /* already released */
        }
      });

      expect(editCtrl.interactionMode, CustomizationInteractionMode.movingWidget);
      expect(editCtrl.movingButtonId, 'mover');

      // Mid-carry: the draft is completely untouched, and the moved widget's
      // origin cell reads as vacant in the live preview (attached to the
      // finger, not rendered through the grid).
      expect(editCtrl.draft.resolvedButtons['mover'], originalMover);
      expect(editCtrl.previewLayoutCfg.resolvedButtons.containsKey('mover'), isFalse);
      expect(editCtrl.previewLayoutCfg.resolvedButtons['occupant']!.gridX, 0);
      expect(editCtrl.previewLayoutCfg.resolvedButtons['occupant']!.gridY, 0);

      await gesture.up();
      await tester.pump();
      expect(
        editCtrl.interactionMode,
        CustomizationInteractionMode.settlingMovedWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);

      final buttons = editCtrl.draft.resolvedButtons;
      expect(buttons, hasLength(2), reason: 'move must never create a new widget');
      final movedAfter = buttons['mover']!;
      expect(movedAfter.gridX, 1);
      expect(movedAfter.gridY, 2);
      expect(
        movedAfter,
        originalMover.copyWith(
          gridX: 1,
          gridY: 2,
          slotIndex: 2 * ButtonConfig.controlGridColumns + 1,
        ),
        reason:
            'id/type/plcMapping/label/style/mappings must all be preserved '
            'exactly — only the grid position may change',
      );
      // Untouched occupant proves this was a real move, not add+delete.
      expect(buttons['occupant']!.gridX, 0);
      expect(buttons['occupant']!.gridY, 0);
    },
  );

  testWidgets(
    'moving a widget onto an occupied cell reflows the occupant to make '
    'room, mirroring catalogue placement, and commits both on release',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);

      final gesture = await liftAndCarryTo(
        tester,
        canvasKey: canvasKey,
        targetCol: 0,
        targetRow: 0,
      );
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {
          /* already released */
        }
      });

      // Live preview: the occupant must be predicted to relocate, purely as
      // a prediction — nothing committed to the draft yet.
      final previewOccupant =
          editCtrl.previewLayoutCfg.resolvedButtons['occupant']!;
      expect(
        previewOccupant.gridX == 0 && previewOccupant.gridY == 0,
        isFalse,
        reason:
            'occupant must be predicted to move out of the drop cell while '
            'the dragged widget is still being carried',
      );
      expect(editCtrl.draft.resolvedButtons['occupant']!.gridX, 0);
      expect(editCtrl.draft.resolvedButtons['occupant']!.gridY, 0);

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);

      final buttons = editCtrl.draft.resolvedButtons;
      expect(buttons, hasLength(2));
      expect(buttons['mover']!.gridX, 0);
      expect(buttons['mover']!.gridY, 0);
      final occupantAfter = buttons['occupant']!;
      expect(occupantAfter.gridX == 0 && occupantAfter.gridY == 0, isFalse);
      expect(occupantAfter, previewOccupant);
    },
  );

  testWidgets(
    'dropping on the Cancel bar restores the dragged widget and the '
    'displaced occupant to their exact original positions',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);
      final originalMover = editCtrl.draft.resolvedButtons['mover']!;
      final originalOccupant = editCtrl.draft.resolvedButtons['occupant']!;

      final gesture = await liftAndCarryTo(
        tester,
        canvasKey: canvasKey,
        targetCol: 0,
        targetRow: 0,
      );
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {
          /* already released */
        }
      });

      // Confirm the preview really did predict a displacement before
      // cancelling — otherwise "restores exactly" would be a vacuous pass.
      final previewOccupant =
          editCtrl.previewLayoutCfg.resolvedButtons['occupant']!;
      expect(previewOccupant.gridX == 0 && previewOccupant.gridY == 0, isFalse);

      final cancelBarCenter = tester.getCenter(find.byType(DragTarget<Object>));
      await gesture.moveTo(cancelBarCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
      expect(editCtrl.movingButtonId, isNull);
      final buttons = editCtrl.draft.resolvedButtons;
      expect(buttons, hasLength(2));
      expect(buttons['mover'], originalMover);
      expect(buttons['occupant'], originalOccupant);
      expect(editCtrl.previewLayoutCfg, editCtrl.draft);
    },
  );

  testWidgets(
    'a locked widget refuses to start a move, leaving interactionMode and '
    'the draft untouched',
    (tester) async {
      final (editCtrl, _) = await pumpHost(tester);
      final beforeLocking = editCtrl.draft;

      editCtrl.updateButton('mover', (b) => b.copyWith(locked: true));
      expect(editCtrl.draft.resolvedButtons['mover']!.locked, isTrue);

      editCtrl.beginMove('mover');

      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
      expect(editCtrl.movingButtonId, isNull);
      expect(editCtrl.draft, isNot(beforeLocking));
      expect(editCtrl.draft.resolvedButtons['mover']!.locked, isTrue);
      expect(editCtrl.draft.resolvedButtons['mover']!.gridX, 1);
      expect(editCtrl.draft.resolvedButtons['mover']!.gridY, 0);
    },
  );
}
