import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleScanDevice {
  const BleScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.device,
  });

  final String id;
  final String name;
  final int rssi;
  final BluetoothDevice device;

  factory BleScanDevice.fromScanResult(ScanResult result) {
    final advertisedName = result.advertisementData.advName.trim();
    final platformName = result.device.platformName.trim();

    return BleScanDevice(
      id: result.device.remoteId.toString(),
      name: advertisedName.isNotEmpty
          ? advertisedName
          : (platformName.isNotEmpty ? platformName : 'Unnamed PLC'),
      rssi: result.rssi,
      device: result.device,
    );
  }

  String get signalLabel {
    if (rssi >= -55) {
      return 'Excellent';
    }
    if (rssi >= -68) {
      return 'Strong';
    }
    if (rssi >= -80) {
      return 'Fair';
    }
    return 'Weak';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is BleScanDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
