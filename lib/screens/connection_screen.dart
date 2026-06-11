import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:rev_crane_control_ops/controllers/crane_controllers.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/services/ble_service.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  CraneController? _controller;
  String? _lastShownError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<CraneController>();
    if (_controller != controller) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller;
      _controller!.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final error = _controller?.errorMessage;
    if (error != null && error != _lastShownError) {
      _lastShownError = error;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 5),
              content: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<CraneController>();

    return Scaffold(
      backgroundColor: AppColors.connBg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        titleSpacing: 16,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CRANE CONTROL',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: AppColors.connText,
              ),
            ),
            Text(
              'PLC14 BLE Remote',
              style: TextStyle(fontSize: 11, color: AppColors.connTextMuted),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.precision_manufacturing_rounded,
                color: AppColors.connPrimary,
                size: 22,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: controller.isInitializing
          ? const _InitializingView()
          : Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF7F9FC), AppColors.connBg],
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      _HeroStatusCard(controller: controller),
                      const SizedBox(height: 12),
                      _QuickStatusRow(controller: controller),
                      const SizedBox(height: 12),
                      Expanded(child: _DevicesPanel(controller: controller)),
                      const SizedBox(height: 12),
                      _BottomActionBar(controller: controller),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  const _HeroStatusCard({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final status = _resolveStatus(controller);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
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
        title: 'Permissions Needed',
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

    if (controller.connectionState.status == BleConnectionStatus.error) {
      return _StatusCardModel(
        primary: AppColors.error,
        background: AppColors.errorBg,
        border: AppColors.errorBorder,
        icon: Icons.error_outline_rounded,
        title: 'Connection Error',
        subtitle:
            controller.connectionState.message ??
            'An unexpected error occurred.',
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
        actions: [
          _StatusActionButton(
            label: 'Disconnect',
            color: AppColors.error,
            outlined: true,
            onTap: controller.disconnect,
          ),
        ],
      );
    }

    if (controller.isConnecting) {
      return _StatusCardModel(
        primary: AppColors.scanning,
        background: AppColors.scanningBg,
        border: AppColors.scanningBorder,
        icon: Icons.bluetooth_searching_rounded,
        title: 'Connecting',
        subtitle:
            'Linking to ${controller.connectionState.connectedDevice?.name ?? "device"}...',
        loading: true,
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

class _QuickStatusRow extends StatelessWidget {
  const _QuickStatusRow({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniStatCard(
            label: 'Devices',
            value: controller.isConnected
                ? '1'
                : controller.isConnecting
                ? '...'
                : '${controller.devices.length}',
            icon: Icons.memory_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Bluetooth',
            value: controller.bluetoothReady ? 'ON' : 'OFF',
            icon: controller.bluetoothReady
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_disabled_rounded,
            valueColor: controller.bluetoothReady
                ? AppColors.connected
                : AppColors.error,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MiniStatCard(
            label: 'Permission',
            value: controller.permissionsGranted ? 'OK' : 'WAIT',
            icon: controller.permissionsGranted
                ? Icons.verified_rounded
                : Icons.key_off_rounded,
            valueColor: controller.permissionsGranted
                ? AppColors.connected
                : AppColors.connWarning,
          ),
        ),
      ],
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor = AppColors.connPrimary,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    // Calculate size based on screen width
    final screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth = screenWidth < 600 ? 110 : 140;
    final double cardHeight = screenWidth < 600 ? 65 : 75;

    return Container(
      width: cardWidth,
      height: cardHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.connTextMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.connTextMuted,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    color: valueColor,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
class _DevicesPanel extends StatelessWidget {
  const _DevicesPanel({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Text(
                  'NEARBY DEVICES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppColors.connTextMuted,
                  ),
                ),
                const Spacer(),
                Text(
                  _countLabel(controller),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.connTextMuted,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildBody(),
            ),
          ),
        ],
      ),
    );
  }

  String _countLabel(CraneController controller) {
    if (controller.isConnected) return '1 connected';
    if (controller.isConnecting) return 'connecting...';
    return '${controller.devices.length} found';
  }

  Widget _buildBody() {
    if (controller.isConnected || controller.isConnecting) {
      final device = controller.connectionState.connectedDevice;
      if (device == null) {
        return const _EmptyDeviceState(
          key: ValueKey('empty-connected'),
          scanning: false,
        );
      }
      return ListView(
        key: const ValueKey('connected-list'),
        padding: const EdgeInsets.all(14),
        children: [
          _ConnectedDeviceCard(
            device: device,
            isConnecting: controller.isConnecting,
            onDisconnect: controller.disconnect,
          ),
        ],
      );
    }

    if (controller.devices.isEmpty) {
      return _EmptyDeviceState(
        key: const ValueKey('empty-idle'),
        scanning: controller.isScanning,
      );
    }

    return ListView.separated(
      key: const ValueKey('devices-list'),
      padding: const EdgeInsets.all(14),
      itemCount: controller.devices.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _AvailableDeviceCard(
        device: controller.devices[i],
        connecting: controller.isConnecting,
        onConnect: () => controller.connectToDevice(controller.devices[i]),
      ),
    );
  }
}

class _AvailableDeviceCard extends StatelessWidget {
  const _AvailableDeviceCard({
    required this.device,
    required this.connecting,
    required this.onConnect,
  });

  final BleScanDevice device;
  final bool connecting;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.connSurfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.connBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.developer_board_rounded,
              color: AppColors.connPrimary,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.connText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  device.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.connTextMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                _SignalPill(rssi: device.rssi, label: device.signalLabel),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: FilledButton(
              onPressed: connecting ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.connPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.neutral,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
              child: connecting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Text('CONNECT'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  const _SignalPill({required this.rssi, required this.label});

  final int rssi;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tone = rssi >= -68
        ? AppColors.connected
        : rssi >= -80
        ? AppColors.connWarning
        : AppColors.error;
    final barValue = (((rssi + 100) / 50).clamp(0.05, 1.0)).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$rssi dBm  |  $label',
              style: TextStyle(
                color: tone,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: LinearProgressIndicator(
              value: barValue,
              minHeight: 4,
              borderRadius: BorderRadius.circular(4),
              backgroundColor: tone.withValues(alpha: 0.22),
              valueColor: AlwaysStoppedAnimation<Color>(tone),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectedDeviceCard extends StatelessWidget {
  const _ConnectedDeviceCard({
    required this.device,
    required this.isConnecting,
    required this.onDisconnect,
  });

  final BleScanDevice device;
  final bool isConnecting;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.connectedBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.connectedBorder),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.connectedBorder),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.connected,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.connText,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.connTextMuted,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              if (isConnecting)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.scanning,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.connectedBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 8,
                        color: AppColors.connected,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          color: AppColors.connected,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (!isConnecting) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: const Icon(Icons.bluetooth_disabled_rounded, size: 16),
                label: const Text('DISCONNECT'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyDeviceState extends StatelessWidget {
  const _EmptyDeviceState({required this.scanning, super.key});

  final bool scanning;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.connBorder),
              ),
              child: Icon(
                scanning ? Icons.radar_rounded : Icons.bluetooth_rounded,
                color: scanning
                    ? AppColors.scanning
                    : AppColors.connTextMuted,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              scanning ? 'Scanning for Devices...' : 'No Controllers Found',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.connText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              scanning
                  ? 'Looking for ${BLEConstants.deviceName} nearby.'
                  : 'Power on the PLC14 controller and keep it in BLE range.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.connTextMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.controller});

  final CraneController controller;

  @override
  Widget build(BuildContext context) {
    final scanning = controller.isScanning;
    final connecting = controller.isConnecting;
    final connected = controller.isConnected;

    final canScan =
        !scanning &&
        !connecting &&
        !connected &&
        controller.bluetoothReady &&
        controller.permissionsGranted;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.connBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: scanning
            ? OutlinedButton.icon(
                onPressed: controller.stopScan,
                icon: const Icon(
                  Icons.stop_circle_outlined,
                  color: AppColors.error,
                ),
                label: const Text(
                  'STOP SCANNING',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.error),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              )
            : FilledButton.icon(
                onPressed: canScan ? controller.scanForDevices : null,
                icon: Icon(
                  connected
                      ? Icons.check_circle_outline_rounded
                      : Icons.bluetooth_searching_rounded,
                ),
                label: Text(
                  connected ? 'SESSION ACTIVE' : 'SCAN FOR DEVICES',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: connected
                      ? AppColors.connected
                      : AppColors.connPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.neutral,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
      ),
    );
  }
}

class _InitializingView extends StatelessWidget {
  const _InitializingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF7F9FC), AppColors.connBg],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.connPrimary,
              strokeWidth: 2.5,
            ),
            SizedBox(height: 18),
            Text(
              'Preparing BLE Runtime',
              style: TextStyle(
                color: AppColors.connText,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'Checking Bluetooth and permissions...',
              style: TextStyle(
                color: AppColors.connTextMuted,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
