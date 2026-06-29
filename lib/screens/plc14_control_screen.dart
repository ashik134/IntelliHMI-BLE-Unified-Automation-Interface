import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/widgets/estop_swipe_button.dart';
import 'package:rev_crane_control_ops/widgets/crane_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/push_control_button.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnim;
  CraneController? _craneController;

  // ── Mutual-exclusion: only one hoist direction active at a time ────────────
  bool _upActive = false;
  bool _downActive = false;
  bool _isResetDialogVisible = false;
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
    _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
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
    _pulseController.dispose();
    _craneController?.removeListener(_onControllerChange);
    WidgetsBinding.instance.removeObserver(this);
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

  // void resetLocalButtonStates() {
  //   setState(() {
  //     _upState = ControlState.idle;
  //     _downState = ControlState.idle;
  //   });
  // }

  // ── E-Stop ──────────────────────────────────────────────────────────────────

  Future<void> _onEStopTap() async {
    // resetLocalButtonStates();
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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer2<CraneController, LayoutSettingsController>(
      builder: (ctx, controller, layoutCtrl, _) {
        final layoutCfg = layoutCtrl.config;
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

        return Scaffold(
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
            actions: [
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
                  _buildSafetyActionPanel(
                    controller: controller,
                    compact: metrics.isCompact,
                    height: metrics.estopHeight,
                    labels: labels,
                  ),
                  SizedBox(height: metrics.itemSpacing),
                  if (metrics.showSensorRow) ...[
                    _sensorRow(controller),
                    SizedBox(height: metrics.itemSpacing),
                  ],
                  if (metrics.showLEDs) ...[
                    _liveLEDs(controller),
                    SizedBox(height: metrics.itemSpacing),
                  ],
                  // ── Hoist controls – Expanded fills all remaining space
                  // (prevents overflow on compact / landscape screens).
                  Expanded(
                    child: layoutCfg.widgetType == ControlWidgetType.pushButton
                        ? PushControlGroup(
                            pushConfig: layoutCfg.pushConfig,
                            upLabel: labels.upLabel,
                            downLabel: labels.downLabel,
                            isDisabled:
                                controller.estopLatched ||
                                !controller.isConnected,
                            upActive:
                                controller.hoistState == HoistState.upSlow,
                            downActive:
                                controller.hoistState == HoistState.downSlow,
                            onUpChanged: (state) {
                              setState(() {
                                _upActive = state != ControlState.idle;
                              });
                              controller.setHoistCommand(
                                isUp: true,
                                state: state,
                              );
                            },
                            onDownChanged: (state) {
                              setState(() {
                                _downActive = state != ControlState.idle;
                              });
                              controller.setHoistCommand(
                                isUp: false,
                                state: state,
                              );
                            },
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: CraneSliderButton(
                                  label: labels.upLabel,
                                  icon: Icons.arrow_upward_rounded,
                                  isUp: true,
                                  // Disabled when e-stop is active, disconnected,
                                  // OR the DOWN button is currently active (mutual exclusion).
                                  isDisabled:
                                      controller.estopLatched ||
                                      !controller.isConnected ||
                                      _downActive,
                                  onCommandChanged: (state) {
                                    setState(() {
                                      _upActive = state != ControlState.idle;
                                    });
                                    controller.setHoistCommand(
                                      isUp: true,
                                      state: state,
                                    );
                                  },
                                  externalState:
                                      switch (controller.hoistState) {
                                        HoistState.upSlow => ControlState.slow,
                                        HoistState.upFast => ControlState.fast,
                                        _ => ControlState.idle,
                                      },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CraneSliderButton(
                                  label: labels.downLabel,
                                  icon: Icons.arrow_downward_rounded,
                                  isUp: false,
                                  // Disabled when e-stop is active, disconnected,
                                  // OR the UP button is currently active (mutual exclusion).
                                  isDisabled:
                                      controller.estopLatched ||
                                      !controller.isConnected ||
                                      _upActive,
                                  onCommandChanged: (state) {
                                    setState(() {
                                      _downActive = state != ControlState.idle;
                                    });
                                    controller.setHoistCommand(
                                      isUp: false,
                                      state: state,
                                    );
                                  },
                                  externalState: switch (controller
                                      .hoistState) {
                                    HoistState.downSlow => ControlState.slow,
                                    HoistState.downFast => ControlState.fast,
                                    _ => ControlState.idle,
                                  },
                                ),
                              ),
                            ],
                          ),
                  ),

                  SizedBox(height: metrics.itemSpacing),

                  // ── Status bar
                  _buildStatusBar(controller),

                  SizedBox(height: metrics.itemSpacing),
                ],
              ),
            ),
          ),
        );
      },
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
              instructionLabel: labels.estopSwipeInstruction,
              compact: compact,
              height: height,
            ),
    );
  }

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
          _ledIndicator(
            label: 'ESTOP',
            active: controller.ledEstop,
            color: AppColors.eStopColor,
            pinName: 'R0_0',
          ),
          _ledIndicator(
            label: 'UP',
            active: controller.ledUp,
            color: AppColors.upColor,
            pinName: 'Q0.1',
          ),
          _ledIndicator(
            label: 'DOWN',
            active: controller.ledDown,
            color: AppColors.downColor,
            pinName: 'Q0.2',
          ),
          _ledIndicator(
            label: 'FAST',
            active: controller.ledFast,
            color: AppColors.fastColor,
            pinName: 'Q0.3',
          ),
        ],
      ),
    );
  }

  Widget _ledIndicator({
    required String label,
    required Color color,
    required bool active,
    required String pinName,
  }) {
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: active ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 300),
          builder: (context, value, child) {
            return Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: active ? color : Colors.grey.shade300,
                shape: BoxShape.circle,

                boxShadow: active
                    ? [
                        BoxShadow(
                          color: color.withAlpha(153),
                          blurRadius: (4 * value),
                          spreadRadius: 1,
                        ),
                      ]
                    : [],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          pinName,
          style: const TextStyle(
            fontSize: 6,
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextSub,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: active ? color : AppColors.darkTextMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _sensorRow(CraneController controller) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _sensorCard(
          label: 'Load 1',
          tag: 'A1',
          value: controller.a1,
          color: AppColors.upColor,
        ),
        const SizedBox(width: 8),
        _sensorCard(
          label: 'Load 2',
          tag: 'A2',
          value: controller.a2,
          color: AppColors.downColor,
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
    return Expanded(
      child: Container(
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
      ),
    );
  }

  // ── Status bar ──────────────────────────────────────────────────────────────

  Widget _buildStatusBar(CraneController controller) {
    final Color c = controller.estopLatched
        ? AppColors.eStopColor
        : switch (controller.hoistState) {
            HoistState.idle => AppColors.idleColor,
            HoistState.upSlow => AppColors.upColor,
            HoistState.upFast => AppColors.fastColor,
            HoistState.downSlow => AppColors.downColor,
            HoistState.downFast => AppColors.fastColor,
          };

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
          Text(
            controller.statusLabel,
            style: TextStyle(
              color: c,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  // ── E-Stop button ───────────────────────────────────────────────────────────

  Widget _buildEStopButton({
    required double height,
    required String instructionLabel,
    required bool compact,
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

  // ── ESTOP active → Reset section ────────────────────────────────────────────

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
              Container(
                width: compact ? 28 : 32,
                height: compact ? 28 : 32,
                decoration: const BoxDecoration(
                  color: AppColors.eStopColor,
                  shape: BoxShape.circle,
                ),
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
