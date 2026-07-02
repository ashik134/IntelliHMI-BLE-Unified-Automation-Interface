import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/customization_mode_controller.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/widgets/buttons/cross_travel_slider.dart';
import 'package:rev_crane_control_ops/widgets/buttons/crane_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/push_control_button.dart';
import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';
import 'package:rev_crane_control_ops/widgets/customization/button_edit_sheet.dart';
import 'package:rev_crane_control_ops/widgets/customization/customization_mode_bar.dart';
import 'package:rev_crane_control_ops/widgets/customization/editable_control_tile.dart';
import 'package:rev_crane_control_ops/widgets/customization/toggle_switch_button.dart';

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
  late final AnimationController _pulseController;
  CraneController? _craneController;

  // ── Per-axis active flags for mutual exclusion within the same axis ────────
  bool _vertUpActive = false;
  bool _vertDownActive = false;
  bool _travLeftActive = false;
  bool _travRightActive = false;
  bool _tripFwdActive = false;
  bool _tripRevActive = false;

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
    setState(() {
      _vertUpActive = false;
      _vertDownActive = false;
      _travLeftActive = false;
      _travRightActive = false;
      _tripFwdActive = false;
      _tripRevActive = false;
    });
  }

  // ── Customization Mode ──────────────────────────────────────────────────────

  Future<void> _enterCustomizationMode() async {
    _resetLocalButtonStates();
    await context.read<CustomizationModeController>().enter();
  }

  void _reorderAxis({required AxisKind moved, required AxisKind target}) {
    final customCtrl = context.read<CustomizationModeController>();
    final draft = customCtrl.draft;
    final order = List<AxisKind>.from(draft.axisOrder);
    final fromIndex = order.indexOf(moved);
    final toIndex = order.indexOf(target);
    if (fromIndex == -1 || toIndex == -1 || fromIndex == toIndex) return;
    order.removeAt(fromIndex);
    order.insert(toIndex, moved);
    customCtrl.applyDraftChange(draft.copyWith(axisOrder: order));
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
        final controlsDisabled =
            controller.estopLatched || !controller.isConnected;
        final vertUpActive =
            _vertUpActive ||
            _externalVertState(controller, isUp: true) != ControlState.idle;
        final vertDownActive =
            _vertDownActive ||
            _externalVertState(controller, isUp: false) != ControlState.idle;
        final travLeftActive =
            _travLeftActive ||
            _externalTravState(controller, isLeft: true) != ControlState.idle;
        final travRightActive =
            _travRightActive ||
            _externalTravState(controller, isLeft: false) != ControlState.idle;
        final tripFwdActive =
            _tripFwdActive ||
            _externalTripState(controller, isForward: true) !=
                ControlState.idle;
        final tripRevActive =
            _tripRevActive ||
            _externalTripState(controller, isForward: false) !=
                ControlState.idle;
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
                    padding: metrics.bodyPadding,
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
                            child: SensorRow(a1: controller.a1, a2: controller.a2),
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
                        Expanded(
                          child: Column(
                            children: [
                              for (var i = 0; i < layoutCfg.axisOrder.length; i++) ...[
                                _axisSection(
                                  layoutCfg.axisOrder[i],
                                  isEditing: isEditing,
                                  card: _cardForAxis(
                                    layoutCfg.axisOrder[i],
                                    controller: controller,
                                    labels: labels,
                                    layoutCfg: layoutCfg,
                                    sizing: sizing,
                                    controlsDisabled: controlsDisabled,
                                    isEditing: isEditing,
                                    vertUpActive: vertUpActive,
                                    vertDownActive: vertDownActive,
                                    travLeftActive: travLeftActive,
                                    travRightActive: travRightActive,
                                    tripFwdActive: tripFwdActive,
                                    tripRevActive: tripRevActive,
                                  ),
                                ),
                                if (i != layoutCfg.axisOrder.length - 1)
                                  SizedBox(height: metrics.itemSpacing),
                              ],
                            ],
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

  Widget _cardForAxis(
    AxisKind kind, {
    required CraneController controller,
    required ControlLabelConfig labels,
    required ControlLayoutConfig layoutCfg,
    required ControlWidgetSizeConfig sizing,
    required bool controlsDisabled,
    required bool isEditing,
    required bool vertUpActive,
    required bool vertDownActive,
    required bool travLeftActive,
    required bool travRightActive,
    required bool tripFwdActive,
    required bool tripRevActive,
  }) {
    switch (kind) {
      case AxisKind.hoist:
        return _axisCard(
          label: 'HOIST',
          icon: Icons.swap_vert_rounded,
          color: AppColors.upColor,
          showDragHandle: isEditing,
          children: _hoistAxisContent(
            controller: controller,
            labels: labels,
            axisCfg: layoutCfg.axisConfigs.hoist,
            roleStyles: layoutCfg.roleStyles,
            controlsDisabled: controlsDisabled,
            upActive: vertUpActive,
            downActive: vertDownActive,
            isEditing: isEditing,
          ),
        );
      case AxisKind.traverse:
        return _axisCard(
          label: 'TRAVERSE',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.traverseColor,
          showDragHandle: isEditing,
          children: _traverseAxisContent(
            controller: controller,
            labels: labels,
            axisCfg: layoutCfg.axisConfigs.traverse,
            roleStyles: layoutCfg.roleStyles,
            controlsDisabled: controlsDisabled,
            leftActive: travLeftActive,
            rightActive: travRightActive,
            isEditing: isEditing,
          ),
        );
      case AxisKind.travel:
        return _axisCard(
          label: 'TRAVEL',
          icon: Icons.open_in_full_rounded,
          color: AppColors.travelColor,
          showDragHandle: isEditing,
          children: _travelAxisContent(
            controller: controller,
            labels: labels,
            axisCfg: layoutCfg.axisConfigs.travel,
            roleStyles: layoutCfg.roleStyles,
            controlsDisabled: controlsDisabled,
            forwardActive: tripFwdActive,
            reverseActive: tripRevActive,
            isEditing: isEditing,
          ),
        );
    }
  }

  // ── HOIST axis content ──────────────────────────────────────────────────────

  List<Widget> _hoistAxisContent({
    required CraneController controller,
    required ControlLabelConfig labels,
    required AxisControlConfig axisCfg,
    required RoleStyleConfig roleStyles,
    required bool controlsDisabled,
    required bool upActive,
    required bool downActive,
    required bool isEditing,
  }) {
    final upStyle = roleStyles.forRole(ControlRole.hoistUp);
    final downStyle = roleStyles.forRole(ControlRole.hoistDown);

    switch (axisCfg.widgetType) {
      case ControlWidgetType.pushButton:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () =>
                  ButtonEditSheet.showForRole(context, ControlRole.hoistUp),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: UpPushControlButton(
                  label: labels.upLabel,
                  isActive: upActive,
                  isDisabled: controlsDisabled || downActive,
                  isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                  colorOverride: upStyle.primaryColor,
                  colorOverrideLight: upStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _vertUpActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: true, state: state);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () =>
                  ButtonEditSheet.showForRole(context, ControlRole.hoistDown),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: DownPushControlButton(
                  label: labels.downLabel,
                  isActive: downActive,
                  isDisabled: controlsDisabled || upActive,
                  isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                  colorOverride: downStyle.primaryColor,
                  colorOverrideLight: downStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _vertDownActive = state != ControlState.idle);
                    controller.setHoistCommand(isUp: false, state: state);
                  },
                ),
              ),
            ),
          ),
        ];

      case ControlWidgetType.toggle:
        return [
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
                isActive: upActive,
                isDisabled: controlsDisabled || downActive,
                isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                style: upStyle,
                onCommandChanged: (state) {
                  setState(() => _vertUpActive = state != ControlState.idle);
                  controller.setHoistCommand(isUp: true, state: state);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () =>
                  ButtonEditSheet.showForRole(context, ControlRole.hoistDown),
              child: ToggleSwitchButton(
                label: labels.downLabel,
                icon: Icons.arrow_downward_rounded,
                activeColor: downStyle.resolvePrimary(AppColors.downColor),
                activeColorLight: downStyle.resolveActive(
                  AppColors.downColorLight,
                ),
                isActive: downActive,
                isDisabled: controlsDisabled || upActive,
                isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                style: downStyle,
                onCommandChanged: (state) {
                  setState(() => _vertDownActive = state != ControlState.idle);
                  controller.setHoistCommand(isUp: false, state: state);
                },
              ),
            ),
          ),
        ];

      case ControlWidgetType.sliderButton:
      case ControlWidgetType.joystick:
      case ControlWidgetType.rotary:
        return [
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
                isDisabled: controlsDisabled || downActive,
                onCommandChanged: (state) {
                  setState(() => _vertUpActive = state != ControlState.idle);
                  controller.setHoistCommand(isUp: true, state: state);
                },
                externalState: _externalVertState(controller, isUp: true),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () =>
                  ButtonEditSheet.showForRole(context, ControlRole.hoistDown),
              child: CraneSliderButton(
                label: labels.downLabel,
                icon: Icons.arrow_downward_rounded,
                isUp: false,
                axisColor: downStyle.primaryColor,
                isDisabled: controlsDisabled || upActive,
                onCommandChanged: (state) {
                  setState(() => _vertDownActive = state != ControlState.idle);
                  controller.setHoistCommand(isUp: false, state: state);
                },
                externalState: _externalVertState(controller, isUp: false),
              ),
            ),
          ),
        ];
    }
  }

  // ── TRAVERSE axis content ───────────────────────────────────────────────────

  List<Widget> _traverseAxisContent({
    required CraneController controller,
    required ControlLabelConfig labels,
    required AxisControlConfig axisCfg,
    required RoleStyleConfig roleStyles,
    required bool controlsDisabled,
    required bool leftActive,
    required bool rightActive,
    required bool isEditing,
  }) {
    final leftStyle = roleStyles.forRole(ControlRole.traverseLeft);
    final rightStyle = roleStyles.forRole(ControlRole.traverseRight);

    switch (axisCfg.widgetType) {
      case ControlWidgetType.pushButton:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.traverseLeft,
              ),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: LeftPushControlButton(
                  label: labels.leftLabel,
                  isActive: leftActive,
                  isDisabled: controlsDisabled || rightActive,
                  isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                  colorOverride: leftStyle.primaryColor,
                  colorOverrideLight: leftStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _travLeftActive = state != ControlState.idle);
                    controller.setTraverseCommand(isLeft: true, state: state);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.traverseRight,
              ),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: RightPushControlButton(
                  label: labels.rightLabel,
                  isActive: rightActive,
                  isDisabled: controlsDisabled || leftActive,
                  isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                  colorOverride: rightStyle.primaryColor,
                  colorOverrideLight: rightStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _travRightActive = state != ControlState.idle);
                    controller.setTraverseCommand(isLeft: false, state: state);
                  },
                ),
              ),
            ),
          ),
        ];

      case ControlWidgetType.toggle:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.traverseLeft,
              ),
              child: ToggleSwitchButton(
                label: labels.leftLabel,
                icon: Icons.arrow_back_rounded,
                activeColor: leftStyle.resolvePrimary(AppColors.traverseColor),
                activeColorLight: leftStyle.resolveActive(
                  AppColors.traverseColorLight,
                ),
                isActive: leftActive,
                isDisabled: controlsDisabled || rightActive,
                isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                style: leftStyle,
                onCommandChanged: (state) {
                  setState(() => _travLeftActive = state != ControlState.idle);
                  controller.setTraverseCommand(isLeft: true, state: state);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.traverseRight,
              ),
              child: ToggleSwitchButton(
                label: labels.rightLabel,
                icon: Icons.arrow_forward_rounded,
                activeColor: rightStyle.resolvePrimary(AppColors.traverseColor),
                activeColorLight: rightStyle.resolveActive(
                  AppColors.traverseColorLight,
                ),
                isActive: rightActive,
                isDisabled: controlsDisabled || leftActive,
                isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                style: rightStyle,
                onCommandChanged: (state) {
                  setState(() => _travRightActive = state != ControlState.idle);
                  controller.setTraverseCommand(isLeft: false, state: state);
                },
              ),
            ),
          ),
        ];

      case ControlWidgetType.sliderButton:
      case ControlWidgetType.joystick:
      case ControlWidgetType.rotary:
        // CrossTravelSlider renders both directions as one combined widget —
        // it has no per-direction color override hook (unlike CraneSliderButton),
        // so it's wrapped as a single axis-scoped edit target rather than two
        // per-role tiles.
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () =>
                  ButtonEditSheet.showForAxis(context, AxisKind.traverse),
              child: CrossTravelSlider(
                leftLabel: labels.leftLabel,
                rightLabel: labels.rightLabel,
                isDisabled: controlsDisabled,
                onCommandChanged:
                    ({required bool isLeft, required ControlState state}) {
                      setState(() {
                        _travLeftActive = isLeft && state != ControlState.idle;
                        _travRightActive =
                            !isLeft && state != ControlState.idle;
                      });
                      controller.setTraverseCommand(isLeft: isLeft, state: state);
                    },
              ),
            ),
          ),
        ];
    }
  }

  // ── TRAVEL axis content ─────────────────────────────────────────────────────

  List<Widget> _travelAxisContent({
    required CraneController controller,
    required ControlLabelConfig labels,
    required AxisControlConfig axisCfg,
    required RoleStyleConfig roleStyles,
    required bool controlsDisabled,
    required bool forwardActive,
    required bool reverseActive,
    required bool isEditing,
  }) {
    final forwardStyle = roleStyles.forRole(ControlRole.travelForward);
    final reverseStyle = roleStyles.forRole(ControlRole.travelReverse);

    switch (axisCfg.widgetType) {
      case ControlWidgetType.pushButton:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelForward,
              ),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: ForwardPushControlButton(
                  label: labels.forwardLabel,
                  isActive: forwardActive,
                  isDisabled: controlsDisabled || reverseActive,
                  isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                  colorOverride: forwardStyle.primaryColor,
                  colorOverrideLight: forwardStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _tripFwdActive = state != ControlState.idle);
                    controller.setTravelCommand(isForward: true, state: state);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelReverse,
              ),
              child: _pushButtonFrame(
                buttonHeight: axisCfg.resolvedHeight,
                child: ReversePushControlButton(
                  label: labels.reverseLabel,
                  isActive: reverseActive,
                  isDisabled: controlsDisabled || forwardActive,
                  isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                  colorOverride: reverseStyle.primaryColor,
                  colorOverrideLight: reverseStyle.activeColor,
                  onCommandChanged: (state) {
                    setState(() => _tripRevActive = state != ControlState.idle);
                    controller.setTravelCommand(isForward: false, state: state);
                  },
                ),
              ),
            ),
          ),
        ];

      case ControlWidgetType.toggle:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelForward,
              ),
              child: ToggleSwitchButton(
                label: labels.forwardLabel,
                icon: Icons.north_rounded,
                activeColor: forwardStyle.resolvePrimary(AppColors.travelColor),
                activeColorLight: forwardStyle.resolveActive(
                  AppColors.travelColorLight,
                ),
                isActive: forwardActive,
                isDisabled: controlsDisabled || reverseActive,
                isSpringReturn: axisCfg.wiringConfig.upIsSpringReturn,
                style: forwardStyle,
                onCommandChanged: (state) {
                  setState(() => _tripFwdActive = state != ControlState.idle);
                  controller.setTravelCommand(isForward: true, state: state);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelReverse,
              ),
              child: ToggleSwitchButton(
                label: labels.reverseLabel,
                icon: Icons.south_rounded,
                activeColor: reverseStyle.resolvePrimary(AppColors.travelColor),
                activeColorLight: reverseStyle.resolveActive(
                  AppColors.travelColorLight,
                ),
                isActive: reverseActive,
                isDisabled: controlsDisabled || forwardActive,
                isSpringReturn: axisCfg.wiringConfig.downIsSpringReturn,
                style: reverseStyle,
                onCommandChanged: (state) {
                  setState(() => _tripRevActive = state != ControlState.idle);
                  controller.setTravelCommand(isForward: false, state: state);
                },
              ),
            ),
          ),
        ];

      case ControlWidgetType.sliderButton:
      case ControlWidgetType.joystick:
      case ControlWidgetType.rotary:
        return [
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelForward,
              ),
              child: CraneSliderButton(
                label: labels.forwardLabel,
                icon: Icons.north_rounded,
                isUp: true,
                axisColor: forwardStyle.primaryColor ?? AppColors.travelColor,
                isDisabled: controlsDisabled || reverseActive,
                onCommandChanged: (state) {
                  setState(() => _tripFwdActive = state != ControlState.idle);
                  controller.setTravelCommand(isForward: true, state: state);
                },
                externalState: _externalTripState(controller, isForward: true),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableControlTile(
              isEditing: isEditing,
              onCustomize: () => ButtonEditSheet.showForRole(
                context,
                ControlRole.travelReverse,
              ),
              child: CraneSliderButton(
                label: labels.reverseLabel,
                icon: Icons.south_rounded,
                isUp: false,
                axisColor: reverseStyle.primaryColor ?? AppColors.travelColor,
                isDisabled: controlsDisabled || forwardActive,
                onCommandChanged: (state) {
                  setState(() => _tripRevActive = state != ControlState.idle);
                  controller.setTravelCommand(isForward: false, state: state);
                },
                externalState: _externalTripState(controller, isForward: false),
              ),
            ),
          ),
        ];
    }
  }

  Widget _pushButtonFrame({
    required double buttonHeight,
    required Widget child,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : buttonHeight;
        final resolvedHeight = buttonHeight > boundedHeight
            ? boundedHeight
            : buttonHeight;
        return Center(
          child: SizedBox(height: resolvedHeight, child: child),
        );
      },
    );
  }

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

  // ── Axis card / reorder wrapper ─────────────────────────────────────────────

  Widget _axisCard({
    required String label,
    required IconData icon,
    required Color color,
    required List<Widget> children,
    required bool showDragHandle,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(76)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: color,
                  letterSpacing: 1.2,
                ),
              ),
              if (showDragHandle) ...[
                const Spacer(),
                const Icon(
                  Icons.drag_indicator_rounded,
                  size: 12,
                  color: AppColors.darkTextSub,
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Expanded(child: Row(children: children)),
        ],
      ),
    );
  }

  /// Wraps an axis card with drag-to-reorder handling while Customization
  /// Mode is active. Reordering only changes child order within the Column —
  /// each axis keeps its Expanded flex-fill, so ControlLayoutMetrics'
  /// overflow-prevention guarantees are untouched.
  Widget _axisSection(
    AxisKind kind, {
    required bool isEditing,
    required Widget card,
  }) {
    if (!isEditing) return Expanded(child: card);
    return Expanded(
      child: DragTarget<AxisKind>(
        onWillAcceptWithDetails: (details) => details.data != kind,
        onAcceptWithDetails: (details) =>
            _reorderAxis(moved: details.data, target: kind),
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return LongPressDraggable<AxisKind>(
            data: kind,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 320,
                height: 130,
                child: Opacity(opacity: 0.85, child: card),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.25, child: card),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                border: isHovering
                    ? Border.all(color: AppColors.accent, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(12),
              ),
              child: card,
            ),
          );
        },
      ),
    );
  }
}
