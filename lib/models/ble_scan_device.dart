import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rev_crane_control_ops/core/constants/ble_constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';

class BleScanDevice {
  BleScanDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.device,
    DateTime? lastSeenAt,
    this.frozenStatus,
    this.plcType = PlcType.unknown,
  }) : lastSeenAt = lastSeenAt ?? DateTime.now();

  final String id;
  final String name;
  final int rssi;
  final PlcType plcType;
  final BluetoothDevice device;
  final DateTime lastSeenAt;

  DeviceStaleStatus? frozenStatus;
  static const Duration staleThreshold = Duration(seconds: 10);
  static const Duration expireThreshold = Duration(seconds: 15);

  Duration get silenceDuration => DateTime.now().difference(lastSeenAt);
  bool get isStale => staleStatus != DeviceStaleStatus.active;

  DeviceStaleStatus get staleStatus {
    if (frozenStatus != null) return frozenStatus!;
    final age = silenceDuration;
    if (age < staleThreshold) return DeviceStaleStatus.active;
    if (age < expireThreshold) return DeviceStaleStatus.stale;
    return DeviceStaleStatus.expired;
  }

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

      // Deliberately not result.timeStamp: that's the platform's own
      // advertisement clock (and can replay a cached advertisement stamped
      // well before this scan session started), while staleStatus below
      // compares against DateTime.now(). Stamping with our own clock at the
      // moment we actually process the result keeps both sides of that
      // comparison in the same clock domain, so a genuinely fresh
      // advertisement is never misread as stale.
      plcType: _parsePlcType(result),
    );
  }

  /// Returns `true` when the device's Manufacturer Data starts with
  /// [BLEConstants.manufacturerDataPrefix] (case-insensitive).
  /// All byte sequences that are not printable ASCII are silently skipped.
  static bool matchesPlcFilter(ScanResult result) {
    try {
      final mfrData = result.advertisementData.manufacturerData;
      for (final entry in mfrData.entries) {
        final str = _decodeMfrEntry(entry.key, entry.value);
        if (str != null &&
            str.toLowerCase().startsWith(
              BLEConstants.manufacturerDataPrefix.toLowerCase(),
            )) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static PlcType _parsePlcType(ScanResult result) {
    try {
      final mfrData = result.advertisementData.manufacturerData;
      for (final entry in mfrData.entries) {
        final str = _decodeMfrEntry(entry.key, entry.value);
        if (str == null) continue;
        final type = PlcType.fromString(str);
        if (type != PlcType.unknown) return type;
      }
    } catch (_) {}
    return PlcType.unknown;
  }

  /// Reconstructs the full BLE manufacturer data string from the company-ID
  /// key and raw payload bytes.  Returns `null` when the bytes are not
  /// printable ASCII (i.e. not a text-encoded identifier).
  static String? _decodeMfrEntry(int companyId, List<int> payload) {
    final bytes = [companyId & 0xFF, (companyId >> 8) & 0xFF, ...payload];
    if (bytes.isEmpty || !bytes.every((b) => b >= 0x20 && b <= 0x7E)) {
      return null;
    }
    return String.fromCharCodes(bytes);
  }

  BleScanDevice copyWith({
    int? rssi,
    DateTime? lastSeenAt,
    DeviceStaleStatus? frozenStatus,
    bool clearFrozen = false,
    PlcType? plcType,
  }) {
    return BleScanDevice(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      device: device,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      frozenStatus: clearFrozen ? null : (frozenStatus ?? this.frozenStatus),
      plcType: plcType ?? this.plcType,
    );
  }

  String get signalLabel {
    if (rssi >= -55) return 'Excellent';
    if (rssi >= -68) return 'Strong';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BleScanDevice && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
