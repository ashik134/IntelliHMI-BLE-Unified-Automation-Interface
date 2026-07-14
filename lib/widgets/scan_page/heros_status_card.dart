import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';

class _StatusCardModel {
  const _StatusCardModel({
    required this.primary,
    required this.background,
    required this.border,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.actions = const [],
  });

  final Color primary;
  final Color background;
  final Color border;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool loading;
  final List<Widget> actions;
}

class HeroStatusCard extends StatelessWidget {
  const HeroStatusCard({super.key, required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final status = _resolveStatus(controller);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: status.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: status.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: status.loading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: status.primary,
                        ),
                      )
                    : Icon(status.icon, color: status.primary, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.title,
                      style: TextStyle(
                        color: status.primary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.subtitle,
                      style: const TextStyle(
                        color: AppColors.connTextSub,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: status.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          if (status.actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: status.actions),
          ],
        ],
      ),
    );
  }

  _StatusCardModel _resolveStatus(CraneController controller) {
    if (!controller.permissionsGranted) {
      return _StatusCardModel(
        primary: AppColors.connWarning,
        background: AppColors.warningBg,
        border: AppColors.warningBorder,
        icon: Icons.key_rounded,
        title: 'Permissions Required',
        subtitle: 'Bluetooth permissions are required to discover PLC devices.',
        actions: [
          _StatusActionButton(
            label: 'Open Settings',
            color: AppColors.connWarning,
            onTap: controller.openSettings,
          ),
          _StatusActionButton(
            label: 'Retry Permissions',
            color: AppColors.connWarning,
            outlined: true,
            onTap: controller.refreshPermissions,
          ),
        ],
      );
    }

    if (!controller.bluetoothReady) {
      return _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Bluetooth Off',
        subtitle: 'Turn on Bluetooth to scan for ${BLEConstants.deviceName}.',
        actions: [
          _StatusActionButton(
            label: 'Enable Bluetooth',
            color: AppColors.scanning,
            onTap: controller.enableBluetooth,
          ),
        ],
      );
    }

    if (controller.isScanning) {
      return const _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.radar_rounded,
        title: 'Scanning',
        subtitle:
            'Searching for ${BLEConstants.deviceName} controllers nearby.',
        loading: true,
      );
    }

    if (controller.isConnecting) {
      return _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.bluetooth_searching_rounded,
        title: 'Connecting',
        subtitle: 'Linking to ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isDiscoveringServices) {
      return _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.settings_ethernet_rounded,
        title: 'Discovering Services',
        subtitle:
            'Discovering services on ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isConfiguringNotifications) {
      return const _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.notifications_active_rounded,
        title: 'Configuring Notifications',
        subtitle: 'Initializing communication channels...',
        loading: true,
      );
    }

    if (controller.isInitializingSafeState) {
      return const _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.shield_rounded,
        title: 'Initializing Safety State',
        subtitle: 'Applying safe PLC state...',
        loading: true,
      );
    }

    if (controller.isAwaitingAuthentication || controller.isAuthenticating) {
      return _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.lock_outline_rounded,
        title: 'Preparing Authentication',
        subtitle:
            'Establishing secure session with ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isConnected) {
      return _StatusCardModel(
        primary: AppColors.connected,
        background: AppColors.connectedBg,
        border: AppColors.connectedBorder,
        icon: Icons.bluetooth_connected_rounded,
        title: 'Session Active',
        subtitle:
            'Connected to ${controller.connectedDeviceName ?? BLEConstants.deviceName}. Continue to authentication.',
      );
    }

    if (controller.isCancellingConnection) {
      return _StatusCardModel(
        icon: Icons.close_rounded,
        title: 'Cancelling Connection',
        subtitle:
            'Aborting connection to ${controller.cancellingDevice?.name ?? "device"}...',
        border: AppColors.neutralBorder,
        loading: true,
        primary: AppColors.connTextSub,
        background: AppColors.neutralBg,
      );
    }

    if (controller.connectionState.status == BleConnectionStatus.error) {
      final msg =
          controller.connectionState.message ?? 'An unexpected error occurred.';
      final msgLower = msg.toLowerCase();
      final bool isUnreachable =
          msgLower.contains('unreachable') ||
          msgLower.contains('timed out') ||
          msgLower.contains('timeout') ||
          msgLower.contains('out of range') ||
          msgLower.contains('offline');
      return _StatusCardModel(
        primary: isUnreachable ? AppColors.connWarning : AppColors.error,
        background: isUnreachable ? AppColors.warningBg : AppColors.errorBg,
        border: isUnreachable ? AppColors.warningBorder : AppColors.errorBorder,
        icon: isUnreachable
            ? Icons.wifi_off_rounded
            : Icons.error_outline_rounded,
        title: isUnreachable ? 'Device Unreachable' : 'Connection Error',
        subtitle: msg,
      );
    }

    return const _StatusCardModel(
      primary: AppColors.neutral,
      background: AppColors.neutralBg,
      border: AppColors.neutralBorder,
      icon: Icons.bluetooth_searching_rounded,
      title: 'Ready to Scan',
      subtitle: 'Tap scan to discover available crane controllers.',
    );
  }
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.45)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      );
    }

    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
