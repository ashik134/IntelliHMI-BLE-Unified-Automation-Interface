import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_slot_grid.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';
import 'package:rev_crane_control_ops/widgets/customization/button_edit_sheet.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_mode_bar.dart';
import 'package:rev_crane_control_ops/widgets/customization/editable_control_tile.dart';

// ═══════════════════════════════════════════════════════════════
// Plc38ControlScreen
//
// Rebuild-scope note: this used to sit behind one Consumer3<CraneController,
// LayoutSettingsController, CustomizationModeController> wrapping the whole
// Scaffold body, so any notifyListeners() from any of the three — including
// a BLE analog/status notification arriving many times a second — rebuilt
// the AppBar, 10-LED row, sensor row, the whole ControlSlotGrid, and the
// status chip together. `_LayoutShape` below is recomputed only when editing
// toggles, the draft/committed layout changes, or the PLC type changes; each
// live-data section (LEDs, sensor row, safety panel, status chip, the grid's
// disabled/estop gating) is its own small widget with its own narrow
// Selector, so a BLE notification only rebuilds the section that changed.
// ═══════════════════════════════════════════════════════════════

class Plc38ControlScreen extends StatefulWidget {
  const Plc38ControlScreen({super.key});

  @override
  State<Plc38ControlScreen> createState() => _Plc38ControlScreenState();
}

class _Plc38ControlScreenState extends State<Plc38ControlScreen> {
  static const List<ControlRole> _motionRoles = [
    ControlRole.hoistUp,
    ControlRole.hoistDown,
    ControlRole.traverseLeft,
    ControlRole.traverseRight,
    ControlRole.travelForward,
    ControlRole.travelReverse,
  ];

  CraneController? _craneController;

  // ── Local touch-driven active state, keyed by button id ─────────────────────
  //
  // This is the single source of truth for every button's VISUAL active/idle
  // state. It is written only by _onCommand(), which fires synchronously on
  // USER_DOWN/USER_UP/USER_CANCEL — never by PLC feedback. PLC status
  // (controller.activeCommand / hoistState) arrives asynchronously over BLE
  // and can be stale by the time it's observed (the hardware's echo of a
  // command sent moments ago), so it must never be allowed to drive a
  // button's own visual state back to active after the user has released it.
  // PLC feedback remains fully visible elsewhere (LEDs, status chip) — just
  // not here.
  final Map<String, ControlState> _localActive = {};

  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

  @override
  void initState() {
    super.initState();
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
    super.dispose();
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
  // Deliberately reachable at all times, including while Customization Mode
  // is active — the safety action panel is never gated by AbsorbPointer.

  Future<void> _onEStopTap() async {
    _resetLocalButtonStates();
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
    if (context.read<CustomizationModeController>().isActive) return;
    final controller = context.read<CraneController>();
    if (controller.currentScreen != AppScreen.plc38Control ||
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
      _resetLocalButtonStates();

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

  void _resetLocalButtonStates() {
    if (!mounted) return;
    setState(_localActive.clear);
  }

  // ── Customization Mode ──────────────────────────────────────────────────────

  Future<void> _enterCustomizationMode() async {
    _resetLocalButtonStates();
    await context.read<CustomizationModeController>().enter();
  }

  // Mirrors CustomizationModeBar's Apply action — the AppBar's "Done" banner
  // button is a second entry point to the same commit flow.
  Future<void> _finishCustomization(
    CustomizationModeController customCtrl,
  ) async {
    final result = await customCtrl.commit();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.isValid ? 'Layout applied.' : result.firstError),
        backgroundColor: result.isValid
            ? AppColors.darkSuccess
            : AppColors.eStopColor,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _confirmDeleteSelectedButton(
    CustomizationModeController customCtrl,
  ) async {
    final button = customCtrl.selectedButton;
    if (button == null) return;
    final name = button.label.isEmpty ? button.id : button.label;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text(
          'Delete button?',
          style: TextStyle(color: AppColors.darkText),
        ),
        content: Text(
          'Remove $name from the grid? The adjacent button will fill the row when possible.',
          style: const TextStyle(color: AppColors.darkTextSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.eStopColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final result = customCtrl.deleteSelectedButton();
    if (!result.isValid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Could not delete button.')),
      );
    }
  }

  Future<void> _addButton(CustomizationModeController customCtrl) async {
    await ButtonEditSheet.showForNewButton(
      context,
      preferredPageIndex: customCtrl.activeControlPage,
    );
  }

  // Tapping a vacant grid slot (or its edit icon) in Customization Mode opens
  // the same add-button flow as the AppBar's "+" action, but anchored to the
  // exact slot the operator tapped instead of the first free cell — this is
  // what makes an empty placeholder feel directly editable rather than just
  // a drop target. Never sends a PLC command: the new button only exists as
  // local sheet state until the operator saves a real control type.
  Future<void> _addButtonAtSlot(
    CustomizationModeController customCtrl,
    int pageIndex,
    int slotIndex,
  ) async {
    await ButtonEditSheet.showForNewButton(
      context,
      preferredPageIndex: pageIndex,
      preferredSlot: slotIndex,
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Selector<CraneController, PlcType>(
      selector: (_, controller) => controller.connectedPlcType,
      builder: (context, plcType, _) {
        return Selector2<
          CustomizationModeController,
          LayoutSettingsController,
          _LayoutShape
        >(
          selector: (_, customCtrl, layoutCtrl) {
            final bucket = LayoutBucket.forPlcType(plcType);
            final isEditing = customCtrl.isActive;
            final layoutCfg = isEditing
                ? customCtrl.draft
                : layoutCtrl.configFor(bucket);
            return _LayoutShape(isEditing: isEditing, layoutCfg: layoutCfg);
          },
          builder: (context, shape, _) =>
              _buildScaffold(context, shape.isEditing, shape.layoutCfg),
        );
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    bool isEditing,
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
    final customizationBarMinTop =
        MediaQuery.of(context).padding.top +
        kToolbarHeight +
        metrics.bodyPadding.top +
        metrics.estopHeight +
        metrics.itemSpacing;

    return Stack(
      children: [
        PopScope(
          canPop: !isEditing,
          onPopInvokedWithResult: _onBackAttempted,
          child: Scaffold(
            backgroundColor: AppColors.darkBg,
            resizeToAvoidBottomInset: false,
            appBar: _Plc38AppBar(
              isEditing: isEditing,
              labels: labels,
              onEnterCustomization: _enterCustomizationMode,
              onFinishCustomization: _finishCustomization,
              onAddButton: _addButton,
              onConfirmDeleteSelectedButton: _confirmDeleteSelectedButton,
            ),
            body: SafeArea(
              maintainBottomViewPadding: true,
              child: Padding(
                padding: metrics.bodyPadding,
                child: Column(
                  children: [
                    // ── E-Stop / Reset ──────────────────────────────────────
                    _SafetyPanelSection(
                      isEditing: isEditing,
                      compact: metrics.isCompact,
                      height: metrics.estopHeight,
                      width: sizing.resolvedEstopWidthOrFill,
                      instructionLabel: labels.estopSwipeInstruction,
                      resetLabel: labels.resetEstopLabel,
                      onEStopTap: _onEStopTap,
                      onResetActivated: _onResetEStopTap,
                    ),
                    SizedBox(height: metrics.itemSpacing),

                    // ── Sensor row ────────────────────────────────────────
                    if (metrics.showSensorRow) ...[
                      EditableControlTile(
                        isEditing: isEditing,
                        onDelete: () => context
                            .read<CustomizationModeController>()
                            .applyDraftChange(
                              layoutCfg.copyWith(
                                arrangementConfig: arrangement.copyWith(
                                  showSensorRow: false,
                                ),
                              ),
                            ),
                        child: const _SensorSection(),
                      ),
                      SizedBox(height: metrics.itemSpacing),
                    ],

                    // ── PLC38 10-output LED indicators ──────────────────────
                    if (metrics.showLEDs) ...[
                      EditableControlTile(
                        isEditing: isEditing,
                        onDelete: () => context
                            .read<CustomizationModeController>()
                            .applyDraftChange(
                              layoutCfg.copyWith(
                                arrangementConfig: arrangement.copyWith(
                                  showLiveLEDs: false,
                                ),
                              ),
                            ),
                        child: const _LiveLedSection(),
                      ),
                      SizedBox(height: metrics.itemSpacing),
                    ],

                    // ── Axis controls (reorderable while editing) ───────────
                    // Fixed 2 x 3 motion-control grid. Edit mode uses
                    // the same renderer and swaps slot indices.
                    Expanded(
                      child: RepaintBoundary(
                        child: _ControlGridSection(
                          layoutCfg: layoutCfg,
                          isEditing: isEditing,
                          motionRoles: _motionRoles,
                          localActive: _localActive,
                          onLocalActiveChanged: (id, state) =>
                              setState(() => _localActive[id] = state),
                          onAddButtonAtSlot: _addButtonAtSlot,
                        ),
                      ),
                    ),

                    SizedBox(height: metrics.itemSpacing),

                    // ── Status bar ────────────────────────────────────────
                    const _StatusChipSection(),
                    SizedBox(height: metrics.itemSpacing),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (isEditing)
          Positioned.fill(
            child: DraggableCustomizationModeBar(
              minTop: customizationBarMinTop,
            ),
          ),
      ],
    );
  }
}

/// Result of the outer selector: the two pieces of state that decide the
/// screen's overall shape (which sections render, what the grid contains).
/// Value-typed (`==` compares `layoutCfg` structurally — see
/// [ControlLayoutConfig.==]) so Selector skips a rebuild whenever neither
/// actually changed.
class _LayoutShape {
  const _LayoutShape({required this.isEditing, required this.layoutCfg});

  final bool isEditing;
  final ControlLayoutConfig layoutCfg;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LayoutShape &&
          other.isEditing == isEditing &&
          other.layoutCfg == layoutCfg;

  @override
  int get hashCode => Object.hash(isEditing, layoutCfg);
}

// ─────────────────────────────────────────────────────────────────────────────
// _Plc38AppBar
//
// Isolated because its actions depend on CustomizationModeController's
// selection state (selectedButton, canDeleteSelectedButton), which changes on
// every tap/drag select — far more often than the layout shape itself. Only
// the AppBar repaints for that; the grid/LEDs/sensor row below are untouched.
// ─────────────────────────────────────────────────────────────────────────────

class _Plc38AppBar extends StatelessWidget implements PreferredSizeWidget {
  const _Plc38AppBar({
    required this.isEditing,
    required this.labels,
    required this.onEnterCustomization,
    required this.onFinishCustomization,
    required this.onAddButton,
    required this.onConfirmDeleteSelectedButton,
  });

  final bool isEditing;
  final ControlLabelConfig labels;
  final VoidCallback onEnterCustomization;
  final void Function(CustomizationModeController) onFinishCustomization;
  final void Function(CustomizationModeController) onAddButton;
  final void Function(CustomizationModeController)
  onConfirmDeleteSelectedButton;

  @override
  Size get preferredSize =>
      Size.fromHeight(isEditing ? kToolbarHeight + 36 : kToolbarHeight + 3);

  @override
  Widget build(BuildContext context) {
    final customCtrl = context.watch<CustomizationModeController>();
    final selectedButton = customCtrl.selectedButton;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppBar(
          actionsPadding: const EdgeInsets.only(right: 8),
          automaticallyImplyLeading: false,
          backgroundColor: AppColors.appBarBg,
          flexibleSpace: const ControlAppBarGlow(),
          titleSpacing: isEditing ? 16 : NavigationToolbar.kMiddleSpacing,
          title: isEditing
              ? const Text(
                  'CUSTOMIZE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AppColors.appBarGlow,
                  ),
                )
              : _DeviceTitle(labels: labels),
          actions: isEditing
              ? [
                  IconButton(
                    icon: const Icon(Icons.screen_rotation_rounded),
                    color: selectedButton == null
                        ? AppColors.disabled
                        : AppColors.darkTextSub,
                    tooltip: selectedButton == null
                        ? 'Select a button to rotate'
                        : 'Rotate to ${selectedButton.rotation.next.label}',
                    onPressed: selectedButton == null
                        ? null
                        : customCtrl.rotateSelectedButton,
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    color: AppColors.darkTextSub,
                    tooltip: 'Auto arrange controls',
                    onPressed: customCtrl.autoArrangeControls,
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_rounded),
                    color: AppColors.darkTextSub,
                    tooltip: 'Add control page',
                    onPressed: customCtrl.createControlPage,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: AppColors.darkTextSub,
                    tooltip: 'Add button',
                    onPressed: () => onAddButton(customCtrl),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: selectedButton == null
                        ? AppColors.disabled
                        : AppColors.eStopColor,
                    tooltip: 'Delete selected button',
                    onPressed:
                        selectedButton == null ||
                            !customCtrl.canDeleteSelectedButton
                        ? null
                        : () => onConfirmDeleteSelectedButton(customCtrl),
                  ),
                ]
              : [
                  IconButton(
                    icon: const Icon(
                      Icons.dashboard_customize_rounded,
                      size: 20,
                      color: AppColors.darkTextSub,
                    ),
                    tooltip: 'Customize Layout',
                    onPressed: onEnterCustomization,
                  ),
                  const _DisconnectButton(),
                ],
          // REMOVED: bottom property entirely
        ),
        // Banner is now outside the AppBar
        if (isEditing)
          CustomizationStatusBanner(
            onDone: () => onFinishCustomization(customCtrl),
          )
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
/// update independently of (and more often than) the AppBar's edit actions.
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
    required this.isEditing,
    required this.compact,
    required this.height,
    required this.width,
    required this.instructionLabel,
    required this.resetLabel,
    required this.onEStopTap,
    required this.onResetActivated,
  });

  final bool isEditing;
  final bool compact;
  final double height;
  final double? width;
  final String instructionLabel;
  final String resetLabel;
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

class _LiveLedRowValues {
  const _LiveLedRowValues({
    required this.estop,
    required this.up,
    required this.down,
    required this.fast,
    required this.left,
    required this.right,
    required this.fastLr,
    required this.forward,
    required this.reverse,
    required this.fastFb,
  });

  final bool estop;
  final bool up;
  final bool down;
  final bool fast;
  final bool left;
  final bool right;
  final bool fastLr;
  final bool forward;
  final bool reverse;
  final bool fastFb;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LiveLedRowValues &&
          other.estop == estop &&
          other.up == up &&
          other.down == down &&
          other.fast == fast &&
          other.left == left &&
          other.right == right &&
          other.fastLr == fastLr &&
          other.forward == forward &&
          other.reverse == reverse &&
          other.fastFb == fastFb;

  @override
  int get hashCode => Object.hash(
    estop,
    up,
    down,
    fast,
    left,
    right,
    fastLr,
    forward,
    reverse,
    fastFb,
  );
}

class _LiveLedSection extends StatelessWidget {
  const _LiveLedSection();

  @override
  Widget build(BuildContext context) {
    final v = context.select<CraneController, _LiveLedRowValues>(
      (c) => _LiveLedRowValues(
        estop: c.ledEstop,
        up: c.ledUp,
        down: c.ledDown,
        fast: c.ledFast,
        left: c.ledLeft,
        right: c.ledRight,
        fastLr: c.ledFastLr,
        forward: c.ledForward,
        reverse: c.ledReverse,
        fastFb: c.ledFastFb,
      ),
    );
    return RepaintBoundary(
      child: LiveLedRow(
        leds: [
          LedSpec(
            label: 'ESTOP',
            active: v.estop,
            color: AppColors.eStopColor,
            pin: 'Q_ES',
          ),
          LedSpec(
            label: 'UP',
            active: v.up,
            color: AppColors.upColor,
            pin: 'Q0.1',
          ),
          LedSpec(
            label: 'DN',
            active: v.down,
            color: AppColors.downColor,
            pin: 'Q0.2',
          ),
          LedSpec(
            label: 'FU',
            active: v.fast,
            color: AppColors.fastColor,
            pin: 'Q0.3',
          ),
          LedSpec(
            label: 'LT',
            active: v.left,
            color: AppColors.traverseColor,
            pin: 'Q0.4',
          ),
          LedSpec(
            label: 'RT',
            active: v.right,
            color: AppColors.traverseColor,
            pin: 'Q0.5',
          ),
          LedSpec(
            label: 'FL',
            active: v.fastLr,
            color: AppColors.fastColor,
            pin: 'Q0.6',
          ),
          LedSpec(
            label: 'FW',
            active: v.forward,
            color: AppColors.travelColor,
            pin: 'Q0.7',
          ),
          LedSpec(
            label: 'RV',
            active: v.reverse,
            color: AppColors.travelColor,
            pin: 'Q0.8',
          ),
          LedSpec(
            label: 'FB',
            active: v.fastFb,
            color: AppColors.fastColor,
            pin: 'Q0.9',
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
            : AppColors.upColorLight,
        label: controller.activeCommand.statusLabel,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ControlGridSection
//
// Wraps ControlSlotGrid with its own narrow watch of exactly the
// CraneController fields the grid's isDisabled/activeStateFor closures need
// (estopLatched, isConnected) plus CustomizationModeController's selection/
// paging state. A BLE status notification that doesn't flip estopLatched or
// isConnected never rebuilds the grid.
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

class _ControlGridSection extends StatelessWidget {
  const _ControlGridSection({
    required this.layoutCfg,
    required this.isEditing,
    required this.motionRoles,
    required this.localActive,
    required this.onLocalActiveChanged,
    required this.onAddButtonAtSlot,
  });

  final ControlLayoutConfig layoutCfg;
  final bool isEditing;
  final List<ControlRole> motionRoles;
  final Map<String, ControlState> localActive;
  final void Function(String id, ControlState state) onLocalActiveChanged;
  final Future<void> Function(CustomizationModeController, int, int)
  onAddButtonAtSlot;

  bool _isMutuallyExcluded(ButtonConfig config) {
    // Cross-travel widgets manage both directions as a single unit — the
    // slider physically prevents left+right from activating simultaneously.
    // Applying mutual exclusion here would cause isDisabled to flip true
    // mid-drag (when the paired role's localActive entry is set), which
    // in turn causes the slider to get stuck in a permanently disabled state.
    if (config.type == ButtonType.crossTravel ||
        config.type == ButtonType.crossTravelSlowOnly) {
      return false;
    }
    for (final excludedId in config.mutualExclusion.excludedButtonIds) {
      if ((localActive[excludedId] ?? ControlState.idle) != ControlState.idle) {
        return true;
      }
    }
    return false;
  }

  /// Resolves the VISUAL active state for [config]. This is local-touch
  /// state only (see [localActive]) — PLC feedback (`controller.activeCommand`)
  /// intentionally never feeds into a button's own visual state; it stays
  /// visible only through status/output indicators (LEDs, status chip)
  /// elsewhere on screen. estop latch forces idle regardless of local state
  /// since the crane physically cannot be moving in that condition.
  ControlState _activeStateForButton(bool estopLatched, ButtonConfig config) {
    if (estopLatched) return ControlState.idle;
    return localActive[config.id] ?? ControlState.idle;
  }

  @override
  Widget build(BuildContext context) {
    final gate = context.select<CraneController, _GridGateValues>(
      (c) => _GridGateValues(c.estopLatched, c.isConnected),
    );
    final customCtrl = context.watch<CustomizationModeController>();
    final controlsDisabled = gate.estopLatched || !gate.isConnected;

    return ControlSlotGrid(
      layoutCfg: layoutCfg,
      roles: motionRoles,
      isEditing: isEditing,
      activeStateFor: (config) =>
          _activeStateForButton(gate.estopLatched, config),
      isDisabled: (config) =>
          // isEditing is defense-in-depth: ControlSlotGrid already forces
          // every occupied slot's ConfigurableButton disabled+AbsorbPointer
          // in Customization Mode and never wires onCommand for vacant
          // slots, but gating here too means this closure alone documents
          // and enforces "Customization Mode never sends PLC output" even
          // if that internal behavior ever changes.
          isEditing ||
          controlsDisabled ||
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
        context.read<CraneController>().setButtonCommand(
          buttonId: id,
          state: state,
          stateId: resolved.stateId,
          activeVariants: resolved.activeVariants,
        );
      },
      onEditButton: (config) {
        final role = config.role;
        if (role != null) {
          ButtonEditSheet.showForRole(context, role);
        } else {
          ButtonEditSheet.showForButton(context, config.id);
        }
      },
      selectedRole: customCtrl.selectedRole,
      selectedButtonId: customCtrl.selectedSlotId,
      onPageChanged: customCtrl.setActiveControlPage,
      activePageIndex: customCtrl.activeControlPage,
      onSelectButton: isEditing ? customCtrl.selectButton : null,
      onSlotDrop: isEditing
          ? (
              dragged,
              sourceSlot,
              target,
              targetSlot, {
              required targetPageIndex,
            }) {
              final result = buildGridSlotDrop(
                buttons: customCtrl.draft.resolvedButtons,
                dragged: dragged,
                sourceSlot: sourceSlot,
                target: target,
                targetSlot: targetSlot,
                targetPageIndex: targetPageIndex,
              );
              if (!result.isValid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.message ?? kCrossTravelSpanMessage),
                  ),
                );
                return;
              }
              customCtrl.applyDraftChangeAndCompact(
                customCtrl.draft.copyWith(buttons: result.buttons),
              );
            }
          : null,
      onResizeButton: isEditing
          ? (config, gridColumns, gridRows, {anchorX, anchorY}) {
              final result = buildButtonResize(
                buttons: customCtrl.draft.resolvedButtons,
                selected: config,
                gridColumns: gridColumns,
                gridRows: gridRows,
                anchorX: anchorX,
                anchorY: anchorY,
              );
              if (!result.isValid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.message ?? kWidgetPlacementMessage),
                  ),
                );
                return;
              }
              customCtrl.applyDraftChangeAndCompact(
                customCtrl.draft.copyWith(buttons: result.buttons),
              );
            }
          : null,
      onSelectVacantSlot: isEditing
          ? (pageIndex, slotIndex) {
              customCtrl.selectVacantSlot(pageIndex, slotIndex);
              onAddButtonAtSlot(customCtrl, pageIndex, slotIndex);
            }
          : null,
    );
  }
}
