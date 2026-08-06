import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/models/widget_catalog.dart';

import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/catalogue_overlay_host.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_canvas.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/customization_toolbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/edit_mode_backdrop.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/placement_cancel_bar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/settling_preview.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/widget_properties_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rebuild-scope note
// ─────────────────────────────────────────────────────────────────────────────

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with WidgetsBindingObserver {
  CraneController? _craneController;
  LayoutEditController? _editCtrl;

  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

  final Map<String, ControlState> _localActive = {};

  // ── Widget-placement drop geometry ───────────────────────────────────────
  //
  // _canvasKey locates the grid's on-screen rectangle (see _canvasRect) and
  // _canvasPageController is handed to ControlCanvas so a drop landing on a
  // different page can be animated there — both registered with
  // LayoutEditController as a PlacementSurface (see registerPlacementSurface's
  // doc comment) so handleCatalogueDrop, which has no BuildContext of its
  // own, can convert a release point into a grid position.
  final GlobalKey _canvasKey = GlobalKey();
  final PageController _canvasPageController = PageController();

  void _resetLocalButtonStates() {
    if (_localActive.isEmpty) return;
    setState(_localActive.clear);
  }

  Rect _canvasRect() {
    final box = _canvasKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  int _currentCanvasPageIndex() {
    if (!_canvasPageController.hasClients) return 0;
    return _canvasPageController.page?.round() ?? 0;
  }

  void _navigateCanvasToPage(int pageIndex) {
    if (!_canvasPageController.hasClients) return;
    _canvasPageController.animateToPage(
      pageIndex,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final editCtrl = context.read<LayoutEditController>();
    _editCtrl = editCtrl;
    editCtrl.registerPlacementSurface(
      this,
      PlacementSurface(
        canvasRect: _canvasRect,
        currentPageIndex: _currentCanvasPageIndex,
        navigateToPage: _navigateCanvasToPage,
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<CraneController>();
      _craneController = controller;
      controller.addListener(_onControllerChange);
    });
  }

  @override
  void dispose() {
    FocusManager.instance.primaryFocus?.unfocus();
    _editCtrl?.unregisterPlacementSurface(this);
    _craneController?.removeListener(_onControllerChange);
    WidgetsBinding.instance.removeObserver(this);
    _canvasPageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancelActivePlacement();
  }

  void _cancelActivePlacement() {
    if (!mounted) return;
    context.read<LayoutEditController>().cancelCataloguePlacement();
  }

  void _dismissResetDialogIfVisible() {
    if (!mounted || _resetDialogContext == null || _isDismissingResetDialog) {
      return;
    }
    _isDismissingResetDialog = true;
    FocusManager.instance.primaryFocus?.unfocus();
    final dialogContext = _resetDialogContext;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.of(dialogContext).pop(false);
      return;
    }

    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) {
      rootNavigator.pop(false);
      return;
    }
    _isDismissingResetDialog = false;
  }

  void _onControllerChange() {
    final controller = _craneController;
    if (!mounted || controller == null) return;
    if (controller.currentScreen != AppScreen.control ||
        controller.isDisconnected) {
      _dismissResetDialogIfVisible();
      _resetLocalButtonStates();
      _cancelActivePlacement();
    }
    if (controller.isDisconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Disconnected from PLC'),
          backgroundColor: AppColors.eStopColor,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ── E-Stop ──────────────────────────────────────────────────────────────────

  Future<void> _onEStopTap() async {
    final controller = context.read<CraneController>();
    await controller.triggerEStop();
    Vibration.vibrate(duration: 600, amplitude: 255);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'EMERGENCY STOP ACTIVATED',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          backgroundColor: AppColors.eStopColor,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _onResetEStopTap() async {
    final controller = context.read<CraneController>();

    if (context.read<LayoutEditController>().isEditing ||
        controller.currentScreen != AppScreen.control ||
        !controller.isConnected) {
      return;
    }
    if (mounted) {
      await controller.resetEStop();
      Vibration.vibrate(duration: 100);
    }
  }

  Future<void> _onBackAttempted(bool didPop, Object? result) async {
    if (didPop || _isBackNavigating) return;

    final editCtrl = context.read<LayoutEditController>();
    switch (editCtrl.interactionMode) {
      case CustomizationInteractionMode.browsingCatalogue:
        // The catalogue is a sliding overlay within this same route (see
        // CatalogueOverlayHost), not a pushed route of its own — back must
        // close it locally instead of falling through to the full
        // exit-confirmation flow below.
        editCtrl.closeCatalogueBrowsing();
        return;
      case CustomizationInteractionMode.liftingCatalogueWidget:
      case CustomizationInteractionMode.placingWidget:
        // Mid-carry: there's no "release" equivalent for a back press, so
        // treat it as an explicit cancel, same as the Cancel bar.
        editCtrl.cancelCataloguePlacement();
        return;
      case CustomizationInteractionMode.settlingWidget:
        // Brief and deliberately non-cancelable (see
        // LayoutEditController.commitSettledPlacement's doc comment) — a
        // back press here is simply ignored until it settles on its own.
        return;
      case CustomizationInteractionMode.editing:
        break;
    }

    _isBackNavigating = true;
    try {
      final controller = context.read<CraneController>();

      await controller.stopAllMotion();

      if (!mounted) return;
      final confirmed = await showControlExitDialog(context);
      if (!mounted) return;

      if (confirmed) {
        await controller.disconnect();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Exit canceled. Controls reactivated.'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) _isBackNavigating = false;
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Selector<CraneController, PlcType>(
      selector: (_, controller) => controller.connectedPlcType,
      builder: (context, plcType, _) {
        return Selector2<
          LayoutEditController,
          LayoutSettingsController,
          _LayoutShape
        >(
          selector: (_, editCtrl, layoutCtrl) => _LayoutShape(
            isEditing: editCtrl.isEditing,
            interactionMode: editCtrl.interactionMode,
            layoutCfg: editCtrl.isEditing
                ? (editCtrl.interactionMode ==
                              CustomizationInteractionMode.placingWidget ||
                          editCtrl.interactionMode ==
                              CustomizationInteractionMode.settlingWidget
                      ? editCtrl.previewLayoutCfg
                      : editCtrl.draft)
                : layoutCtrl.configFor(LayoutBucket.forPlcType(plcType)),
            pendingCatalogueEntry: editCtrl.pendingCatalogueEntry,
            settlingStartRect: editCtrl.settlingStartRect,
            settlingEndRect: editCtrl.settlingEndRect,
          ),
          builder: (context, shape, _) => _buildScaffold(
            context,
            shape.isEditing,
            shape.interactionMode,
            shape.layoutCfg,
            shape.pendingCatalogueEntry,
            shape.settlingStartRect,
            shape.settlingEndRect,
          ),
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    bool isEditing,
    CustomizationInteractionMode interactionMode,
    ControlLayoutConfig layoutCfg,
    CatalogEntry? pendingCatalogueEntry,
    Rect? settlingStartRect,
    Rect? settlingEndRect,
  ) {
    final labels = layoutCfg.labelConfig;
    final sizing = layoutCfg.sizeConfig;
    final arrangement = layoutCfg.arrangementConfig;
    final metrics = ControlLayoutMetrics.compute(
      MediaQuery.of(context).size.height -
          kToolbarHeight -
          MediaQuery.of(context).padding.top -
          MediaQuery.of(context).padding.bottom,
      baseEstopHeight: sizing.resolvedEstopHeight,
      preferShowSensor: arrangement.showSensorRow,
      preferShowLEDs: arrangement.showLiveLEDs,
    );

    return Stack(
      children: [
        PopScope(
          canPop: !isEditing,
          onPopInvokedWithResult: _onBackAttempted,
          child: Scaffold(
            backgroundColor: AppColors.darkBg,
            resizeToAvoidBottomInset: false,
            appBar: _ControlAppBar(labels: labels, isEditing: isEditing),
            body: SafeArea(
              maintainBottomViewPadding: true,
              child: Stack(
                children: [
                  Padding(
                    padding: metrics.bodyPadding,
                    child: Column(
                      children: [
                        _SafetyPanelSection(
                          compact: metrics.isCompact,
                          height: metrics.estopHeight,
                          width: sizing.resolvedEstopWidthOrFill,
                          instructionLabel: labels.estopSwipeInstruction,
                          resetLabel: labels.resetEstopLabel,
                          isEditing: isEditing,
                          onEStopTap: _onEStopTap,
                          onResetActivated: _onResetEStopTap,
                        ),
                        SizedBox(height: metrics.itemSpacing),
                        if (metrics.showSensorRow) ...[
                          const _SensorSection(),
                          SizedBox(height: metrics.itemSpacing),
                        ],
                        if (metrics.showLEDs) ...[
                          const _LiveLedSection(),
                          SizedBox(height: metrics.itemSpacing),
                        ],
                        Expanded(
                          child: RepaintBoundary(
                            key: _canvasKey,
                            child: _CanvasSection(
                              layoutCfg: layoutCfg,
                              isEditing: isEditing,
                              localActive: _localActive,
                              onLocalActiveChanged: (id, state) =>
                                  setState(() => _localActive[id] = state),
                              pageController: _canvasPageController,
                            ),
                          ),
                        ),
                        SizedBox(height: metrics.itemSpacing),
                        BottomActionsRecede(
                          recede: isEditing,
                          child: const _StatusChipSection(),
                        ),
                        SizedBox(height: metrics.itemSpacing),
                      ],
                    ),
                  ),
                  if (isEditing)
                    const Positioned.fill(child: EditModeBackdrop()),
                ],
              ),
            ),
          ),
        ),
        EditModeToolbarHost(
          isEditing:
              isEditing &&
              interactionMode == CustomizationInteractionMode.editing,
        ),
        if (isEditing) CatalogueOverlayHost(interactionMode: interactionMode),
        if (interactionMode == CustomizationInteractionMode.placingWidget)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PlacementCancelBar(),
          ),
        if (interactionMode == CustomizationInteractionMode.settlingWidget &&
            pendingCatalogueEntry != null &&
            settlingStartRect != null &&
            settlingEndRect != null)
          SettlingPreviewOverlay(
            entry: pendingCatalogueEntry,
            startRect: settlingStartRect,
            endRect: settlingEndRect,
            onSettled: () =>
                context.read<LayoutEditController>().commitSettledPlacement(),
          ),
        const _PlacementErrorListener(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PlacementErrorListener
//
// A one-shot bridge from LayoutEditController.placementError (a plain field,
// not a Stream — see its doc comment) to a SnackBar: watches the value and,
// if non-null, clears it and shows the message on the very next frame. Never
// builds anything visible itself.
// ─────────────────────────────────────────────────────────────────────────────

class _PlacementErrorListener extends StatelessWidget {
  const _PlacementErrorListener();

  @override
  Widget build(BuildContext context) {
    final error = context.select<LayoutEditController, String?>(
      (c) => c.placementError,
    );
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        context.read<LayoutEditController>().clearPlacementError();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: AppColors.eStopColor),
        );
      });
    }
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LayoutShape
// ─────────────────────────────────────────────────────────────────────────────

class _LayoutShape {
  const _LayoutShape({
    required this.isEditing,
    required this.interactionMode,
    required this.layoutCfg,
    required this.pendingCatalogueEntry,
    required this.settlingStartRect,
    required this.settlingEndRect,
  });

  final bool isEditing;
  final CustomizationInteractionMode interactionMode;
  final ControlLayoutConfig layoutCfg;
  final CatalogEntry? pendingCatalogueEntry;
  final Rect? settlingStartRect;
  final Rect? settlingEndRect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutShape &&
          other.isEditing == isEditing &&
          other.interactionMode == interactionMode &&
          other.layoutCfg == layoutCfg &&
          other.pendingCatalogueEntry == pendingCatalogueEntry &&
          other.settlingStartRect == settlingStartRect &&
          other.settlingEndRect == settlingEndRect;

  @override
  int get hashCode => Object.hash(
    isEditing,
    interactionMode,
    layoutCfg,
    pendingCatalogueEntry,
    settlingStartRect,
    settlingEndRect,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ControlAppBar
// ─────────────────────────────────────────────────────────────────────────────

class _ControlAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ControlAppBar({required this.labels, required this.isEditing});

  final ControlLabelConfig labels;
  final bool isEditing;

  @override
  Size get preferredSize =>
      const Size.fromHeight(kToolbarHeight + ControlModeAppBarFooter.height);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actionsPadding: const EdgeInsets.only(right: 8),
      automaticallyImplyLeading: false,
      backgroundColor: isEditing
          ? AppColors.appBarEditingBg
          : AppColors.appBarBg,
      flexibleSpace: const ControlAppBarGlow(),
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      title: isEditing
          ? const EditModeAppBarTitle()
          : _DeviceTitle(labels: labels),
      actions: [
        if (!isEditing)
          IconButton(
            icon: const Icon(
              Icons.dashboard_customize_rounded,
              size: 20,
              color: AppColors.darkTextMuted,
            ),
            tooltip: 'Customize Layout',
            onPressed: () => context.read<LayoutEditController>().enter(),
          ),
        if (isEditing) const EditModeUndoRedoActions(),
        const _DisconnectButton(),
      ],
      bottom: ControlModeAppBarFooter(isEditing: isEditing),
    );
  }
}

class _DeviceTitle extends StatelessWidget {
  const _DeviceTitle({required this.labels});

  final ControlLabelConfig labels;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    final screenTitle = labels.screenTitle.isNotEmpty
        ? labels.screenTitle
        : (controller.connectedDeviceName ?? BLEConstants.deviceName);
    return DeviceInfoAppBarTitle(
      deviceName: screenTitle,
      plcType: controller.connectedPlcType,
      rssi: controller.connectedDeviceRssi,
    );
  }
}

class _DisconnectButton extends StatelessWidget {
  const _DisconnectButton();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    return IconButton.filledTonal(
      onPressed: controller.disconnect,
      tooltip: 'Disconnect',
      style: IconButton.styleFrom(
        foregroundColor: AppColors.error,
        backgroundColor: AppColors.error.withValues(alpha: 0.10),
        hoverColor: AppColors.error.withValues(alpha: 0.15),
        highlightColor: AppColors.error.withValues(alpha: 0.20),
        minimumSize: const Size(42, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.22)),
        ),
      ),
      icon: const Icon(Icons.power_settings_new_rounded, size: 21),
    );
  }
}

class _SafetyPanelSection extends StatelessWidget {
  const _SafetyPanelSection({
    required this.compact,
    required this.height,
    required this.width,
    required this.instructionLabel,
    required this.resetLabel,
    required this.isEditing,
    required this.onEStopTap,
    required this.onResetActivated,
  });

  final bool compact;
  final double height;
  final double? width;
  final String instructionLabel;
  final String resetLabel;

  final bool isEditing;
  final Future<void> Function() onEStopTap;
  final Future<void> Function() onResetActivated;

  @override
  Widget build(BuildContext context) {
    final estopLatched = context.select<CraneController, bool>(
      (c) => c.estopLatched,
    );
    return RepaintBoundary(
      child: SafetyActionPanel(
        estopLatched: estopLatched,
        compact: compact,
        height: height,
        width: width,
        instructionLabel: instructionLabel,
        resetLabel: resetLabel,
        resetEnabled: !isEditing,
        onEStopTap: onEStopTap,
        onResetActivated: onResetActivated,
      ),
    );
  }
}

class _SensorSection extends StatelessWidget {
  const _SensorSection();

  @override
  Widget build(BuildContext context) {
    final a1 = context.select<CraneController, int>((c) => c.a1);
    final a2 = context.select<CraneController, int>((c) => c.a2);
    return RepaintBoundary(
      child: SensorRow(a1: a1, a2: a2),
    );
  }
}

// PLC14/PLC21 expose the first 4 wire fields (DF1/E-STOP..DF4).
const List<PlcOutputVariant> _ledVariants = [
  PlcOutputVariant.df1,
  PlcOutputVariant.df2,
  PlcOutputVariant.df3,
  PlcOutputVariant.df4,
];

class _LiveLedRowValues {
  const _LiveLedRowValues(this.states);

  final List<bool> states;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _LiveLedRowValues || other.states.length != states.length) {
      return false;
    }
    for (var i = 0; i < states.length; i++) {
      if (other.states[i] != states[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(states);
}

class _LiveLedSection extends StatelessWidget {
  const _LiveLedSection();

  @override
  Widget build(BuildContext context) {
    final values = context.select<CraneController, _LiveLedRowValues>(
      (c) => _LiveLedRowValues([
        for (final variant in _ledVariants) c.ledStateFor(variant),
      ]),
    );
    return RepaintBoundary(
      child: LiveLedRow(
        leds: [
          for (var i = 0; i < _ledVariants.length; i++)
            LedSpec(
              label: _ledVariants[i].isEmergencyStop
                  ? 'ESTOP'
                  : _ledVariants[i].storageKey,
              active: values.states[i],
              color: _ledVariants[i].isEmergencyStop
                  ? AppColors.eStopColor
                  : AppColors.accent,
              inactiveColor: _ledVariants[i].isEmergencyStop
                  ? AppColors.darkSuccess
                  : null,
              pulseWhenInactive: _ledVariants[i].isEmergencyStop,
            ),
        ],
      ),
    );
  }
}

class _StatusChipSection extends StatelessWidget {
  const _StatusChipSection();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    return RepaintBoundary(
      child: StatusBarChip(
        color: controller.estopLatched
            ? AppColors.eStopColor
            : controller.activeCommand.isIdle
            ? AppColors.idleColor
            : AppColors.accent,
        label: controller.statusLabel,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CanvasSection
// ─────────────────────────────────────────────────────────────────────────────

class _GridGateValues {
  const _GridGateValues(this.estopLatched, this.isConnected);

  final bool estopLatched;
  final bool isConnected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _GridGateValues &&
          other.estopLatched == estopLatched &&
          other.isConnected == isConnected;

  @override
  int get hashCode => Object.hash(estopLatched, isConnected);
}

class _CanvasSection extends StatelessWidget {
  const _CanvasSection({
    required this.layoutCfg,
    required this.isEditing,
    required this.localActive,
    required this.onLocalActiveChanged,
    required this.pageController,
  });

  final ControlLayoutConfig layoutCfg;
  final bool isEditing;
  final Map<String, ControlState> localActive;
  final void Function(String id, ControlState state) onLocalActiveChanged;

  /// Externally-owned so a widget-placement drop can animate the grid to a
  /// different page while its floating preview settles (see
  /// PlacementSurface / ControlCanvas.pageController's doc comments).
  final PageController pageController;

  bool _isMutuallyExcluded(ButtonConfig config) {
    if (config.type == ButtonType.bidirectionalSlider5Step ||
        config.type == ButtonType.bidirectionalSlider3Step) {
      return false;
    }
    for (final excludedId in config.mutualExclusion.excludedButtonIds) {
      if ((localActive[excludedId] ?? ControlState.idle) != ControlState.idle) {
        return true;
      }
    }
    return false;
  }

  ControlState _activeStateForButton(bool estopLatched, ButtonConfig config) {
    if (estopLatched) return ControlState.idle;
    return localActive[config.id] ?? ControlState.idle;
  }

  void _onDelete(BuildContext context, String id) {
    final result = context.read<LayoutEditController>().deleteButton(id);
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message ?? 'Could not delete this widget.'),
        ),
      );
    }
  }

  void _onEdit(BuildContext context, String id) {
    showWidgetPropertiesSheet(context, id);
  }

  @override
  Widget build(BuildContext context) {
    final gate = context.select<CraneController, _GridGateValues>(
      (c) => _GridGateValues(c.estopLatched, c.isConnected),
    );
    final selectedButtonId = isEditing
        ? context.select<LayoutEditController, String?>(
            (c) => c.selectedButtonId,
          )
        : null;

    final pageTransitionStyle = isEditing
        ? context.select<LayoutEditController, CanvasPageTransitionStyle>(
            (c) => c.pageTransitionStyle,
          )
        : CanvasPageTransitionStyle.slide;

    return ControlCanvas(
      layoutCfg: layoutCfg,
      isEditing: isEditing,
      pageTransitionStyle: pageTransitionStyle,
      pageController: pageController,
      activeStateFor: (config) =>
          _activeStateForButton(gate.estopLatched, config),
      isDisabled: (config) =>
          isEditing ||
          gate.estopLatched ||
          !gate.isConnected ||
          !config.enabled ||
          (config.role == null && !config.plcMappingEnabled) ||
          _isMutuallyExcluded(config),
      onCommand: (id, state) {
        ButtonStateLog.log(
          state == ControlState.idle
              ? 'SEND_IDLE  [$id] (PLC14)'
              : 'SEND_ACTIVE [$id] -> ${state.name} (PLC14)',
        );
        onLocalActiveChanged(id, state);
        final resolved = resolveButtonCommand(
          buttonId: id,
          state: state,
          layoutCfg: layoutCfg,
        );
        context.read<CraneController>().setButtonState(
          buttonId: id,
          stateId: resolved.stateId,
          activeVariants: resolved.activeVariants,
        );
      },
      onStateIdCommand: (id, stateId) {
        final isIdle =
            stateId == MultiZoneSliderStateId.center || stateId == 'idle';
        final state = isIdle ? ControlState.idle : ControlState.level1;
        ButtonStateLog.log(
          isIdle
              ? 'SEND_IDLE  [$id] (PLC14)'
              : 'SEND_ACTIVE [$id] -> $stateId (PLC14)',
        );
        onLocalActiveChanged(id, state);
        final activeVariants =
            layoutCfg
                .resolvedButtons[id]
                ?.stateMappings[stateId]
                ?.activeVariants ??
            const <PlcOutputVariant>{};
        context.read<CraneController>().setButtonState(
          buttonId: id,
          stateId: stateId,
          activeVariants: activeVariants,
        );
      },
      onAnalogCommand: (config, value) {
        final analogConfig = resolveAnalogWireConfig(config);
        context.read<CraneController>().setAnalogButtonValue(
          buttonId: config.id,
          value: value,
          config: analogConfig,
        );
      },
      selectedButtonId: selectedButtonId,
      onSelectButton: isEditing
          ? (id) => context.read<LayoutEditController>().selectButton(id)
          : null,
      onDeleteButton: isEditing ? (id) => _onDelete(context, id) : null,
      onEditButton: isEditing ? (id) => _onEdit(context, id) : null,
    );
  }
}
