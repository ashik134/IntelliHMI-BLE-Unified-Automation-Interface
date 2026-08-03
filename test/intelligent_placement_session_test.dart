import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalog_preview_stage.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalogue_overlay_host.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/placement_cancel_bar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/settling_preview.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Same minimal placement harness as catalogue_placement_session_test.dart
// (PlacementSurface registration + the real CatalogueOverlayHost/
// PlacementCancelBar/SettlingPreviewOverlay stack), reused here to drive a
// REAL long-press-drag gesture through the REAL LongPressDraggable and prove
// the intelligent-placement engine end-to-end: an existing occupant must
// visibly relocate in the live preview WHILE the finger is still down (and
// the committed draft must stay untouched until release), then either
// commit at its predicted new position or, on Cancel, revert exactly.
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
        final pendingEntry = _editCtrl.pendingCatalogueEntry;
        final startRect = _editCtrl.settlingStartRect;
        final endRect = _editCtrl.settlingEndRect;
        return Stack(
          children: [
            Scaffold(
              body: Column(
                children: [
                  ElevatedButton(
                    onPressed: _editCtrl.enterCatalogueBrowsing,
                    child: const Text('Open Catalogue'),
                  ),
                  Expanded(
                    child: Container(key: widget.canvasKey, color: Colors.black12),
                  ),
                ],
              ),
            ),
            CatalogueOverlayHost(interactionMode: mode),
            if (mode == CustomizationInteractionMode.placingWidget)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PlacementCancelBar(),
              ),
            if (mode == CustomizationInteractionMode.settlingWidget &&
                pendingEntry != null &&
                startRect != null &&
                endRect != null)
              SettlingPreviewOverlay(
                entry: pendingEntry,
                startRect: startRect,
                endRect: endRect,
                onSettled: _editCtrl.commitSettledPlacement,
              ),
          ],
        );
      },
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    // Seed an occupant sitting exactly where the new widget will be dropped,
    // so the drag has something to intelligently displace.
    editCtrl.addButton(
      const ButtonConfig(
        id: 'occupant',
        type: ButtonType.pushButton,
        plcMapping: PlcOutputVariant.df2,
        label: 'Occupant',
      ),
    );
    expect(editCtrl.draft.resolvedButtons['occupant']!.gridX, 0);
    expect(editCtrl.draft.resolvedButtons['occupant']!.gridY, 0);

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

  /// Long-presses catalogue entry 0 (a 1x1 push button — see
  /// catalogue_placement_session_test.dart's own assertion of this) and
  /// carries it to grid cell (0, 0), where 'occupant' already sits. Stops
  /// once the preview is fully attached to the finger and hovering the
  /// target, WITHOUT releasing — so callers can assert on the live preview
  /// before deciding to release or cancel.
  Future<TestGesture> liftAndCarryToOccupiedCell(
    WidgetTester tester, {
    required GlobalKey canvasKey,
  }) async {
    await tester.tap(find.text('Open Catalogue'));
    await tester.pumpAndSettle();

    final cardFinder = find.byType(CatalogPreviewStage).first;
    await tester.ensureVisible(cardFinder);
    await tester.pumpAndSettle();
    final cardCenter = tester.getCenter(cardFinder);

    final gesture = await tester.startGesture(cardCenter);
    // Clear the 400ms long-press delay, then the ~160ms lift-off animation
    // (see catalogue_placement_session_test.dart's own two-step pump of the
    // same transitions) before the preview is actually attached to the
    // finger over the control screen.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 250));

    final canvasRect = tester.getRect(find.byKey(canvasKey));
    final cellW = canvasRect.width / ButtonConfig.controlGridColumns;
    final cellH = canvasRect.height / ButtonConfig.controlGridRows;
    final targetCenter = Offset(canvasRect.left + cellW / 2, canvasRect.top + cellH / 2);

    await gesture.moveTo(targetCenter);
    await tester.pump();
    return gesture;
  }

  testWidgets(
    'existing widgets relocate live while dragging, commit on release, and '
    'the draft stays untouched until then',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);

      final gesture = await liftAndCarryToOccupiedCell(tester, canvasKey: canvasKey);
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {}
      });

      expect(editCtrl.interactionMode, CustomizationInteractionMode.placingWidget);

      // Live preview: the occupant must have relocated to make room, purely
      // as a PREDICTION — nothing committed to the draft yet.
      final previewOccupant = editCtrl.previewLayoutCfg.resolvedButtons['occupant']!;
      expect(
        previewOccupant.gridX == 0 && previewOccupant.gridY == 0,
        isFalse,
        reason: 'occupant must be predicted to move out of the drop cell '
            'while the new widget is still being carried',
      );
      final draftOccupant = editCtrl.draft.resolvedButtons['occupant']!;
      expect(
        draftOccupant.gridX,
        0,
        reason: 'the committed draft must be completely unaffected mid-drag',
      );
      expect(draftOccupant.gridY, 0);

      // Release and let the settle animation complete.
      await gesture.up();
      await tester.pump();
      expect(editCtrl.interactionMode, CustomizationInteractionMode.settlingWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);

      // Now the draft itself must reflect BOTH the new widget at (0,0) and
      // the occupant relocated to its predicted new cell.
      final buttons = editCtrl.draft.resolvedButtons;
      final occupantAfter = buttons['occupant']!;
      expect(occupantAfter.gridX == 0 && occupantAfter.gridY == 0, isFalse);
      expect(occupantAfter, previewOccupant.copyWith(id: 'occupant'));

      final placedIds = buttons.keys.where((id) => id.startsWith('placed_'));
      expect(placedIds, hasLength(1));
      final placed = buttons[placedIds.first]!;
      expect(placed.gridX, 0);
      expect(placed.gridY, 0);
      expect(placed.pageIndex, 0);
    },
  );

  testWidgets(
    'dropping on the Cancel bar restores the original layout exactly — no '
    'new widget, occupant back at its original cell',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);
      final originalOccupant = editCtrl.draft.resolvedButtons['occupant']!;

      final gesture = await liftAndCarryToOccupiedCell(tester, canvasKey: canvasKey);
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {}
      });

      // Confirm the preview really did predict a displacement before
      // cancelling — otherwise "restores the original layout" would be a
      // vacuous pass (nothing to restore).
      final previewOccupant = editCtrl.previewLayoutCfg.resolvedButtons['occupant']!;
      expect(previewOccupant.gridX == 0 && previewOccupant.gridY == 0, isFalse);

      // Carry up to the Cancel bar's actual drop target (PlacementCancelBar
      // itself is a full-width Positioned; its pill-shaped DragTarget is
      // aligned top-left within that, so target the DragTarget directly
      // rather than the wider ancestor's center).
      final cancelBarCenter = tester.getCenter(find.byType(DragTarget<CatalogEntry>));
      await gesture.moveTo(cancelBarCenter);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
      final buttons = editCtrl.draft.resolvedButtons;
      expect(buttons.keys.where((id) => id.startsWith('placed_')), isEmpty);
      expect(buttons['occupant'], originalOccupant);
      expect(editCtrl.previewLayoutCfg, editCtrl.draft);
    },
  );
}
