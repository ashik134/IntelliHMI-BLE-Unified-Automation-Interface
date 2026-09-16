import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';

import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/control_exit_utils.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';

import 'package:rev_crane_control_ops/widgets/control_screen/control_screen_profile_sheet.dart';
import 'package:rev_crane_control_ops/widgets/control_screen/device_info_appbar.dart';
import 'package:rev_crane_control_ops/widgets/safety/circular_estop_control.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SafetyControlScreen
//
// The Safety Control Screen Profile: a dedicated circular E-Stop control and
// nothing else — no dynamic control grid, no layout editing. Reuses the same
// CraneController.triggerEStop()/resetEStop() the Standard control screens
// call (see plc14_control_screen.dart's _onEStopTap/_onResetEStopTap) so the
// actual PLC E-Stop write is identical; only the on-screen control and
// interaction (tap-to-trip, clockwise-swipe-to-reset) differ.
//
// The button's *displayed* state is a separate concern from that write path:
// it's driven by controller.reportedStatusCommand.estop — the PLC's own
// Status Characteristic echo of its actual E-STOP relay output — not by
// controller.estopLatched (what this app last commanded). The PLC pushes a
// status notification immediately after authentication, and
// CraneController resets reportedStatusCommand right as that authenticated
// transition fires (see the `authenticated` branch in
// _attachStreamsIfNeeded's stream listener), so this screen never shows a
// value left over from a previous session/PLC — only this connection's own
// PLC-reported truth, live.
// ─────────────────────────────────────────────────────────────────────────────

class SafetyControlScreen extends StatelessWidget {
  const SafetyControlScreen({super.key});

  Future<void> _onEStopTap(BuildContext context) async {
    final controller = context.read<CraneController>();
    await controller.triggerEStop();
    Vibration.vibrate(duration: 600, amplitude: 255);
    if (context.mounted) {
      // clearSnackBars (not showSnackBar alone) so a still-visible or queued
      // SnackBar from a previous E-Stop never leaks into this one — each
      // E-Stop press is guaranteed a fresh notification.
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Emergency Stop activated')),
            ],
          ),
          backgroundColor: AppColors.eStopColor,
        ),
      );
    }
  }

  Future<void> _onResetEStopTap(BuildContext context) async {
    final controller = context.read<CraneController>();
    if (controller.currentScreen != AppScreen.safetyControl ||
        !controller.isConnected) {
      return;
    }
    await controller.resetEStop();
    Vibration.vibrate(duration: 100);
    // Dismiss the "Emergency Stop activated" SnackBar immediately on reset
    // rather than leaving it to time out on its own — otherwise it (or a
    // queued duplicate) can still be showing at the next E-Stop.
    if (context.mounted) ScaffoldMessenger.of(context).clearSnackBars();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    // Source of truth for the displayed button — see the header comment.
    final estopActive = controller.reportedStatusCommand.estop;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        actionsPadding: const EdgeInsets.only(right: 8),
        automaticallyImplyLeading: false,
        backgroundColor: AppColors.appBarBg,
        flexibleSpace: const ControlAppBarGlow(),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        title: DeviceInfoAppBarTitle(
          deviceName: controller.connectedDeviceName ?? BLEConstants.deviceName,
          plcType: controller.connectedPlcType,
          rssi: controller.connectedDeviceRssi,
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.tune_rounded,
              size: 20,
              color: AppColors.darkTextMuted,
            ),
            tooltip: 'Configure Screen',
            onPressed: () => showControlScreenProfileSheet(context),
          ),
          const _DisconnectButton(),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = constraints.biggest.shortestSide;
              final diameter = (side * 0.6).clamp(180.0, 320.0);
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularEStopControl(
                      estopLatched: estopActive,
                      diameter: diameter,
                      resetEnabled: controller.isConnected,
                      onEStopTap: () => _onEStopTap(context),
                      onResetActivated: () => _onResetEStopTap(context),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      estopActive
                          ? 'Complete the clockwise swipe all the way around '
                                'to clear the lockout.'
                          : 'Tap the button to trip the emergency stop.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.darkTextSub,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DisconnectButton extends StatelessWidget {
  const _DisconnectButton();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();
    return IconButton.filledTonal(
      onPressed: () => confirmAndDisconnect(context, controller),
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
