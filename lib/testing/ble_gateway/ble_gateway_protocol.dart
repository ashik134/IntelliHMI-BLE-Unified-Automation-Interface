import 'dart:convert';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';

class BleGatewayProtocol {
  BleGatewayProtocol._();

  static const int defaultPort = 8787;

  static const String scan = 'scan';
  static const String stopScan = 'stopScan';
  static const String connect = 'connect';
  static const String disconnect = 'disconnect';
  static const String digitalWrite = 'digitalWrite';
  static const String write = 'write';
  static const String read = 'read';

  static const String scanResult = 'scanResult';
  static const String bleStatus = 'bleStatus';
  static const String notification = 'notification';
  static const String readResult = 'readResult';
  static const String error = 'error';
  static const String log = 'log';

  static String encodeBytes(List<int> bytes) => base64Encode(bytes);

  static List<int> decodeBytes(Object? value, {Object? encoding}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return const [];
    }

    final mode = encoding?.toString().toLowerCase();
    if (mode == 'hex' || (mode == null && _looksLikeHex(text))) {
      return _decodeHex(text);
    }
    return base64Decode(text);
  }

  static String statusToWire(BleConnectionStatus status) {
    return status.name;
  }

  static BleConnectionStatus statusFromWire(String? value) {
    return BleConnectionStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => BleConnectionStatus.error,
    );
  }

  static String plcTypeToWire(PlcType type) => type.name;

  static PlcType plcTypeFromWire(String? value) {
    return PlcType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => PlcType.unknown,
    );
  }

  static bool _looksLikeHex(String text) {
    if (text.isEmpty || text.length.isOdd) {
      return false;
    }
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(text);
  }

  static List<int> _decodeHex(String text) {
    final bytes = <int>[];
    for (var i = 0; i < text.length; i += 2) {
      bytes.add(int.parse(text.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
