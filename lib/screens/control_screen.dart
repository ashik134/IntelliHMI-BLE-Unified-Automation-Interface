import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rev6_crane_control_ops/widgets/estop_swipe_button.dart';
import 'package:vibration/vibration.dart';

import 'package:rev6_crane_control_ops/controllers/layout_settings_controller.dart';
import 'package:rev6_crane_control_ops/models/control_layout_config.dart';
import 'package:rev6_crane_control_ops/utils/constants.dart';
import 'package:rev6_crane_control_ops/widgets/crane_slider_button.dart';
import 'package:rev6_crane_control_ops/controllers/crane_controllers.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  // late final Animation<double> _pulseAnim;
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    // _pulseAnim = Tween<double>(begin: 0.3, end: 1.0).animate(
    //   CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    // );
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
    if (controller.currentScreen != AppScreen.control ||
        controller.isDisconnected) {
      _dismissResetDialogIfVisible();
    }
    if (controller.isDisconnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(controller.errorMessage ?? 'Disconnected from PLC14'),
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
    final confirmed = await _showResetDialog(controller);
    if (confirmed && mounted) {
      await controller.resetEStop();
      Vibration.vibrate(duration: 100);
    }
  }

  Future<bool> _showResetDialog(CraneController controller) async {
    if (!mounted || _isResetDialogVisible) return false;
    if (controller.currentScreen != AppScreen.control ||
        !controller.isConnected) {
      return false;
    }

    _isResetDialogVisible = true;
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          _resetDialogContext = dialogContext;
          return _ResetEStopDialog(controller: controller);
        },
      );
      return result ?? false;
    } finally {
      _isResetDialogVisible = false;
      _isDismissingResetDialog = false;
      _resetDialogContext = null;
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

        final screenTitle = labels.screenTitle.isNotEmpty
            ? labels.screenTitle
            : (controller.connectedDeviceName ?? BLEConstants.deviceName);

        return Scaffold(
          backgroundColor: AppColors.background,
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
                    color: AppColors.textPrimary,
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
                  color: AppColors.textSecondary,
                ),
                tooltip: 'Disconnect',
                onPressed: controller.disconnect,
              ),
            ],
          ),
          body: SafeArea(
            maintainBottomViewPadding: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Column(
                children: [
                  controller.estopLatched
                      ? _buildResetSection(labels.resetEstopLabel)
                      : _buildEStopButton(
                          height: sizing.resolvedEstopHeight,
                          instructionLabel: labels.estopSwipeInstruction,
                        ),
                  const SizedBox(height: 6),
                  if (arrangement.showSensorRow) ...[
                    _sensorRow(controller),
                    const SizedBox(height: 6),
                  ],
                  if (arrangement.showLiveLEDs) ...[
                    _liveLEDs(controller),
                    const SizedBox(height: 6),
                  ],
                  // ── Hoist controls
                  SizedBox(
                    height: sizing.resolvedHoistHeight,
                    child: Row(
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
                            externalState: switch (controller.hoistState) {
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
                            externalState: switch (controller.hoistState) {
                              HoistState.downSlow => ControlState.slow,
                              HoistState.downFast => ControlState.fast,
                              _ => ControlState.idle,
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ── Status bar
                  _buildStatusBar(controller),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _liveLEDs(CraneController controller) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
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
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 8,
            color: active ? color : AppColors.textMuted,
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
          border: Border.all(color: AppColors.border),
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
                      color: AppColors.textSecondary,
                      fontSize: 8,
                    ),
                  ),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
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
  }) {
    return EStopSwipeButton(
      onActivated: _onEStopTap,
      buttonHeight: height,
      instructionLabel: instructionLabel,
    );
  }

  // ── ESTOP active → Reset section ────────────────────────────────────────────

  Widget _buildResetSection(String resetLabel) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
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
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: AppColors.eStopColor,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 18,
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
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _onResetEStopTap,
            icon: const Icon(Icons.lock_open_rounded, size: 16),
            label: Text(
              '$resetLabel — Password Required',
              style: const TextStyle(fontSize: 12, letterSpacing: 0.5),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.eStopColorLight,
              side: const BorderSide(color: AppColors.eStopColorLight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ResetEStopDialog extends StatefulWidget {
  final CraneController controller;

  const _ResetEStopDialog({required this.controller});

  @override
  State<_ResetEStopDialog> createState() => _ResetEStopDialogState();
}

class _ResetEStopDialogState extends State<_ResetEStopDialog> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscure = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(
        children: [
          Icon(Icons.lock_reset, color: AppColors.eStopColorLight, size: 22),
          SizedBox(width: 10),
          Text(
            'Reset Emergency Stop',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter your password to unlock crane controls.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.eStopColor.withAlpha(31),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.eStopColor.withAlpha(102)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppColors.eStopColorLight,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.eStopColorLight,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            decoration: BoxDecoration(
              color: AppColors.panelAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: TextField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Password',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                prefixIcon: const Icon(
                  Icons.lock_outlined,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (widget.controller.verifyLocalPassword(
              _passwordController.text,
            )) {
              Navigator.pop(context, true);
              return;
            }
            setState(() => _errorMessage = 'Incorrect password.');
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.upColor,
            foregroundColor: Colors.white,
          ),
          child: const Text('UNLOCK'),
        ),
      ],
    );
  }
}
