import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';

class BleService {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<BleScanDevice>> _scanController =
      StreamController<List<BleScanDevice>>.broadcast();
  final StreamController<Map<String, int>> _analogController =
      StreamController<Map<String, int>>.broadcast();
  final StreamController<PlcOutputCommand> _statusController =
      StreamController<PlcOutputCommand>.broadcast();

  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;
  Stream<List<BleScanDevice>> get scanStream => _scanController.stream;
  Stream<Map<String, int>> get analogStream => _analogController.stream;
  Stream<PlcOutputCommand> get statusStream => _statusController.stream;

  BleConnectionState _snapshot = BleConnectionState.initial();
  BluetoothDevice? _device;
  BleScanDevice? _connectedDevice;

  BluetoothCharacteristic? _analogChar;
  BluetoothCharacteristic? _digitalChar;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _statusChar;

  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _analogSubscription;
  StreamSubscription<List<int>>? _authSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  bool _isDisposing = false;
  bool _scanContinue = false;
  bool _scanPaused = false;

  Timer? _pruneTimer;

  bool _connectCancelled = false;

  Completer<BleAuthOutcome>?
  _pendingAuthCompleter; // For tracking ongoing authentication attempts.

  void _emit(BleConnectionStatus status, {String? message}) {
    if (_isDisposing || _connectionController.isClosed) {
      return;
    }
    _snapshot = BleConnectionState(
      status: status,
      message: message,
      connectedDevice: _connectedDevice,
    );
    _connectionController.add(_snapshot);
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    _scanContinue = false;
    _scanPaused = false;
    await stopScan();
    _scanController.add(const []);
    _emit(BleConnectionStatus.scanning);

    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        final seen = <String>{};
        final devices = results
            .map(BleScanDevice.fromScanResult)
            .where(
              (d) =>
                  d.name.startsWith(BLEConstants.scanNamePrefix) ||
                  d.plcType != PlcType.unknown,
            )
            .where((d) => seen.add(d.id))
            .toList();
        debugPrint(
          'Scan update: ${devices.length} ${BLEConstants.deviceName} device(s) found',
        );
        _scanController.add(List.unmodifiable(devices));
      },
      onError: (e) {
        _emit(
          BleConnectionStatus.error,
          message: 'Scan error: ${e.toString()}',
        );
      },
    );

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    await FlutterBluePlus.isScanning.where((s) => !s).first;
    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    _emit(BleConnectionStatus.disconnected);
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    await stopScan();
    await disconnect(emitState: false);
    _emit(BleConnectionStatus.connecting);

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    var hasreachedConnectedState = false;

    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) {
        hasreachedConnectedState = true;
        _logger.i('Device connected: ${_connectedDevice?.name}');
        return;
      }
      if (state == BluetoothConnectionState.disconnected) {
        if (!hasreachedConnectedState) {
          _logger.d('Ignoring initial disconnected state before connect.');
          return;
        }
        _logger.e('Failed to connect to device: ${_connectedDevice?.name}');
        _handleDisconnect();
      }
    });
    _device!.cancelWhenDisconnected(_connStateSub!, delayed: true, next: true);

    try {
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
        license: License.commercial,
      );
      await _discoverServices();
      _emit(BleConnectionStatus.awaitingAuthentication);
    } catch (e) {
      _connectedDevice = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Connection failed: ${e.toString()}',
      );
      _logger.e('Connection failed: ${e.toString()}');
      return;
    }

    // Monitor for unexpected disconnection.
    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });
  }

  // Discover services and map characteristics.
  Future<void> _discoverServices() async {
    try {
      final services = await _device!.discoverServices();
      BluetoothCharacteristic? analog;
      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;
      _digitalChar = null;
      _authChar = null;
      _analogChar = null;
      _statusChar = null;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            BLEConstants.serviceUuid.toLowerCase()) {
          continue;
        }

        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == BLEConstants.digitalCharUuid.toLowerCase()) {
            digital = char;
          } else if (uuid == BLEConstants.analogCharUuid.toLowerCase()) {
            analog = char;
          } else if (uuid == BLEConstants.authCharUuid.toLowerCase()) {
            auth = char;
          } else if (uuid == BLEConstants.statusCharUuid.toLowerCase()) {
            status = char;
          }
        }
      }

      //
      if (digital == null || auth == null || analog == null || status == null) {
        await _device!.disconnect();
        _connectedDevice = null;
        _emit(
          BleConnectionStatus.error,
          message: 'PLC service not found on this device.',
        );
        return;
      }

      _analogChar = analog;
      _digitalChar = digital;
      _authChar = auth;
      _statusChar = status;

      await _analogChar!.setNotifyValue(true);
      await _authChar!.setNotifyValue(true);
      await _statusChar!.setNotifyValue(true);
      _analogSubscription = _analogChar!.onValueReceived.listen(
        _handleAnalogNotification,
      );
      _authSubscription = _authChar!.onValueReceived.listen(
        _handleAuthNotification,
      );
      _statusSubscription = _statusChar!.onValueReceived.listen(
        _handleStatusNotification,
      );

      _device!.cancelWhenDisconnected(_analogSubscription!, next: true);
      _device!.cancelWhenDisconnected(_authSubscription!, next: true);
      _device!.cancelWhenDisconnected(_statusSubscription!, next: true);
      _emit(BleConnectionStatus.awaitingAuthentication);
    } catch (e) {
      await _device!.disconnect();
      _connectedDevice = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Service discovery failed: ${e.toString()}',
      );
    }
  }

  Future<void> cancelConnecting() async {
    if (_snapshot.status != BleConnectionStatus.connecting) return;

    _connectCancelled = true;

    await _connStateSub?.cancel();
    _connStateSub = null;

    final device = _device;
    _device = null;
    _connectedDevice = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;

    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    _connectCancelled = false;
    _emit(BleConnectionStatus.disconnected);
  }

  Future<void> disconnect({bool emitState = true}) async {
    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;

    await _analogSubscription?.cancel();
    await _authSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _connStateSub?.cancel();
    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    _connStateSub = null;

    final device = _device;
    _device = null;
    _analogChar = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;

    if (device != null && device.isConnected) {
      await device.disconnect();
    }

    if (emitState) {
      _handleDisconnect();
    } else {
      _connectedDevice = null;
    }
  }

  void _handleDisconnect() {
    _device = null;
    _connectedDevice = null;
    _connStateSub?.cancel();
    _connStateSub = null;
    _analogChar = null;
    _authChar = null;
    _digitalChar = null;
    _statusChar = null;
    _analogSubscription?.cancel();
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    _analogController.add(const {'A1': 0, 'A2': 0});
    _statusController.add(PlcOutputCommand.idle());
    _emit(BleConnectionStatus.disconnected);
  }

  // ── Characteristic callbacks ───────────────────────────────────────────────

  // Keeps the last known values so single-channel updates don't zero out the other channel.
  final Map<String, int> _lastAnalog = {'A1': 0, 'A2': 0};

  void _handleAnalogNotification(List<int> bytes) {
    final payload = utf8.decode(bytes).trim();
    final parts = payload.split(',');

    try {
      final updated = Map<String, int>.from(_lastAnalog);
      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length != 2) {
          _logger.w('Unexpected analog token: $part');
          continue;
        }
        final key = kv[0].trim();
        final value = int.parse(kv[1].trim());
        if (updated.containsKey(key)) {
          updated[key] = value;
        } else {
          _logger.w('Unknown analog key: $key');
        }
      }
      _lastAnalog
        ..['A1'] = updated['A1']!
        ..['A2'] = updated['A2']!;
      _analogController.add(Map.unmodifiable(updated));
    } catch (error) {
      _logger.e('Analog parse error', error: error);
    }
  }

  void _handleStatusNotification(List<int> bytes) {
    final command = PlcOutputCommand.fromStatusNotification(bytes);
    _logger.i(
      'PLC status: estop=${command.estop} dir=${command.direction} speed=${command.speed}',
    );
    _statusController.add(command);
  }

  void _handleAuthNotification(List<int> bytes) {
    final payload = utf8.decode(bytes).trim();
    _logger.i('Auth notification: $payload');

    if (payload == BLEConstants.authRequest) {
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return;
    }

    if (payload == BLEConstants.authSuccess) {
      _emit(BleConnectionStatus.authenticated);
      _pendingAuthCompleter?.complete(BleAuthOutcome.success);
      _pendingAuthCompleter = null;
      return;
    }

    if (payload == BLEConstants.authFailed ||
        payload == BLEConstants.authTimeout) {
      _pendingAuthCompleter?.complete(
        payload == BLEConstants.authTimeout
            ? BleAuthOutcome.timedOut
            : BleAuthOutcome.failed,
      );
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);
    }
  }

  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
  }) async {
    if (_authChar == null) {
      throw StateError('Authentication characteristic is not ready.');
    }

    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = Completer<BleAuthOutcome>();
    // Capture the future NOW before the write, so a fast notification that
    // nulls out _pendingAuthCompleter during the await cannot cause a
    // null-check crash on line below.
    final authFuture = _pendingAuthCompleter!.future;
    _emit(BleConnectionStatus.authenticating);

    await _authChar!.write(
      utf8.encode('$email|$password'),
      withoutResponse: false,
    );

    try {
      return await authFuture.timeout(
        SafetyConstants.authReplyTimeout,
        onTimeout: () {
          _pendingAuthCompleter = null;
          _emit(
            BleConnectionStatus.awaitingAuthentication,
            message: 'PLC authentication timed out.',
          );
          return BleAuthOutcome.timedOut;
        },
      );
    } finally {
      if (_snapshot.status != BleConnectionStatus.authenticated &&
          _device != null &&
          _device!.isConnected &&
          _snapshot.status != BleConnectionStatus.error) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
    }
  }

  // ── Write helpers ──────────────────────────────────────────────────────────

  Future<void> writeDigital(List<int> bytes) async {
    if (_digitalChar == null) return;
    await _digitalChar!.write(bytes, withoutResponse: false);
  }

  Future<void> writeAuth(List<int> bytes) async {
    if (_authChar == null) return;
    await _authChar!.write(bytes);
  }

  // ── Bluetooth adapter ──────────────────────────────────────────────────────

  Future<void> ensureBluetoothReady() async {
    if (!kIsWeb && Platform.isAndroid) {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  void dispose() {
    stopScan();
    disconnect();
    _connectionController.close();
    _scanController.close();
    _analogController.close();
    _statusController.close();
  }
}
