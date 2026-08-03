import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/canvas_page_transition_style.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/customization_interaction_mode.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';

import 'package:rev_crane_control_ops/utils/button_state_log.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_edit_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_canvas.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/customization_toolbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/edit_mode_backdrop.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/placement_cancel_bar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';

// ═══════════════════════════════════════════════════════════════
// Plc38ControlScreen
//
// Rebuild-scope note: this used to sit behind one Consumer3<CraneController,
// LayoutSettingsController, CustomizationModeController> wrapping the whole
// Scaffold body, so any notifyListeners() from any of the three — including
// a BLE analog/status notification arriving many times a second — rebuilt
// the AppBar, 10-LED row, sensor row, and status chip together. The layout
// selector below is recomputed only when the committed layout changes or the
// PLC type changes; each live-data section (LEDs, sensor row, safety panel,
// status chip) is its own small widget with its own narrow Selector, so a
// BLE notification only rebuilds the section that changed.
//
// The customization workflow is a tap-only Edit Mode (no drag/resize this
// pass — see LayoutEditController): the Customize button starts an edit
// session, ControlCanvas renders the grid with tap-to-select/delete chrome,
// and the bottom CustomizationToolbar exposes Widgets/Load Template/Save
// Layout/Layout Settings/Done.
// ═══════════════════════════════════════════════════════════════

class Plc38ControlScreen extends StatefulWidget {
  const Plc38ControlScreen({super.key});

  @override
  State<Plc38ControlScreen> createState() => _Plc38ControlScreenState();
}

class _Plc38ControlScreenState extends State<Plc38ControlScreen>
    with WidgetsBindingObserver {
  CraneController? _craneController;

  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

  // Written only by the onCommand callback below, which fires synchronously
  // from a button's own gesture handler — never from PLC status feedback.
  // See _CanvasSection._activeStateForButton's doc comment.
  final Map<String, ControlState> _localActive = {};

  void _resetLocalButtonStates() {
    if (_localActive.isEmpty) return;
    setState(_localActive.clear);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    _craneController?.removeListener(_onControllerChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // See Plc14's ControlScreen counterpart — a backgrounded app can never
    // deliver the pointer-up that would normally end an in-progress
    // catalogue placement drag, so this prevents a permanently stuck
    // floating preview once the app resumes.
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
    if (controller.currentScreen != AppScreen.plc38Control ||
        controller.isDisconnected) {
      _dismissResetDialogIfVisible();
      _resetLocalButtonStates();
      _cancelActivePlacement();
    }
    if (controller.isDisconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Disconnected from PLC38'),
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
    // isEditing is defense-in-depth: SafetyActionPanel already disables the
    // reset swipe (resetEnabled: !isEditing) while Edit Mode is active, but
    // gating here too means Reset E-Stop can never fire mid-edit even if
    // that wiring ever changes.
    if (context.read<LayoutEditController>().isEditing ||
        controller.currentScreen != AppScreen.plc38Control ||
        !controller.isConnected) {
      return;
    }
    if (mounted) {
      await controller.resetEStop();
      Vibration.vibrate(duration: 100);
    }
  }

  // Called by PopScope when the operator presses the back button or swipes.
  // canPop is false so didPop is always false; the method handles all navigation.
  Future<void> _onBackAttempted(bool didPop, Object? result) async {
    if (didPop || _isBackNavigating) return;
    _isBackNavigating = true;
    try {
      final controller = context.read<CraneController>();

      // Stop all motion on all three axes before showing the dialog so the
      // PLC never keeps moving while the operator reviews the prompt.
      await controller.stopAllMotion();

      if (!mounted) return;
      final confirmed = await showControlExitDialog(context);
      if (!mounted) return;

      if (confirmed) {
        // disconnect() sends a final idle command then drops the BLE link.
        // HMIAppShell reacts to isDisconnected and swaps in ConnectionScreen
        // automatically — no explicit Navigator call needed.
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
                ? editCtrl.draft
                : layoutCtrl.configFor(LayoutBucket.forPlcType(plcType)),
          ),
          builder: (context, shape, _) => _buildScaffold(
            context,
            shape.isEditing,
            shape.interactionMode,
            shape.layoutCfg,
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
            appBar: _Plc38AppBar(labels: labels, isEditing: isEditing),
            body: SafeArea(
              maintainBottomViewPadding: true,
              child: Stack(
                children: [
                  Padding(
                    padding: metrics.bodyPadding,
                    child: Column(
                      children: [
                        // ── E-Stop / Reset ──────────────────────────────
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

                        // ── Sensor row ────────────────────────────────
                        if (metrics.showSensorRow) ...[
                          const _SensorSection(),
                          SizedBox(height: metrics.itemSpacing),
                        ],

                        // ── PLC38 10-output LED indicators ─────────────
                        if (metrics.showLEDs) ...[
                          const _LiveLedSection(),
                          SizedBox(height: metrics.itemSpacing),
                        ],

                        // ── Main controls area ─────────────────────────
                        Expanded(
                          child: RepaintBoundary(
                            child: _CanvasSection(
                              layoutCfg: layoutCfg,
                              isEditing: isEditing,
                              localActive: _localActive,
                              onLocalActiveChanged: (id, state) =>
                                  setState(() => _localActive[id] = state),
                            ),
                          ),
                        ),

                        SizedBox(height: metrics.itemSpacing),

                        // ── Status bar ────────────────────────────────
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
              interactionMode != CustomizationInteractionMode.placingWidget,
        ),
        if (interactionMode == CustomizationInteractionMode.placingWidget)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: PlacementCancelBar(),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LayoutShape
//
// Value type combining LayoutEditController.isEditing with the layout config
// that should currently be rendered (the draft while editing, the committed
// config otherwise), so the screen's Selector2 only rebuilds when either
// actually changes.
// ─────────────────────────────────────────────────────────────────────────────

class _LayoutShape {
  const _LayoutShape({
    required this.isEditing,
    required this.interactionMode,
    required this.layoutCfg,
  });

  final bool isEditing;
  final CustomizationInteractionMode interactionMode;
  final ControlLayoutConfig layoutCfg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutShape &&
          other.isEditing == isEditing &&
          other.interactionMode == interactionMode &&
          other.layoutCfg == layoutCfg;

  @override
  int get hashCode => Object.hash(isEditing, interactionMode, layoutCfg);
}

// ─────────────────────────────────────────────────────────────────────────────
// _Plc38AppBar
// ─────────────────────────────────────────────────────────────────────────────

class _Plc38AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _Plc38AppBar({required this.labels, required this.isEditing});

  final ControlLabelConfig labels;
  final bool isEditing;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (isEditing ? 28 : 3));

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
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
            // The customize action only makes sense in normal mode — while
            // editing it would be a duplicate way to (re-)enter a mode
            // already active, so it's omitted entirely rather than disabled.
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
            const _DisconnectButton(),
          ],
        ),
        if (isEditing)
          const CustomizationModeBanner()
        else
          const DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.appBarBanner,
              border: Border(
                bottom: BorderSide(color: AppColors.appBarBannerBorder),
              ),
            ),
            child: SizedBox(height: 3),
          ),
      ],
    );
  }
}

/// Isolated because it watches connection/device-name/RSSI fields that
/// update independently of (and more often than) the AppBar's other actions.
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

// ─────────────────────────────────────────────────────────────────────────────
// Live-data leaf sections — each owns a narrow Selector so a CraneController
// notification (BLE status/analog stream, potentially many times a second)
// only rebuilds the one section whose underlying values actually changed.
// ─────────────────────────────────────────────────────────────────────────────

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

  /// Forces resetEnabled off on SafetyActionPanel while Edit Mode is active
  /// — the operator must press Done and leave Edit Mode before Reset E-Stop
  /// becomes swipeable again (see [_onResetEStopTap]'s matching guard).
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

// PLC38 exposes the full 10-field wire format (DF1/E-STOP..DF10).
const List<PlcOutputVariant> _ledVariants = [
  PlcOutputVariant.df1,
  PlcOutputVariant.df2,
  PlcOutputVariant.df3,
  PlcOutputVariant.df4,
  PlcOutputVariant.df5,
  PlcOutputVariant.df6,
  PlcOutputVariant.df7,
  PlcOutputVariant.df8,
  PlcOutputVariant.df9,
  PlcOutputVariant.df10,
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
//
// Wraps ControlCanvas with its own narrow watch of exactly the
// CraneController fields the grid's isDisabled/activeStateFor closures need
// (estopLatched, isConnected). A BLE status notification that doesn't flip
// either of those never rebuilds the grid.
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
  });

  final ControlLayoutConfig layoutCfg;
  final bool isEditing;
  final Map<String, ControlState> localActive;
  final void Function(String id, ControlState state) onLocalActiveChanged;

  bool _isMutuallyExcluded(ButtonConfig config) {
    // Cross-travel widgets manage both directions as a single unit; mutual
    // exclusion with the paired role would incorrectly disable the widget
    // mid-drag and leave it permanently stuck in the disabled state.
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

  /// Resolves the VISUAL active state for [config]. Local-touch state only
  /// (see [localActive]) — PLC feedback intentionally never feeds into a
  /// button's own visual state; it stays visible only through status/output
  /// indicators (LEDs, status chip) elsewhere on screen. estop latch forces
  /// idle regardless of local state.
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
    // Only meaningful while editing — live mode's NeverScrollableScrollPhysics
    // below never lets the operator page-swipe at all.
    final pageTransitionStyle = isEditing
        ? context.select<LayoutEditController, CanvasPageTransitionStyle>(
            (c) => c.pageTransitionStyle,
          )
        : CanvasPageTransitionStyle.slide;

    return ControlCanvas(
      layoutCfg: layoutCfg,
      isEditing: isEditing,
      pageTransitionStyle: pageTransitionStyle,
      activeStateFor: (config) =>
          _activeStateForButton(gate.estopLatched, config),
      isDisabled: (config) =>
          // isEditing is defense-in-depth: ControlCanvas already forces
          // every occupied cell's ConfigurableButton disabled+AbsorbPointer
          // while editing, but gating here too means this closure alone
          // documents and enforces "Edit Mode never sends PLC output" even
          // if that internal behavior ever changes.
          isEditing ||
          gate.estopLatched ||
          !gate.isConnected ||
          !config.enabled ||
          (config.role == null && !config.plcMappingEnabled) ||
          _isMutuallyExcluded(config),
      onCommand: (id, state) {
        ButtonStateLog.log(
          state == ControlState.idle
              ? 'SEND_IDLE  [$id] (PLC38)'
              : 'SEND_ACTIVE [$id] -> ${state.name} (PLC38)',
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
      // Generic zone-id path (multi-zone slider): the widget already reports
      // the REAL logical state id directly (e.g. 'zone1'..'zone5'), so —
      // unlike onCommand above — there is no ControlState to translate it
      // back from. [state] here is only a binary idle/non-idle bookkeeping
      // marker for localActive/mutual-exclusion; the PLC composition is
      // driven entirely by activeVariants, resolved directly from this exact
      // (buttonId, stateId) pair's ButtonConfig.stateMappings entry.
      onStateIdCommand: (id, stateId) {
        final isIdle =
            stateId == MultiZoneSliderStateId.center || stateId == 'idle';
        final state = isIdle ? ControlState.idle : ControlState.level1;
        ButtonStateLog.log(
          isIdle
              ? 'SEND_IDLE  [$id] (PLC38)'
              : 'SEND_ACTIVE [$id] -> $stateId (PLC38)',
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
    );
  }
}
