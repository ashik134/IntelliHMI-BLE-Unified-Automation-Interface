import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/control_slot_grid.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';
import 'package:rev_crane_control_ops/widgets/customization/button_edit_sheet.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_mode_bar.dart';
import 'package:rev_crane_control_ops/widgets/customization/editable_control_tile.dart';

// ═══════════════════════════════════════════════════════════════
// Plc38ControlScreen
// ═══════════════════════════════════════════════════════════════

class Plc38ControlScreen extends StatefulWidget {
  const Plc38ControlScreen({super.key});

  @override
  State<Plc38ControlScreen> createState() => _Plc38ControlScreenState();
}

class _Plc38ControlScreenState extends State<Plc38ControlScreen>
    with SingleTickerProviderStateMixin {
  static const List<ControlRole> _motionRoles = [
    ControlRole.hoistUp,
    ControlRole.hoistDown,
    ControlRole.traverseLeft,
    ControlRole.traverseRight,
    ControlRole.travelForward,
    ControlRole.travelReverse,
  ];

  late final AnimationController _pulseController;
  CraneController? _craneController;

  // ── Local optimistic active state, keyed by button id ───────────────────────
  final Map<String, bool> _localActive = {};

  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

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
    _pulseController.dispose();
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

  bool _isMutuallyExcluded(ButtonConfig config) {
    // Cross-travel widgets manage both directions as a single unit — the
    // slider physically prevents left+right from activating simultaneously.
    // Applying mutual exclusion here would cause isDisabled to flip true
    // mid-drag (when the paired role's _localActive entry is set), which
    // in turn causes the slider to get stuck in a permanently disabled state.
    if (config.type == ButtonType.crossTravel ||
        config.type == ButtonType.crossTravelSlowOnly) return false;
    for (final excludedId in config.mutualExclusion.excludedButtonIds) {
      if (_localActive[excludedId] == true) return true;
    }
    return false;
  }

  // ── Customization Mode ──────────────────────────────────────────────────────

  Future<void> _enterCustomizationMode() async {
    _resetLocalButtonStates();
    await context.read<CustomizationModeController>().enter();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer3<
      CraneController,
      LayoutSettingsController,
      CustomizationModeController
    >(
      builder: (ctx, controller, layoutCtrl, customCtrl, _) {
        final isEditing = customCtrl.isActive;
        final layoutCfg = isEditing ? customCtrl.draft : layoutCtrl.config;
        final labels = layoutCfg.labelConfig;
        final sizing = layoutCfg.sizeConfig;
        final arrangement = layoutCfg.arrangementConfig;
        final controlsDisabled =
            controller.estopLatched || !controller.isConnected;
        final metrics = ControlLayoutMetrics.compute(
          MediaQuery.of(ctx).size.height -
              kToolbarHeight -
              MediaQuery.of(ctx).padding.top -
              MediaQuery.of(ctx).padding.bottom,
          baseEstopHeight: sizing.resolvedEstopHeight,
          preferShowSensor: arrangement.showSensorRow,
          preferShowLEDs: arrangement.showLiveLEDs,
        );
        final screenTitle = labels.screenTitle.isNotEmpty
            ? labels.screenTitle
            : (controller.connectedDeviceName ?? 'PLC38');

        return Stack(
          children: [
            PopScope(
              canPop: !isEditing,
              onPopInvokedWithResult: _onBackAttempted,
              child: Scaffold(
                backgroundColor: AppColors.darkBg,
                resizeToAvoidBottomInset: false,
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEditing ? 'CUSTOMIZE LAYOUT' : screenTitle,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      if (!isEditing && arrangement.showConnectionSubtitle)
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(
                                color: AppColors.upColorLight,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const Text(
                              'Connected · PLC38',
                              style: TextStyle(
                                color: AppColors.upColorLight,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  actions: isEditing
                      ? const []
                      : [
                          IconButton(
                            icon: const Icon(
                              Icons.dashboard_customize_rounded,
                              size: 20,
                              color: AppColors.darkTextSub,
                            ),
                            tooltip: 'Customize Layout',
                            onPressed: _enterCustomizationMode,
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.bluetooth_disabled,
                              size: 20,
                              color: AppColors.darkTextSub,
                            ),
                            tooltip: 'Disconnect',
                            onPressed: controller.disconnect,
                          ),
                        ],
                ),
                body: SafeArea(
                  maintainBottomViewPadding: true,
                  child: Padding(
                    padding: metrics.bodyPadding.add(
                      EdgeInsets.only(bottom: isEditing ? 84 : 0),
                    ),
                    child: Column(
                      children: [
                        // ── E-Stop / Reset ──────────────────────────────────────
                        SafetyActionPanel(
                          estopLatched: controller.estopLatched,
                          compact: metrics.isCompact,
                          height: metrics.estopHeight,
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
                            onDelete: () => customCtrl.applyDraftChange(
                              layoutCfg.copyWith(
                                arrangementConfig: arrangement.copyWith(
                                  showSensorRow: false,
                                ),
                              ),
                            ),
                            child: SensorRow(
                              a1: controller.a1,
                              a2: controller.a2,
                            ),
                          ),
                          SizedBox(height: metrics.itemSpacing),
                        ],

                        // ── PLC38 10-output LED indicators ──────────────────────
                        if (metrics.showLEDs) ...[
                          EditableControlTile(
                            isEditing: isEditing,
                            onDelete: () => customCtrl.applyDraftChange(
                              layoutCfg.copyWith(
                                arrangementConfig: arrangement.copyWith(
                                  showLiveLEDs: false,
                                ),
                              ),
                            ),
                            child: LiveLedRow(
                              leds: [
                                LedSpec(
                                  label: 'ESTOP',
                                  active: controller.ledEstop,
                                  color: AppColors.eStopColor,
                                  pin: 'Q_ES',
                                ),
                                LedSpec(
                                  label: 'UP',
                                  active: controller.ledUp,
                                  color: AppColors.upColor,
                                  pin: 'Q0.1',
                                ),
                                LedSpec(
                                  label: 'DN',
                                  active: controller.ledDown,
                                  color: AppColors.downColor,
                                  pin: 'Q0.2',
                                ),
                                LedSpec(
                                  label: 'FU',
                                  active: controller.ledFast,
                                  color: AppColors.fastColor,
                                  pin: 'Q0.3',
                                ),
                                LedSpec(
                                  label: 'LT',
                                  active: controller.ledLeft,
                                  color: AppColors.traverseColor,
                                  pin: 'Q0.4',
                                ),
                                LedSpec(
                                  label: 'RT',
                                  active: controller.ledRight,
                                  color: AppColors.traverseColor,
                                  pin: 'Q0.5',
                                ),
                                LedSpec(
                                  label: 'FL',
                                  active: controller.ledFastLr,
                                  color: AppColors.fastColor,
                                  pin: 'Q0.6',
                                ),
                                LedSpec(
                                  label: 'FW',
                                  active: controller.ledForward,
                                  color: AppColors.travelColor,
                                  pin: 'Q0.7',
                                ),
                                LedSpec(
                                  label: 'RV',
                                  active: controller.ledReverse,
                                  color: AppColors.travelColor,
                                  pin: 'Q0.8',
                                ),
                                LedSpec(
                                  label: 'FB',
                                  active: controller.ledFastFb,
                                  color: AppColors.fastColor,
                                  pin: 'Q0.9',
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: metrics.itemSpacing),
                        ],

                        // ── Axis controls (reorderable while editing) ───────────
                        // Fixed 2 x 3 motion-control grid. Edit mode uses
                        // the same renderer and swaps slot indices.
                        Expanded(
                          child: ControlSlotGrid(
                            layoutCfg: layoutCfg,
                            roles: _motionRoles,
                            isEditing: isEditing,
                            activeStateFor: (config) =>
                                _activeStateForButton(controller, config),
                            isDisabled: (config) =>
                                controlsDisabled ||
                                !config.enabled ||
                                _isMutuallyExcluded(config),
                            onCommand: (id, state) =>
                                _onCommand(controller, id, state),
                            onEditButton: (config) {
                              final role = config.role;
                              if (role != null) {
                                ButtonEditSheet.showForRole(context, role);
                              }
                            },
                            onSlotDrop: isEditing
                                ? (dragged, sourceSlot, target, targetSlot) {
                                    final result = buildGridSlotDrop(
                                      buttons: customCtrl.draft.resolvedButtons,
                                      dragged: dragged,
                                      sourceSlot: sourceSlot,
                                      target: target,
                                      targetSlot: targetSlot,
                                    );
                                    if (!result.isValid) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result.message ??
                                                kCrossTravelSpanMessage,
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    customCtrl.applyDraftChange(
                                      customCtrl.draft.copyWith(
                                        buttons: result.buttons,
                                      ),
                                    );
                                  }
                                : null,
                          ),
                        ),

                        SizedBox(height: metrics.itemSpacing),

                        // ── Status bar ────────────────────────────────────────
                        StatusBarChip(
                          color: controller.estopLatched
                              ? AppColors.eStopColor
                              : controller.activeCommand.isIdle
                              ? AppColors.idleColor
                              : AppColors.upColorLight,
                          label: controller.activeCommand.statusLabel,
                        ),
                        SizedBox(height: metrics.itemSpacing),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (isEditing)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomizationModeBar(),
              ),
          ],
        );
      },
    );
  }

  void _onCommand(CraneController controller, String id, ControlState state) {
    setState(() => _localActive[id] = state != ControlState.idle);
    controller.setButtonCommand(buttonId: id, state: state);
  }

  ControlState _activeStateForButton(
    CraneController controller,
    ButtonConfig config,
  ) {
    switch (config.plcMapping) {
      case PlcMapping.up:
        return _externalVertState(controller, isUp: true);
      case PlcMapping.down:
        return _externalVertState(controller, isUp: false);
      case PlcMapping.left:
        return _externalTravState(controller, isLeft: true);
      case PlcMapping.right:
        return _externalTravState(controller, isLeft: false);
      case PlcMapping.forward:
        return _externalTripState(controller, isForward: true);
      case PlcMapping.reverse:
        return _externalTripState(controller, isForward: false);
      case PlcMapping.estop:
      case PlcMapping.fastUd:
      case PlcMapping.fastLr:
      case PlcMapping.fastFb:
        return ControlState.idle;
    }
  }

  // ── HOIST axis content ──────────────────────────────────────────────────────

  // ── TRAVERSE axis content ───────────────────────────────────────────────────

  // ── TRAVEL axis content ─────────────────────────────────────────────────────

  ControlState _externalVertState(CraneController c, {required bool isUp}) {
    if (c.estopLatched) return ControlState.idle;
    final cmd = c.activeCommand;
    if (isUp && cmd.up) {
      return cmd.fastUd ? ControlState.fast : ControlState.slow;
    }
    if (!isUp && cmd.down) {
      return cmd.fastUd ? ControlState.fast : ControlState.slow;
    }
    return ControlState.idle;
  }

  ControlState _externalTravState(CraneController c, {required bool isLeft}) {
    if (c.estopLatched) return ControlState.idle;
    final cmd = c.activeCommand;
    if (isLeft && cmd.left) {
      return cmd.fastLr ? ControlState.fast : ControlState.slow;
    }
    if (!isLeft && cmd.right) {
      return cmd.fastLr ? ControlState.fast : ControlState.slow;
    }
    return ControlState.idle;
  }

  ControlState _externalTripState(
    CraneController c, {
    required bool isForward,
  }) {
    if (c.estopLatched) return ControlState.idle;
    final cmd = c.activeCommand;
    if (isForward && cmd.forward) {
      return cmd.fastFb ? ControlState.fast : ControlState.slow;
    }
    if (!isForward && cmd.reverse) {
      return cmd.fastFb ? ControlState.fast : ControlState.slow;
    }
    return ControlState.idle;
  }
}
