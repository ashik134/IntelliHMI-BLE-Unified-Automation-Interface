import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/button_rotation.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/models/button_config.dart';
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
import 'package:rev_crane_control_ops/widgets/customization/free_button_edit_sheet.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // All 6 motion roles are always passed to ControlSlotGrid so PLC14/PLC21
  // get the same 6-slot grid shape as PLC38. Each PLC type's default layout
  // decides which role buttons are visible and how many grid cells they span.
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

  // ── Local touch-driven active state, keyed by button id ─────────────────────
  //
  // Single source of truth for every button's VISUAL active/idle state.
  // Written only by the onCommand callback below, which fires synchronously
  // on USER_DOWN/USER_UP/USER_CANCEL — never by PLC feedback. PLC status
  // (controller.hoistState) arrives asynchronously over BLE and can echo a
  // command that has already been released locally, so it must never drive
  // a button's own visual state back to active. PLC feedback stays visible
  // through status/output indicators (LEDs, status chip) elsewhere.
  final Map<String, ControlState> _localActive = {};
  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
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
    WidgetsBinding.instance.removeObserver(this);
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
    if (controller.currentScreen != AppScreen.control ||
        controller.isDisconnected) {
      _dismissResetDialogIfVisible();
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
  // Deliberately reachable at all times, including while Customization Mode
  // is active — the safety action panel is never gated by AbsorbPointer.

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
    if (controller.currentScreen != AppScreen.control ||
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

      // Stop all motion before showing the dialog so the PLC never keeps
      // moving while the operator is looking at a confirmation prompt.
      await controller.stopAllMotion();
      _resetLocalButtonStates();

      if (!mounted) return;
      final confirmed = await showControlExitDialog(context);
      if (!mounted) return;

      if (confirmed) {
        // disconnect() sends a final idle command then drops the BLE link.
        // The HMIAppShell reacts to isDisconnected and swaps in ConnectionScreen
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

  Future<void> _addFreeButton(CustomizationModeController customCtrl) async {
    final id = 'custom_${DateTime.now().microsecondsSinceEpoch}';
    final button = ButtonConfig(
      id: id,
      type: ButtonType.pushButton,
      plcMapping: PlcMapping.up,
      label: 'New Button',
      enabled: false,
      plcMappingEnabled: false,
      pageIndex: customCtrl.activeControlPage,
    );
    final result = customCtrl.addControlButton(button);
    if (!mounted) return;
    if (!result.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Could not add button.')),
      );
      return;
    }
    await FreeButtonEditSheet.show(context, id);
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
        final bucket = LayoutBucket.forPlcType(controller.connectedPlcType);
        final layoutCfg = isEditing
            ? customCtrl.draft
            : layoutCtrl.configFor(bucket);
        final labels = layoutCfg.labelConfig;
        final sizing = layoutCfg.sizeConfig;
        final arrangement = layoutCfg.arrangementConfig;
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
            : (controller.connectedDeviceName ?? BLEConstants.deviceName);
        final selectedButton = customCtrl.selectedButton;
        final customizationBarMinTop =
            MediaQuery.of(ctx).padding.top +
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
                appBar: AppBar(
                  actionsPadding: const EdgeInsets.only(right: 8),
                  automaticallyImplyLeading: false,
                  backgroundColor: AppColors.appBarBg,
                  flexibleSpace: const ControlAppBarGlow(),
                  titleSpacing: isEditing
                      ? 16
                      : NavigationToolbar.kMiddleSpacing,
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
                      : DeviceInfoAppBarTitle(
                          deviceName: screenTitle,
                          plcType: controller.connectedPlcType,
                          rssi: controller.connectedDeviceRssi,
                        ),
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
                            onPressed: () => _addFreeButton(customCtrl),
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
                                : () =>
                                      _confirmDeleteSelectedButton(customCtrl),
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
                            onPressed: _enterCustomizationMode,
                          ),
                          IconButton.filledTonal(
                            onPressed: controller.disconnect,
                            tooltip: 'Disconnect',
                            style: IconButton.styleFrom(
                              foregroundColor: AppColors.error,
                              backgroundColor: AppColors.error.withValues(
                                alpha: 0.10,
                              ),
                              hoverColor: AppColors.error.withValues(
                                alpha: 0.15,
                              ),
                              highlightColor: AppColors.error.withValues(
                                alpha: 0.20,
                              ),
                              minimumSize: const Size(42, 42),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: AppColors.error.withValues(
                                    alpha: 0.22,
                                  ),
                                ),
                              ),
                            ),
                            icon: const Icon(
                              Icons.power_settings_new_rounded,
                              size: 21,
                            ),
                          ),
                        ],
                  bottom: isEditing
                      ? CustomizationStatusBanner(
                          onDone: () => _finishCustomization(customCtrl),
                        )
                      : const PreferredSize(
                          preferredSize: Size.fromHeight(3),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.appBarBanner,
                              border: Border(
                                bottom: BorderSide(
                                  color: AppColors.appBarBannerBorder,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                body: SafeArea(
                  maintainBottomViewPadding: true,
                  child: Padding(
                    padding: metrics.bodyPadding,
                    child: Column(
                      children: [
                        SafetyActionPanel(
                          estopLatched: controller.estopLatched,
                          compact: metrics.isCompact,
                          height: metrics.estopHeight,
                          width: sizing.resolvedEstopWidthOrFill,
                          instructionLabel: labels.estopSwipeInstruction,
                          resetLabel: labels.resetEstopLabel,
                          onEStopTap: _onEStopTap,
                          onResetActivated: _onResetEStopTap,
                        ),
                        SizedBox(height: metrics.itemSpacing),
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
                                  pin: 'R0_0',
                                ),
                                LedSpec(
                                  label: 'UP',
                                  active: controller.ledUp,
                                  color: AppColors.upColor,
                                  pin: 'Q0.1',
                                ),
                                LedSpec(
                                  label: 'DOWN',
                                  active: controller.ledDown,
                                  color: AppColors.downColor,
                                  pin: 'Q0.2',
                                ),
                                LedSpec(
                                  label: 'FAST',
                                  active: controller.ledFast,
                                  color: AppColors.fastColor,
                                  pin: 'Q0.3',
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: metrics.itemSpacing),
                        ],
                        Expanded(
                          child: ControlSlotGrid(
                            layoutCfg: layoutCfg,
                            roles: _motionRoles,
                            isEditing: isEditing,
                            activeStateFor: (config) =>
                                _activeStateForButton(controller, config),
                            isDisabled: (config) =>
                                controller.estopLatched ||
                                !controller.isConnected ||
                                !config.enabled ||
                                (config.role == null &&
                                    !config.plcMappingEnabled) ||
                                _isMutuallyExcluded(config),
                            onCommand: (id, state) {
                              final config = layoutCfg.resolvedButtons[id];
                              ButtonStateLog.log(
                                state == ControlState.idle
                                    ? 'SEND_IDLE  [$id] (PLC14)'
                                    : 'SEND_ACTIVE [$id] -> ${state.name} (PLC14)',
                              );
                              setState(() {
                                _localActive[id] = state;
                              });
                              controller.setButtonCommand(
                                buttonId: id,
                                state: state,
                                plcMapping: config?.role == null
                                    ? config?.plcMapping
                                    : null,
                                plcMappingEnabled: config?.role == null
                                    ? config?.plcMappingEnabled ?? false
                                    : true,
                              );
                            },
                            onEditButton: (config) {
                              final role = config.role;
                              if (role != null) {
                                ButtonEditSheet.showForRole(context, role);
                              } else {
                                FreeButtonEditSheet.show(context, config.id);
                              }
                            },
                            selectedRole: customCtrl.selectedRole,
                            selectedButtonId: customCtrl.selectedButton?.id,
                            onPageChanged: customCtrl.setActiveControlPage,
                            activePageIndex: customCtrl.activeControlPage,
                            onSelectButton: isEditing
                                ? customCtrl.selectButton
                                : null,
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
                            onResizeButton: isEditing
                                ? (config, gridColumns, gridRows) {
                                    final result = buildButtonResize(
                                      buttons: customCtrl.draft.resolvedButtons,
                                      selected: config,
                                      gridColumns: gridColumns,
                                      gridRows: gridRows,
                                    );
                                    if (!result.isValid) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            result.message ??
                                                kWidgetPlacementMessage,
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

                        StatusBarChip(
                          color: controller.estopLatched
                              ? AppColors.eStopColor
                              : switch (controller.hoistState) {
                                  HoistState.idle => AppColors.idleColor,
                                  HoistState.upSlow => AppColors.upColor,
                                  HoistState.upFast => AppColors.fastColor,
                                  HoistState.downSlow => AppColors.downColor,
                                  HoistState.downFast => AppColors.fastColor,
                                },
                          label: controller.statusLabel,
                        ),

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
      },
    );
  }

  bool _isMutuallyExcluded(ButtonConfig config) {
    // Cross-travel widgets manage both directions as a single unit; mutual
    // exclusion with the paired role would incorrectly disable the widget
    // mid-drag and leave it permanently stuck in the disabled state.
    if (config.type == ButtonType.crossTravel ||
        config.type == ButtonType.crossTravelSlowOnly) {
      return false;
    }
    for (final excludedId in config.mutualExclusion.excludedButtonIds) {
      if ((_localActive[excludedId] ?? ControlState.idle) !=
          ControlState.idle) {
        return true;
      }
    }
    return false;
  }

  /// Resolves the VISUAL active state for [config]. Local-touch state only
  /// (see [_localActive]) — PLC feedback (`controller.hoistState`) intentionally
  /// never feeds into a button's own visual state; it stays visible only
  /// through status/output indicators (LEDs, status chip) elsewhere on
  /// screen. estop latch forces idle regardless of local state.
  ControlState _activeStateForButton(
    CraneController controller,
    ButtonConfig config,
  ) {
    if (controller.estopLatched) return ControlState.idle;
    return _localActive[config.id] ?? ControlState.idle;
  }
}
