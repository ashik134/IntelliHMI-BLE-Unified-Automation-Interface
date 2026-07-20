import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';

abstract class BleTransport {
  bool get requiresLocalBluetooth;

  String get readinessLabel;

  Stream<bool> get readyStream;

  Stream<BleConnectionState> get connectionStream;

  Stream<List<BleScanDevice>> get scanStream;

  Stream<Map<String, int>> get analogStream;

  Stream<PlcOutputCommand> get statusStream;

  Future<bool> checkReady();

  Future<void> ensureBluetoothReady();

  Future<void> startScan();

  Future<void> pauseScan();

  Future<void> resumeScan();

  Future<void> stopScan();

  Future<void> connect(BleScanDevice scanDevice);

  Future<void> cancelConnecting();

  Future<void> disconnect({bool emitState = true});

  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
    required String deviceId,
  });

  Future<void> writeDigital(List<int> bytes);

  Future<void> writeAuth(List<int> bytes);

  void dispose();
}
