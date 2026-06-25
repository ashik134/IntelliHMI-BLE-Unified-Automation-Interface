import 'package:rev_crane_control_ops/models/ble_scan_device.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,

  discoveringServices,
  configuringNotifications,
  initializingSafeState,

  connected,
  awaitingAuthentication,
  authenticating,
  authenticated,
  error,
}

enum BleAuthOutcome { success, failed, timedOut, untrusted}

class BleConnectionState {
  const BleConnectionState({
    required this.status,
    this.message,
    this.connectedDevice,
  });

  final BleConnectionStatus status;
  final String? message;
  final BleScanDevice? connectedDevice;

  factory BleConnectionState.initial() {
    return const BleConnectionState(status: BleConnectionStatus.disconnected);
  }
}
