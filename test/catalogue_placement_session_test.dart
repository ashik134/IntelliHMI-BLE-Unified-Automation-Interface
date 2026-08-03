import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalog_preview_stage.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalogue_overlay_host.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/placement_cancel_bar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/settling_preview.dart';

// ─────────────────────────────────────────────────────────────────────────────
// _FakeControlHost
//
// Reproduces exactly the placement-relevant plumbing of Plc14ControlScreen /
// Plc38ControlScreen (PlacementSurface registration + the
// CatalogueOverlayHost/PlacementCancelBar/SettlingPreviewOverlay stack)
// without the BLE/PLC chrome that's irrelevant to the catalogue
// carry-and-drop mechanism this file exercises. Kept in lockstep with the
// real screens' Stack so a pass here means the real mechanism works, not
// just this stand-in — in particular this uses the REAL CatalogueOverlayHost
// (not a re-implementation), since the whole point of this file is to prove
// the catalogue no longer needs to be pushed/popped as its own Navigator
// route for a long-press-carry to survive it (see CatalogueOverlayHost's
// doc comment for why that distinction is load-bearing, not stylistic).
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

  /// Drives one full long-press -> lift -> carry -> release -> settle
  /// session for the catalogue entry at [catalogIndex], releasing over grid
  /// cell ([targetCol], [targetRow]). Asserts every intermediate invariant
  /// the spec calls out (no placement before release, no placement while
  /// carrying) in addition to the final landing cell.
  Future<void> runPlacementSession(
    WidgetTester tester, {
    required LayoutEditController editCtrl,
    required GlobalKey canvasKey,
    required int catalogIndex,
    required int targetCol,
    required int targetRow,
  }) async {
    // Captured up front so "nothing placed yet" checks below are relative to
    // whatever earlier sessions already (correctly) committed, not an
    // assumption that the draft starts empty — this helper is also used for
    // a SECOND widget on an already-populated draft.
    int placedCount() =>
        editCtrl.draft.resolvedButtons.values.where((b) => b.role == null).length;
    final countBefore = placedCount();

    await tester.tap(find.text('Open Catalogue'));
    await tester.pumpAndSettle();
    expect(
      editCtrl.interactionMode,
      CustomizationInteractionMode.browsingCatalogue,
    );

    final entry = kWidgetCatalog[catalogIndex];
    final (colSpan, rowSpan) = entry.gridSize;
    expect(
      (colSpan, rowSpan),
      (1, 1),
      reason: 'test picks a 1x1 catalogue entry for a precise target cell',
    );

    // Card index N isn't guaranteed to already be laid out within the
    // default test viewport (the catalogue is a lazy CustomScrollView) —
    // scroll it into view first so getCenter() below is never computed from
    // a stale/off-screen rect.
    final cardFinder = find.byType(CatalogPreviewStage).at(catalogIndex);
    await tester.ensureVisible(cardFinder);
    await tester.pumpAndSettle();
    final cardCenter = tester.getCenter(cardFinder);

    final gesture = await tester.startGesture(cardCenter);
    addTearDown(() async {
      // Best-effort: release any gesture a failed expectation left mid-air so
      // later tests in this file don't inherit a stuck pointer.
      try {
        await gesture.up();
      } catch (_) {
        /* already released */
      }
    });

    // Long-press delay (400ms) not yet elapsed: nothing should have moved.
    await tester.pump(const Duration(milliseconds: 200));
    expect(editCtrl.interactionMode, CustomizationInteractionMode.browsingCatalogue);

    // Clear the long-press delay: the preview should start LIFTING only —
    // never place anything.
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      editCtrl.interactionMode,
      CustomizationInteractionMode.liftingCatalogueWidget,
      reason: 'long press should only lift the preview off its card',
    );
    expect(
      placedCount(),
      countBefore,
      reason: 'must not auto-place on long press',
    );

    // Clear the lift animation: the catalogue overlay should have slid away
    // (see CatalogueOverlayHost), the preview is now attached to the finger
    // over the control screen — and CRITICALLY, still nothing placed. This
    // is the exact instant a Navigator.pop()-based reveal used to silently
    // cancel the drag (see CatalogueOverlayHost's doc comment) and jump
    // straight to settlingWidget without any carry ever happening.
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      editCtrl.interactionMode,
      CustomizationInteractionMode.placingWidget,
      reason:
          'must still be attached to the finger right after the lift '
          'completes — this is exactly where a route-pop-based reveal used '
          'to cancel the drag out from under the operator',
    );
    expect(
      placedCount(),
      countBefore,
      reason: 'must still not be placed while merely attached to the finger',
    );

    // Carry it across the canvas toward the target cell — must not commit.
    final canvasRect = tester.getRect(find.byKey(canvasKey));
    final cellW = canvasRect.width / ButtonConfig.controlGridColumns;
    final cellH = canvasRect.height / ButtonConfig.controlGridRows;
    final targetCenter = Offset(
      canvasRect.left + (targetCol + 0.5) * cellW,
      canvasRect.top + (targetRow + 0.5) * cellH,
    );

    // Move in a couple of steps, like a real carry, checking nothing commits
    // mid-flight.
    final midPoint = Offset.lerp(cardCenter, targetCenter, 0.5)!;
    await gesture.moveTo(midPoint);
    await tester.pump();
    expect(editCtrl.interactionMode, CustomizationInteractionMode.placingWidget);
    expect(
      placedCount(),
      countBefore,
      reason: 'must not insert into the grid while still carrying',
    );

    await gesture.moveTo(targetCenter);
    await tester.pump();
    expect(editCtrl.interactionMode, CustomizationInteractionMode.placingWidget);
    expect(placedCount(), countBefore);

    // Release: this is the ONLY moment placement may be decided.
    await gesture.up();
    await tester.pump();
    expect(editCtrl.interactionMode, CustomizationInteractionMode.settlingWidget);

    // Clear the settle animation: hand-off to the real grid widget.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(editCtrl.interactionMode, CustomizationInteractionMode.editing);
    expect(
      placedCount(),
      countBefore + 1,
      reason: 'exactly one new widget should have been committed by now',
    );
  }

  testWidgets(
    'long-press catalogue placement lands at the release cell, not the first available slot',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);

      // First widget: release far from the top-left corner (bottom-right
      // cell of the 2x3 grid). The old "first available slot" behavior
      // would always land this at (0, 0) regardless of where it's released.
      await runPlacementSession(
        tester,
        editCtrl: editCtrl,
        canvasKey: canvasKey,
        catalogIndex: 0,
        targetCol: ButtonConfig.controlGridColumns - 1,
        targetRow: ButtonConfig.controlGridRows - 1,
      );

      final firstPlaced = editCtrl.draft.resolvedButtons.values
          .where((b) => b.role == null)
          .toList();
      expect(firstPlaced, hasLength(1));
      expect(
        firstPlaced.single.gridX,
        ButtonConfig.controlGridColumns - 1,
        reason: 'must land in the column it was released over',
      );
      expect(
        firstPlaced.single.gridY,
        ButtonConfig.controlGridRows - 1,
        reason: 'must land in the row it was released over',
      );

      // Second widget: release at the TOP-RIGHT cell. The old "next free
      // row" behavior would stack this directly under/after the first
      // widget regardless of release point. (Index 3, not 1: kWidgetCatalog
      // is ordered by section, and index 1 is the 5-Step Bidirectional
      // Slider, a 2x1 widget — index 3, the Latching Push Button, is the
      // next 1x1 entry.)
      await runPlacementSession(
        tester,
        editCtrl: editCtrl,
        canvasKey: canvasKey,
        catalogIndex: 3,
        targetCol: ButtonConfig.controlGridColumns - 1,
        targetRow: 0,
      );

      final allPlaced = editCtrl.draft.resolvedButtons.values
          .where((b) => b.role == null)
          .toList();
      expect(allPlaced, hasLength(2));
      final secondPlaced = allPlaced.firstWhere(
        (b) => !identical(b, firstPlaced.single),
      );
      expect(
        secondPlaced.gridX,
        ButtonConfig.controlGridColumns - 1,
        reason: 'second widget must also land at its own release cell',
      );
      expect(
        secondPlaced.gridY,
        0,
        reason:
            'second widget must land where released, not "next free row" '
            'after the first',
      );
    },
  );

  testWidgets(
    'releasing over the Cancel bar during the initial lift returns to catalogue browsing without placing anything',
    (tester) async {
      final (editCtrl, canvasKey) = await pumpHost(tester);

      await tester.tap(find.text('Open Catalogue'));
      await tester.pumpAndSettle();

      final cardCenter = tester.getCenter(find.byType(CatalogPreviewStage).first);
      final gesture = await tester.startGesture(cardCenter);
      addTearDown(() async {
        try {
          await gesture.up();
        } catch (_) {
          /* already released */
        }
      });

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        editCtrl.interactionMode,
        CustomizationInteractionMode.liftingCatalogueWidget,
      );

      await gesture.up();
      await tester.pump();

      expect(
        editCtrl.interactionMode,
        CustomizationInteractionMode.browsingCatalogue,
        reason:
            'releasing before the lift animation even finishes should '
            'return to browsing the catalogue, not place anything',
      );
      expect(
        editCtrl.draft.resolvedButtons.values.where((b) => b.role == null),
        isEmpty,
      );
    },
  );
}
