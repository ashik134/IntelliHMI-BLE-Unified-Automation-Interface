import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/widgets/crane_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/push_control_button.dart';
import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';
import 'package:rev_crane_control_ops/widgets/customization/button_edit_sheet.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_mode_bar.dart';
import 'package:rev_crane_control_ops/widgets/customization/editable_control_tile.dart';
import 'package:rev_crane_control_ops/widgets/customization/toggle_switch_button.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  
  CraneController? _craneController;

  // ── Mutual-exclusion: only one hoist direction active at a time ────────────
  bool _upActive = false;
  bool _downActive = false;
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
    if (!mounted || _resetDialogContext == null || _isDismissingResetDialog) return;
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
    setState(() {
      _upActive = false;
      _downActive = false;
    });
  }

  // ── Customization Mode ──────────────────────────────────────────────────────

  Future<void> _enterCustomizationMode() async {
    _resetLocalButtonStates();
    await context.read<CustomizationModeController>().enter();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer3<CraneController, LayoutSettingsController, CustomizationModeController>(
      builder: (ctx, controller, layoutCtrl, customCtrl, _) {
        final isEditing = customCtrl.isActive;
        final layoutCfg = isEditing ? customCtrl.draft : layoutCtrl.config;
        final labels = layoutCfg.labelConfig;
        final sizing = layoutCfg.sizeConfig;
        final arrangement = layoutCfg.arrangementConfig;
        final hoistAxisCfg = layoutCfg.axisConfigs.hoist;
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
                              'Connected',
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
                    padding: metrics.bodyPadding,
                    child: Column(
                      children: [
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
                            child: SensorRow(a1: controller.a1, a2: controller.a2),
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
                        // ── Hoist controls – Expanded fills all remaining space
                        // (prevents overflow on compact / landscape screens).
                        Expanded(
                          child: _hoistControls(
                            controller: controller,
                            labels: labels,
                            axisCfg: hoistAxisCfg,
                            roleStyles: layoutCfg.roleStyles,
                            sizing: sizing,
                            isEditing: isEditing,
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

  Widget _hoistControls({
    required CraneController controller,
    required ControlLabelConfig labels,
    required AxisControlConfig axisCfg,
    required RoleStyleConfig roleStyles,
    required ControlWidgetSizeConfig sizing,
    required bool isEditing,
  }) {
    final isDisabled = controller.estopLatched || !controller.isConnected;
    final upStyle = roleStyles.forRole(ControlRole.hoistUp);
    final downStyle = roleStyles.forRole(ControlRole.hoistDown);

    switch (axisCfg.widgetType) {
      case ControlWidgetType.pushButton:
        return Row(
          children: [
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () =>
                    ButtonEditSheet.showForRole(context, ControlRole.hoistUp),
                child: SizedBox(
                  height: axisCfg.resolvedHeight,
                  child: UpPushControlButton(
                    label: labels.upLabel,
                    isActive: controller.hoistState == HoistState.upSlow,
                    isDisabled: isDisabled,
                    isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                    colorOverride: upStyle.primaryColor,
                    colorOverrideLight: upStyle.activeColor,
                    onCommandChanged: (state) {
                      setState(() => _upActive = state != ControlState.idle);
                      controller.setHoistCommand(isUp: true, state: state);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () => ButtonEditSheet.showForRole(
                  context,
                  ControlRole.hoistDown,
                ),
                child: SizedBox(
                  height: axisCfg.resolvedHeight,
                  child: DownPushControlButton(
                    label: labels.downLabel,
                    isActive: controller.hoistState == HoistState.downSlow,
                    isDisabled: isDisabled,
                    isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                    colorOverride: downStyle.primaryColor,
                    colorOverrideLight: downStyle.activeColor,
                    onCommandChanged: (state) {
                      setState(() => _downActive = state != ControlState.idle);
                      controller.setHoistCommand(isUp: false, state: state);
                    },
                  ),
                ),
              ),
            ),
          ],
        );

      case ControlWidgetType.toggle:
        return Row(
          children: [
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () =>
                    ButtonEditSheet.showForRole(context, ControlRole.hoistUp),
                child: ToggleSwitchButton(
                  label: labels.upLabel,
                  icon: Icons.arrow_upward_rounded,
                  activeColor: upStyle.resolvePrimary(AppColors.upColor),
                  activeColorLight: upStyle.resolveActive(AppColors.upColorLight),
                  isActive: controller.hoistState == HoistState.upSlow,
                  isDisabled: isDisabled || _downActive,
                  isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                  style: upStyle,
                  onCommandChanged: (state) {
                    setState(() => _upActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: true, state: state);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () => ButtonEditSheet.showForRole(
                  context,
                  ControlRole.hoistDown,
                ),
                child: ToggleSwitchButton(
                  label: labels.downLabel,
                  icon: Icons.arrow_downward_rounded,
                  activeColor: downStyle.resolvePrimary(AppColors.downColor),
                  activeColorLight: downStyle.resolveActive(
                    AppColors.downColorLight,
                  ),
                  isActive: controller.hoistState == HoistState.downSlow,
                  isDisabled: isDisabled || _upActive,
                  isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                  style: downStyle,
                  onCommandChanged: (state) {
                    setState(() => _downActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: false, state: state);
                  },
                ),
              ),
            ),
          ],
        );

      case ControlWidgetType.sliderButton:
      case ControlWidgetType.joystick:
      case ControlWidgetType.rotary:
        return Row(
          children: [
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () =>
                    ButtonEditSheet.showForRole(context, ControlRole.hoistUp),
                child: CraneSliderButton(
                  label: labels.upLabel,
                  icon: Icons.arrow_upward_rounded,
                  isUp: true,
                  axisColor: upStyle.primaryColor,
                  // Disabled when e-stop is active, disconnected,
                  // OR the DOWN button is currently active (mutual exclusion).
                  isDisabled: isDisabled || _downActive,
                  onCommandChanged: (state) {
                    setState(() => _upActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: true, state: state);
                  },
                  externalState: switch (controller.hoistState) {
                    HoistState.upSlow => ControlState.slow,
                    HoistState.upFast => ControlState.fast,
                    _ => ControlState.idle,
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: EditableControlTile(
                isEditing: isEditing,
                onCustomize: () => ButtonEditSheet.showForRole(
                  context,
                  ControlRole.hoistDown,
                ),
                child: CraneSliderButton(
                  label: labels.downLabel,
                  icon: Icons.arrow_downward_rounded,
                  isUp: false,
                  axisColor: downStyle.primaryColor,
                  // Disabled when e-stop is active, disconnected,
                  // OR the UP button is currently active (mutual exclusion).
                  isDisabled: isDisabled || _upActive,
                  onCommandChanged: (state) {
                    setState(() => _downActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: false, state: state);
                  },
                  externalState: switch (controller.hoistState) {
                    HoistState.downSlow => ControlState.slow,
                    HoistState.downFast => ControlState.fast,
                    _ => ControlState.idle,
                  },
                ),
              ),
            ),
          ],
        );
    }
  }
}
