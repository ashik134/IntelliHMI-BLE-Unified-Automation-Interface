import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:vibration/vibration.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_layout_metrics.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/controllers/layout_settings_controller.dart';

import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/live_led_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/safety_action_panel.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/sensor_row.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/status_bar_chip.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Rebuild-scope note
//
// The screen used to sit behind one Consumer3<CraneController,
// LayoutSettingsController, CustomizationModeController> wrapping the entire
// Scaffold body, so *any* notifyListeners() from any of the three controllers
// — including a BLE analog/status notification arriving many times a second
// — rebuilt the AppBar, LED row, sensor row, and status chip together. That
// was the biggest single rebuild-scope cost on this screen, and it ran
// concurrently with the BLE heartbeat timer on the same isolate, so heavy
// rebuild/paint work could delay heartbeat scheduling.
//
// Below, the layout selector recomputes only the committed ControlLayoutConfig
// for the connected PLC type — this changes rarely (settings edits, PLC type
// change) — and each live-data section (LEDs, sensor row, safety panel,
// status chip) is its own small widget with its own narrow Selector, so a BLE
// notification only rebuilds the specific section that actually changed.
//
// The customization workflow (draft editing, drag/resize, selection overlays,
// the control grid) has been removed pending a full redesign — see the
// Customize button in the AppBar, which is currently a no-op.
// ─────────────────────────────────────────────────────────────────────────────

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen>
    with WidgetsBindingObserver {
  CraneController? _craneController;

  bool _isBackNavigating = false;
  bool _isDismissingResetDialog = false;
  BuildContext? _resetDialogContext;

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

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Narrow selector #1: the screen "shape" — recomputed only when the
    // committed layout changes or the PLC type changes. Deliberately
    // excludes every live-telemetry field on CraneController (LEDs, sensors,
    // hoistState, RSSI, ...) so a BLE notification alone never retriggers
    // this selector or anything below it in the tree.
    return Selector<CraneController, PlcType>(
      selector: (_, controller) => controller.connectedPlcType,
      builder: (context, plcType, _) {
        return Selector<LayoutSettingsController, ControlLayoutConfig>(
          selector: (_, layoutCtrl) =>
              layoutCtrl.configFor(LayoutBucket.forPlcType(plcType)),
          builder: (context, layoutCfg, _) =>
              _buildScaffold(context, layoutCfg),
        );
      },
    );
  }

  Widget _buildScaffold(BuildContext context, ControlLayoutConfig layoutCfg) {
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

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: _onBackAttempted,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        resizeToAvoidBottomInset: false,
        appBar: _ControlAppBar(labels: labels),
        body: SafeArea(
          maintainBottomViewPadding: true,
          child: Padding(
            padding: metrics.bodyPadding,
            child: Column(
              children: [
                _SafetyPanelSection(
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
                  const _SensorSection(),
                  SizedBox(height: metrics.itemSpacing),
                ],
                if (metrics.showLEDs) ...[
                  const _LiveLedSection(),
                  SizedBox(height: metrics.itemSpacing),
                ],
                const Expanded(
                  child: RepaintBoundary(child: _MainControlsPlaceholder()),
                ),
                SizedBox(height: metrics.itemSpacing),
                const _StatusChipSection(),
                SizedBox(height: metrics.itemSpacing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ControlAppBar
// ─────────────────────────────────────────────────────────────────────────────

class _ControlAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ControlAppBar({required this.labels});

  final ControlLabelConfig labels;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 3);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      actionsPadding: const EdgeInsets.only(right: 8),
      automaticallyImplyLeading: false,
      backgroundColor: AppColors.appBarBg,
      flexibleSpace: const ControlAppBarGlow(),
      titleSpacing: NavigationToolbar.kMiddleSpacing,
      title: _DeviceTitle(labels: labels),
      actions: [
        IconButton(
          icon: const Icon(
            Icons.dashboard_customize_rounded,
            size: 20,
            color: AppColors.darkTextSub,
          ),
          tooltip: 'Customize Layout',
          onPressed: () {
            // TODO: Implement the redesigned customization workflow.
          },
        ),
        const _DisconnectButton(),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.appBarBanner,
            border: Border(
              bottom: BorderSide(color: AppColors.appBarBannerBorder),
            ),
          ),
        ),
      ),
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
    required this.onEStopTap,
    required this.onResetActivated,
  });

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
  const _LiveLedRowValues(this.estop, this.up, this.down, this.fast);

  final bool estop;
  final bool up;
  final bool down;
  final bool fast;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _LiveLedRowValues &&
          other.estop == estop &&
          other.up == up &&
          other.down == down &&
          other.fast == fast;

  @override
  int get hashCode => Object.hash(estop, up, down, fast);
}

class _LiveLedSection extends StatelessWidget {
  const _LiveLedSection();

  @override
  Widget build(BuildContext context) {
    final values = context.select<CraneController, _LiveLedRowValues>(
      (c) => _LiveLedRowValues(c.ledEstop, c.ledUp, c.ledDown, c.ledFast),
    );
    return RepaintBoundary(
      child: LiveLedRow(
        leds: [
          LedSpec(
            label: 'ESTOP',
            active: values.estop,
            color: AppColors.eStopColor,
            inactiveColor: AppColors.darkSuccess,
            pulseWhenInactive: true,
            // pin: 'R0_0',
          ),
          LedSpec(
            label: 'UP',
            active: values.up,
            color: AppColors.upColor,
            // pin: 'Q0.1',
          ),
          LedSpec(
            label: 'DOWN',
            active: values.down,
            color: AppColors.downColor,
            // pin: 'Q0.2',
          ),
          LedSpec(
            label: 'FAST',
            active: values.fast,
            color: AppColors.fastColor,
            // pin: 'Q0.3',
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
            : switch (controller.hoistState) {
                HoistState.idle => AppColors.idleColor,
                HoistState.upSlow => AppColors.upColor,
                HoistState.upFast => AppColors.fastColor,
                HoistState.downSlow => AppColors.downColor,
                HoistState.downFast => AppColors.fastColor,
              },
        label: controller.statusLabel,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MainControlsPlaceholder
//
// The customizable control grid (motion buttons, drag/resize, selection
// overlays) has been removed pending a full redesign of the customization
// workflow. This is a non-interactive placeholder only — it never sends a
// PLC command and holds no state.
// ─────────────────────────────────────────────────────────────────────────────

class _MainControlsPlaceholder extends StatelessWidget {
  const _MainControlsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.darkBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.widgets_outlined,
              size: 28,
              color: AppColors.darkTextMuted,
            ),
            SizedBox(height: 8),
            Text(
              'Controls area — pending redesign',
              style: TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
