import 'package:flutter/material.dart';
import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/widgets/shared/brand_widgets.dart';

class _StatusCardModel {
  const _StatusCardModel({
    required this.tone,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.loading = false,
    this.actions = const [],
  });

  final BrandTone tone;
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

    // The two routine states — scanning, and idle-ready — are already
    // spelled out by the console header (radar backdrop, SCAN/STOP control)
    // and by the devices panel (SCANNING badge, empty-state copy). Repeating
    // them here made the same sentence appear up to four times on one screen,
    // so the banner now shows only when it has something those don't say:
    // a fault, a permission to grant, or a connection in progress.
    if (status == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: BrandStatusBanner(
        icon: status.icon,
        title: status.title,
        message: status.subtitle,
        tone: status.tone,
        busy: status.loading,
        actions: status.actions,
      ),
    );
  }

  /// Returns null when the console header already conveys the state.
  _StatusCardModel? _resolveStatus(CraneController controller) {
    if (!controller.permissionsGranted) {
      return _StatusCardModel(
        tone: BrandTone.warning,
        icon: Icons.key_rounded,
        title: 'Permissions Required',
        subtitle: 'Bluetooth permissions are required to discover PLC devices.',
        actions: [
          _StatusActionButton(
            label: 'Open Settings',
            tone: BrandTone.warning,
            onTap: controller.openSettings,
          ),
          _StatusActionButton(
            label: 'Retry Permissions',
            tone: BrandTone.warning,
            outlined: true,
            onTap: controller.refreshPermissions,
          ),
        ],
      );
    }

    if (!controller.bluetoothReady) {
      return _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.bluetooth_disabled_rounded,
        title: 'Bluetooth Off',
        subtitle: 'Turn on Bluetooth to scan for ${BLEConstants.deviceName}.',
        actions: [
          _StatusActionButton(
            label: 'Enable Bluetooth',
            tone: BrandTone.violet,
            onTap: controller.enableBluetooth,
          ),
        ],
      );
    }

    // Carried by the header's live radar and STOP control.
    if (controller.isScanning) return null;

    if (controller.isConnecting) {
      return _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.bluetooth_searching_rounded,
        title: 'Connecting',
        subtitle: 'Linking to ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isDiscoveringServices) {
      return _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.settings_ethernet_rounded,
        title: 'Discovering Services',
        subtitle:
            'Discovering services on ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isConfiguringNotifications) {
      return const _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.notifications_active_rounded,
        title: 'Configuring Notifications',
        subtitle: 'Initializing communication channels...',
        loading: true,
      );
    }

    if (controller.isInitializingSafeState) {
      return const _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.shield_rounded,
        title: 'Initializing Safety State',
        subtitle: 'Applying safe PLC state...',
        loading: true,
      );
    }

    if (controller.isAwaitingAuthentication || controller.isAuthenticating) {
      return _StatusCardModel(
        tone: BrandTone.violet,
        icon: Icons.lock_outline_rounded,
        title: 'Preparing Authentication',
        subtitle:
            'Establishing secure session with ${controller.connectedDeviceName ?? "device"}...',
        loading: true,
      );
    }

    if (controller.isConnected) {
      return _StatusCardModel(
        tone: BrandTone.success,
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
        loading: true,
        tone: BrandTone.neutral,
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
        tone: isUnreachable ? BrandTone.warning : BrandTone.danger,
        icon: isUnreachable
            ? Icons.wifi_off_rounded
            : Icons.error_outline_rounded,
        title: isUnreachable ? 'Device Unreachable' : 'Connection Error',
        subtitle: msg,
      );
    }

    // Idle and ready: the header's SCAN button is the whole message.
    return null;
  }
}

class _StatusActionButton extends StatelessWidget {
  const _StatusActionButton({
    required this.label,
    required this.tone,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final BrandTone tone;
  final VoidCallback onTap;
  final bool outlined;

  Color get _color => switch (tone) {
    BrandTone.violet => AppColors.brandViolet,
    BrandTone.info => AppColors.brandInfo,
    BrandTone.warning => AppColors.brandWarning,
    BrandTone.success => AppColors.brandSuccess,
    BrandTone.danger => AppColors.brandDanger,
    BrandTone.neutral => AppColors.brandTextSub,
  };

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _color,
          side: BorderSide(color: _color.withAlpha(115)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
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
        backgroundColor: _color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppMetrics.radiusSm),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }
}
