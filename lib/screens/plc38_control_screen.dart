import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/widgets/estop_swipe_button.dart';
import 'package:rev_crane_control_ops/widgets/cross_travel_slider.dart';
import 'package:rev_crane_control_ops/widgets/crane_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/push_control_button.dart';
import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/screens/settings/control_customization_screen.dart';

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
  bool _isResetDialogVisible = false;
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
    if (!mounted || !_isResetDialogVisible || _isDismissingResetDialog) return;
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

  Future<void> _onEStopTap() async {
    setState(() {
      _vertUpActive = false;
      _vertDownActive = false;
      _travLeftActive = false;
      _travRightActive = false;
      _tripFwdActive = false;
      _tripRevActive = false;
    });
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

  // Future<bool> _showResetDialog(CraneController controller) async {
  //   if (!mounted || _isResetDialogVisible) return false;
  //   if (controller.currentScreen != AppScreen.plc38Control ||
  //       !controller.isConnected) {
  //     return false;
  //   }
  //   _isResetDialogVisible = true;
  //   try {
  //     final result = await showDialog<bool>(
  //       context: context,
  //       barrierDismissible: false,
  //       builder: (dialogContext) {
  //         _resetDialogContext = dialogContext;
  //         return _Plc38ResetDialog(controller: controller);
  //       },
  //     );
  //     return result ?? false;
  //   } finally {
  //     _isResetDialogVisible = false;
  //     _isDismissingResetDialog = false;
  //     _resetDialogContext = null;
  //   }
  // }

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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer2<CraneController, LayoutSettingsController>(
      builder: (ctx, controller, layoutCtrl, _) {
        final layoutCfg = layoutCtrl.config;
        final labels = layoutCfg.labelConfig;
        final sizing = layoutCfg.sizeConfig;
        final arrangement = layoutCfg.arrangementConfig;
        final usePushButtons =
            layoutCfg.widgetType == ControlWidgetType.pushButton;
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

        return PopScope(
          canPop: false,
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
                  screenTitle,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
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
            actions: [
              IconButton(
                icon: const Icon(
                  Icons.tune_rounded,
                  size: 20,
                  color: AppColors.darkTextSub,
                ),
                tooltip: 'Customise',
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ControlCustomizationScreen(),
                  ),
                ),
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
                  _buildSafetyActionPanel(
                    controller: controller,
                    compact: metrics.isCompact,
                    height: metrics.estopHeight,
                    labels: labels,
                  ),
                  SizedBox(height: metrics.itemSpacing),

                  // ── Sensor row ────────────────────────────────────────────────
                  if (metrics.showSensorRow) ...[
                    _sensorRow(controller),
                    SizedBox(height: metrics.itemSpacing),
                  ],

                  // ── PLC38 10-output LED indicators ──────────────────────
                  if (metrics.showLEDs) ...[
                    _liveLEDs(controller),
                    SizedBox(height: metrics.itemSpacing),
                  ],

                  // ── Axis controls (3 rows) ──────────────────────────────
                  Expanded(
                    child: Column(
                      children: [
                        _axisRow(
                          label: 'HOIST',
                          icon: Icons.swap_vert_rounded,
                          color: AppColors.upColor,
                          children: [
                            if (usePushButtons)
                              ..._verticalPushButtons(
                                controller: controller,
                                labels: labels,
                                pushConfig: layoutCfg.pushConfig,
                                controlsDisabled: controlsDisabled,
                                buttonHeight: sizing.resolvedHoistHeight,
                                upActive: vertUpActive,
                                downActive: vertDownActive,
                              )
                            else
                              ..._verticalSliders(
                                controller: controller,
                                labels: labels,
                                controlsDisabled: controlsDisabled,
                                upActive: vertUpActive,
                                downActive: vertDownActive,
                              ),
                          ],
                        ),
                        SizedBox(height: metrics.itemSpacing),

                        _axisRow(
                          label: 'TRAVERSE',
                          icon: Icons.swap_horiz_rounded,
                          color: AppColors.traverseColor,
                          children: [
                            if (usePushButtons)
                              ..._traversePushButtons(
                                controller: controller,
                                labels: labels,
                                pushConfig: layoutCfg.pushConfig,
                                controlsDisabled: controlsDisabled,
                                buttonHeight: sizing.resolvedHoistHeight,
                                leftActive: travLeftActive,
                                rightActive: travRightActive,
                              )
                            else
                              Expanded(
                                child: CrossTravelSlider(
                                  leftLabel: labels.leftLabel,
                                  rightLabel: labels.rightLabel,
                                  isDisabled: controlsDisabled,
                                  onCommandChanged:
                                      ({
                                        required bool isLeft,
                                        required ControlState state,
                                      }) {
                                        setState(() {
                                          _travLeftActive =
                                              isLeft &&
                                              state != ControlState.idle;
                                          _travRightActive =
                                              !isLeft &&
                                              state != ControlState.idle;
                                        });
                                        controller.setTraverseCommand(
                                          isLeft: isLeft,
                                          state: state,
                                        );
                                      },
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: metrics.itemSpacing),

                        _axisRow(
                          label: 'TRAVEL',
                          icon: Icons.open_in_full_rounded,
                          color: AppColors.travelColor,
                          children: [
                            if (usePushButtons)
                              ..._travelPushButtons(
                                controller: controller,
                                labels: labels,
                                pushConfig: layoutCfg.pushConfig,
                                controlsDisabled: controlsDisabled,
                                buttonHeight: sizing.resolvedHoistHeight,
                                forwardActive: tripFwdActive,
                                reverseActive: tripRevActive,
                              )
                            else
                              ..._travelSliders(
                                controller: controller,
                                labels: labels,
                                controlsDisabled: controlsDisabled,
                                forwardActive: tripFwdActive,
                                reverseActive: tripRevActive,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: metrics.itemSpacing),

                  // ── Status bar ──────────────────────────────────────────────────────
                  _buildStatusBar(controller),
                  SizedBox(height: metrics.itemSpacing),
                ],
              ),
            ),
          ),
        ),
        );
      },
    );
  }

  // ── External state helpers ─────────────────────────────────────────────────

  List<Widget> _verticalSliders({
    required CraneController controller,
    required ControlLabelConfig labels,
    required bool controlsDisabled,
    required bool upActive,
    required bool downActive,
  }) {
    return [
      Expanded(
        child: CraneSliderButton(
          label: labels.upLabel,
          icon: Icons.arrow_upward_rounded,
          isUp: true,
          isDisabled: controlsDisabled || downActive,
          onCommandChanged: (state) {
            setState(() => _vertUpActive = state != ControlState.idle);
            controller.setHoistCommand(isUp: true, state: state);
          },
          externalState: _externalVertState(controller, isUp: true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: CraneSliderButton(
          label: labels.downLabel,
          icon: Icons.arrow_downward_rounded,
          isUp: false,
          isDisabled: controlsDisabled || upActive,
          onCommandChanged: (state) {
            setState(() => _vertDownActive = state != ControlState.idle);
            controller.setHoistCommand(isUp: false, state: state);
          },
          externalState: _externalVertState(controller, isUp: false),
        ),
      ),
    ];
  }

  List<Widget> _verticalPushButtons({
    required CraneController controller,
    required ControlLabelConfig labels,
    required PushControlConfig pushConfig,
    required bool controlsDisabled,
    required double buttonHeight,
    required bool upActive,
    required bool downActive,
  }) {
    return [
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: UpPushControlButton(
            label: labels.upLabel,
            isActive: upActive,
            isDisabled: controlsDisabled || downActive,
            isSpringReturn: pushConfig.wiringConfig.upIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _vertUpActive = state != ControlState.idle);
              controller.setHoistCommand(isUp: true, state: state);
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: DownPushControlButton(
            label: labels.downLabel,
            isActive: downActive,
            isDisabled: controlsDisabled || upActive,
            isSpringReturn: pushConfig.wiringConfig.downIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _vertDownActive = state != ControlState.idle);
              controller.setHoistCommand(isUp: false, state: state);
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _traversePushButtons({
    required CraneController controller,
    required ControlLabelConfig labels,
    required PushControlConfig pushConfig,
    required bool controlsDisabled,
    required double buttonHeight,
    required bool leftActive,
    required bool rightActive,
  }) {
    return [
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: LeftPushControlButton(
            label: labels.leftLabel,
            isActive: leftActive,
            isDisabled: controlsDisabled || rightActive,
            isSpringReturn: pushConfig.wiringConfig.upIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _travLeftActive = state != ControlState.idle);
              controller.setTraverseCommand(isLeft: true, state: state);
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: RightPushControlButton(
            label: labels.rightLabel,
            isActive: rightActive,
            isDisabled: controlsDisabled || leftActive,
            isSpringReturn: pushConfig.wiringConfig.downIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _travRightActive = state != ControlState.idle);
              controller.setTraverseCommand(isLeft: false, state: state);
            },
          ),
        ),
      ),
    ];
  }

  List<Widget> _travelSliders({
    required CraneController controller,
    required ControlLabelConfig labels,
    required bool controlsDisabled,
    required bool forwardActive,
    required bool reverseActive,
  }) {
    return [
      Expanded(
        child: CraneSliderButton(
          label: labels.forwardLabel,
          icon: Icons.north_rounded,
          isUp: true,
          axisColor: AppColors.travelColor,
          isDisabled: controlsDisabled || reverseActive,
          onCommandChanged: (state) {
            setState(() => _tripFwdActive = state != ControlState.idle);
            controller.setTravelCommand(isForward: true, state: state);
          },
          externalState: _externalTripState(controller, isForward: true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: CraneSliderButton(
          label: labels.reverseLabel,
          icon: Icons.south_rounded,
          isUp: false,
          axisColor: AppColors.travelColor,
          isDisabled: controlsDisabled || forwardActive,
          onCommandChanged: (state) {
            setState(() => _tripRevActive = state != ControlState.idle);
            controller.setTravelCommand(isForward: false, state: state);
          },
          externalState: _externalTripState(controller, isForward: false),
        ),
      ),
    ];
  }

  List<Widget> _travelPushButtons({
    required CraneController controller,
    required ControlLabelConfig labels,
    required PushControlConfig pushConfig,
    required bool controlsDisabled,
    required double buttonHeight,
    required bool forwardActive,
    required bool reverseActive,
  }) {
    return [
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: ForwardPushControlButton(
            label: labels.forwardLabel,
            isActive: forwardActive,
            isDisabled: controlsDisabled || reverseActive,
            isSpringReturn: pushConfig.wiringConfig.upIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _tripFwdActive = state != ControlState.idle);
              controller.setTravelCommand(isForward: true, state: state);
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _pushButtonFrame(
          buttonHeight: buttonHeight,
          child: ReversePushControlButton(
            label: labels.reverseLabel,
            isActive: reverseActive,
            isDisabled: controlsDisabled || forwardActive,
            isSpringReturn: pushConfig.wiringConfig.downIsSpringReturn,
            onCommandChanged: (state) {
              setState(() => _tripRevActive = state != ControlState.idle);
              controller.setTravelCommand(isForward: false, state: state);
            },
          ),
        ),
      ),
    ];
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

  // ── Axis row wrapper ────────────────────────────────────────────────────────

  Widget _axisRow({
    required String label,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Expanded(
      child: Container(
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
              ],
            ),
            const SizedBox(height: 2),
            Expanded(child: Row(children: children)),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyActionPanel({
    required CraneController controller,
    required bool compact,
    required double height,
    required ControlLabelConfig labels,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: double.infinity,
      child: controller.estopLatched
          ? _buildResetSection(labels.resetEstopLabel, compact: compact)
          : _buildEStopButton(
              compact: compact,
              height: height,
              instructionLabel: labels.estopSwipeInstruction,
            ),
    );
  }

  Widget _buildEStopButton({
    required double height,
    required bool compact,
    required String instructionLabel,
  }) {
    return Material(
      // Wrap with Material for ripple effect
      color: Colors.transparent,
      child: InkWell(
        // Use InkWell instead of GestureDetector
        onTap: _onEStopTap,
        borderRadius: BorderRadius.circular(14),
        splashColor: Colors.white.withAlpha(50),
        highlightColor: Colors.white.withAlpha(20),
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: compact ? 100 : 100),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6B0000), AppColors.eStopColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: AppColors.eStopColor.withAlpha(100),
                blurRadius: 14,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: compact ? 32 : 34,
                height: compact ? 32 : 34,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(31),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withAlpha(64),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.power_settings_new,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'STOP',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  Text(
                    'Tap to stop all crane operations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 10-output LED indicator row ─────────────────────────────────────────────

  Widget _liveLEDs(CraneController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _led('ESTOP', controller.ledEstop, AppColors.eStopColor, 'Q_ES'),
          _led('UP', controller.ledUp, AppColors.upColor, 'Q0.1'),
          _led('DN', controller.ledDown, AppColors.downColor, 'Q0.2'),
          _led('FU', controller.ledFast, AppColors.fastColor, 'Q0.3'),
          _led('LT', controller.ledLeft, AppColors.traverseColor, 'Q0.4'),
          _led('RT', controller.ledRight, AppColors.traverseColor, 'Q0.5'),
          _led('FL', controller.ledFastLr, AppColors.fastColor, 'Q0.6'),
          _led('FW', controller.ledForward, AppColors.travelColor, 'Q0.7'),
          _led('RV', controller.ledReverse, AppColors.travelColor, 'Q0.8'),
          _led('FB', controller.ledFastFb, AppColors.fastColor, 'Q0.9'),
        ],
      ),
    );
  }

  Widget _led(String label, bool active, Color color, String pin) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, _) {
            return Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? color : Colors.grey.shade600,
                shape: BoxShape.circle,
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withAlpha(153),
                          blurRadius: 4 * value,
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Text(
          pin,
          style: const TextStyle(
            fontSize: 5.5,
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextSub,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 7,
            color: active ? color : AppColors.darkTextMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // ── Sensor row ──────────────────────────────────────────────────────────────

  Widget _sensorRow(CraneController controller) {
    return Row(
      children: [
        Expanded(
          child: _sensorCard(
            label: 'Load 1',
            tag: 'A1',
            value: controller.a1,
            color: AppColors.upColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _sensorCard(
            label: 'Load 2',
            tag: 'A2',
            value: controller.a2,
            color: AppColors.downColor,
          ),
        ),
      ],
    );
  }

  Widget _sensorCard({
    required String label,
    required String tag,
    required int value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.darkTextSub,
                    fontSize: 8,
                  ),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.darkText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Status bar ──────────────────────────────────────────────────────────────

  Widget _buildStatusBar(CraneController controller) {
    final Color c = controller.estopLatched
        ? AppColors.eStopColor
        : controller.activeCommand.isIdle
        ? AppColors.idleColor
        : AppColors.upColorLight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: c.withAlpha(31),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withAlpha(128)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.activeCommand.statusLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── E-Stop button ───────────────────────────────────────────────────────────

  // ── Reset section ───────────────────────────────────────────────────────────

  Widget _buildResetSection(String resetLabel, {bool compact = false}) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 8 : 10),
          decoration: BoxDecoration(
            color: AppColors.eStopColor.withAlpha(31),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.eStopColor.withAlpha(153),
              width: 2,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: compact ? 13 : 16,
                backgroundColor: AppColors.eStopColor,
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: compact ? 15 : 18,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EMERGENCY STOP ACTIVE',
                      style: TextStyle(
                        color: AppColors.eStopColorLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      'All crane controls are locked',
                      style: TextStyle(
                        color: AppColors.darkTextSub,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        EStopSwipeButton(
          onActivated: () {
            _onResetEStopTap();
          },
          instructionLabel: 'SWIPE TO RESET E-STOP',
          instructionSubtitle: 'Slide right to clear emergency lockout',
        ),
      ],
    );
  }
}

// // ── Reset E-Stop dialog ─────────────────────────────────────────────────────

// class _Plc38ResetDialog extends StatefulWidget {
//   final CraneController controller;

//   const _Plc38ResetDialog({required this.controller});

//   @override
//   State<_Plc38ResetDialog> createState() => _Plc38ResetDialogState();
// }

// class _Plc38ResetDialogState extends State<_Plc38ResetDialog> {
//   final TextEditingController _pwCtrl = TextEditingController();
//   bool _obscure = true;
//   String? _errorMessage;

//   @override
//   void dispose() {
//     _pwCtrl.dispose();
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     return AlertDialog(
//       scrollable: true,
//       backgroundColor: AppColors.panel,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//       title: const Row(
//         children: [
//           Icon(Icons.lock_reset, color: AppColors.eStopColorLight, size: 22),
//           SizedBox(width: 10),
//           Text(
//             'Reset Emergency Stop',
//             style: TextStyle(color: AppColors.darkText, fontSize: 17),
//           ),
//         ],
//       ),
//       content: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text(
//             'Enter your password to unlock crane controls.',
//             style: TextStyle(color: AppColors.darkTextSub, fontSize: 13),
//           ),
//           const SizedBox(height: 16),
//           if (_errorMessage != null) ...[
//             Container(
//               padding: const EdgeInsets.all(10),
//               decoration: BoxDecoration(
//                 color: AppColors.eStopColor.withAlpha(31),
//                 borderRadius: BorderRadius.circular(8),
//                 border:
//                     Border.all(color: AppColors.eStopColor.withAlpha(102)),
//               ),
//               child: Row(
//                 children: [
//                   const Icon(Icons.error_outline,
//                       color: AppColors.eStopColorLight, size: 16),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       _errorMessage!,
//                       style: const TextStyle(
//                           color: AppColors.eStopColorLight, fontSize: 12),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 12),
//           ],
//           TextField(
//             controller: _pwCtrl,
//             obscureText: _obscure,
//             autofocus: true,
//             style: const TextStyle(color: AppColors.darkText),
//             decoration: InputDecoration(
//               labelText: 'Password',
//               labelStyle: const TextStyle(color: AppColors.darkTextSub),
//               filled: true,
//               fillColor: AppColors.panelAlt,
//               border: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(10),
//                 borderSide:
//                     const BorderSide(color: AppColors.darkBorder),
//               ),
//               enabledBorder: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(10),
//                 borderSide:
//                     const BorderSide(color: AppColors.darkBorder),
//               ),
//               suffixIcon: IconButton(
//                 icon: Icon(
//                   _obscure ? Icons.visibility_off : Icons.visibility,
//                   color: AppColors.darkTextSub,
//                   size: 18,
//                 ),
//                 onPressed: () => setState(() => _obscure = !_obscure),
//               ),
//             ),
//           ),
//         ],
//       ),
//       actions: [
//         TextButton(
//           onPressed: () => Navigator.of(context).pop(false),
//           child: const Text('Cancel',
//               style: TextStyle(color: AppColors.darkTextSub)),
//         ),
//         ElevatedButton(
//           onPressed: () {
//             final ok =
//                 widget.controller.verifyLocalPassword(_pwCtrl.text);
//             if (ok) {
//               Navigator.of(context).pop(true);
//             } else {
//               setState(
//                   () => _errorMessage = 'Incorrect password. Try again.');
//             }
//           },
//           style: ElevatedButton.styleFrom(
//             backgroundColor: AppColors.eStopColorLight,
//             foregroundColor: Colors.white,
//             shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(10)),
//           ),
//           child: const Text('Unlock'),
//         ),
//       ],
//     );
//   }
// }
