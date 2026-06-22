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

  final Map<String, BleScanDevice> _deviceCache = {};

  DateTime? _scanDeadline;
  Timer? _pruneTimer;
  static const Duration _deviceExpireTimeout = Duration(seconds: 20);
  static const Duration _pruneInterval = Duration(seconds: 3);

  bool _connectCancelled = false;
  bool _sessionAuthenticated = false;
  bool _digitalCharWriteNoResponse = false;

  static const Duration _scanBurstDuration = Duration(seconds: 6);
  static const Duration _scanPauseDuration = Duration(milliseconds: 1500);
  static const Duration _maxScanDuration = Duration(minutes: 3);

  Completer<BleAuthOutcome>? _pendingAuthCompleter;

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
    _pruneTimer?.cancel;
    _pruneTimer = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    _deviceCache.clear();
    _scanDeadline = DateTime.now().add(_maxScanDuration);
    await _runScanSession();
  }

  // ── Run Scan Burst Section ───────────────────────────────────────────────────────────────

  Future<void> _runScanSession() async {
    _unfreezeCache();
    _emit(BleConnectionStatus.scanning);
    _scanContinue = true;

    if (_deviceCache.isNotEmpty) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(_pruneInterval, (_) => _pruneStaleDevices());

    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        bool changed = false;

        for (final result in results) {
          if (!BleScanDevice.matchesPlcFilter(result)) continue;

          final device = BleScanDevice.fromScanResult(result);
          final existing = _deviceCache[device.id];

          if (existing == null) {
            _deviceCache[device.id] = device;
            changed = true;
          } else if (existing.rssi != device.rssi || existing.isStale) {
            _deviceCache[device.id] = device;
            changed = true;
          } else {
            _deviceCache[device.id] = existing.copyWith(
              lastSeenAt: device.lastSeenAt,
            );
          }
        }

        if (changed) {
          debugPrint(
            'Scan update: ${_deviceCache.length} ${BLEConstants.manufacturerDataPrefix}* device(s) in cache',
          );
          _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
        }
      },
      onError: (e) {
        _emit(
          BleConnectionStatus.error,
          message: 'Scan error: ${e.toString()}',
        );
      },
    );

    while (_scanContinue && !_isDisposing) {
      final remaining = _scanDeadline!.difference(DateTime.now());
      if (remaining.inSeconds < 1) break;

      final burst = remaining < _scanBurstDuration
          ? remaining
          : _scanBurstDuration;

      try {
        await FlutterBluePlus.startScan(
          timeout: burst,
          androidScanMode: AndroidScanMode.balanced,
        );
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (_) {
        break;
      }
      if (!_scanContinue || _isDisposing) break;
      await Future.delayed(_scanPauseDuration);
    }

    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _freezeCache();

    if (!_scanPaused) {
      _scanDeadline = null;
      if (_snapshot.status == BleConnectionStatus.scanning) {
        _emit(BleConnectionStatus.disconnected);
      }
    }
  }

  // ── Stop Scanning ───────────────────────────────────────────────────────────────

  Future<void> stopScan() async {
    _scanContinue = false;
    _scanPaused = false;
    _scanDeadline = null;
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    _freezeCache();
    if (_snapshot.status == BleConnectionStatus.scanning) {
      _emit(BleConnectionStatus.disconnected);
    }
  }

  // ── Cache freeze ───────────────────────────────────────────────────────────────

  void _freezeCache({bool forceEmit = false}) {
    _pruneTimer?.cancel();
    _pruneTimer = null;
    if (_deviceCache.isEmpty) return;
    bool changed = false;
    for (final id in _deviceCache.keys.toList()) {
      final d = _deviceCache[id]!;
      if (d.frozenStatus == null) {
        _deviceCache[id] = d.copyWith(frozenStatus: DeviceStaleStatus.active);
        changed = true;
      }
    }
    if (changed || forceEmit) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }
  }

  // ── Uncache freeze  ───────────────────────────────────────────────────────────────

  void _unfreezeCache() {
    if (_deviceCache.isEmpty) return;
    final now = DateTime.now();
    for (final id in _deviceCache.keys.toList()) {
      _deviceCache[id] = _deviceCache[id]!.copyWith(
        lastSeenAt: now,
        clearFrozen: true,
      );
    }
  }

  // ──Remove the Stale Devices ───────────────────────────────────────────────────────────────

  void _pruneStaleDevices() {
    final now = DateTime.now();

    final expiredIds = _deviceCache.entries
        .where(
          (e) =>
              e.value.frozenStatus == null &&
              now.difference(e.value.lastSeenAt) > _deviceExpireTimeout,
        )
        .map((e) => e.key)
        .toList();

    for (final id in expiredIds) {
      _deviceCache.remove(id);
    }
    if (expiredIds.isNotEmpty) {
      debugPrint(
        '[BLE] Removed ${expiredIds.length} expired device(s) from cache '
        '(silent > ${_deviceExpireTimeout.inSeconds}s).',
      );
    }

    if (_deviceCache.isNotEmpty || expiredIds.isNotEmpty) {
      _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    // ✅ From Version 1: Stop any ongoing scan
    await stopScan();

    // ✅ From Version 2: Clean disconnect first
    await disconnect(emitState: false);

    // ✅ From Version 2: Set state early
    _emit(BleConnectionStatus.connecting);

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    var hasreachedConnectedState = false;

    // Setup connection state listener
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
      // ✅ From Version 2: Shorter timeout for better UX (or keep 15s?)
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 10), // Balanced
        license: License.commercial,
      );

      await _discoverServices();

      // ✅ From Version 1: Authentication state
      _emit(BleConnectionStatus.awaitingAuthentication);
    } catch (e) {
      // ✅ From Version 2: Handle cancellation
      if (_connectCancelled) return;

      // ✅ From Version 2: Complete cleanup
      _connStateSub?.cancel();
      _connStateSub = null;
      _device = null;
      _connectedDevice = null;

      // ✅ From Version 2: User-friendly error messages
      final String message;
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('timed out') || errStr.contains('timeout')) {
        message = 'Controller unreachable — device is out of range or offline.';

        // ✅ From Version 2: Auto-recovery
        Future.delayed(const Duration(seconds: 3), () {
          if (!_isDisposing && _snapshot.status == BleConnectionStatus.error) {
            _emit(BleConnectionStatus.disconnected);
          }
        });
      } else {
        message = 'Connection failed: ${e.toString()}';
      }

      _emit(BleConnectionStatus.error, message: message);
      _logger.e('Connection failed: ${e.toString()}');
      return;
    }

    // Monitor for unexpected disconnection
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
      // ✅ From Version 2: Progress tracking
      _emit(BleConnectionStatus.discoveringServices);

      // ✅ From Version 2: MTU optimization for Android
      if (!kIsWeb && Platform.isAndroid) {
        try {
          final negotiatedMtu = await _device!.requestMtu(512);
          debugPrint('[BLE] ATT MTU negotiated: $negotiatedMtu bytes');
        } catch (e) {
          _logger.w('MTU negotiation failed — proceeding with default MTU: $e');
        }
      }

      final services = await _device!.discoverServices();

      // ✅ From Version 1: Analog support
      BluetoothCharacteristic? analog;
      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;
      // BluetoothCharacteristic? heartbeat;

      _digitalChar = null;
      _authChar = null;
      _analogChar = null;
      _statusChar = null;
      // _heartbeatChar = null;
      // _digitalCharWriteNoResponse = false;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            BLEConstants.serviceUuid.toLowerCase()) {
          continue;
        }

        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();

          // ✅ From Version 2: Detailed logging
          debugPrint(
            '[BLE] Char discovered: $uuid '
            '| write=${char.properties.write} '
            '| writeNoResp=${char.properties.writeWithoutResponse} '
            '| notify=${char.properties.notify}',
          );

          // ✅ Combined: All characteristics
          if (uuid == BLEConstants.digitalCharUuid.toLowerCase()) {
            digital = char;
            _digitalCharWriteNoResponse = char.properties.writeWithoutResponse;
          } else if (uuid == BLEConstants.analogCharUuid.toLowerCase()) {
            analog = char; // ← Added from Version 1
          } else if (uuid == BLEConstants.authCharUuid.toLowerCase()) {
            auth = char;
          } else if (uuid == BLEConstants.statusCharUuid.toLowerCase()) {
            status = char;
          }
          // else if (uuid == BLEConstants.heartbeatCharUuid.toLowerCase()) {
          //   heartbeat = char;  // ← From Version 2
          // }
        }
      }

      // ✅ Version 2: Better verification (including analog)
      if (digital == null || auth == null || status == null || analog == null) {
        await _device!.disconnect();
        _connectedDevice = null;
        _emit(
          BleConnectionStatus.error,
          message: 'PLC service not fully found on this device.',
        );
        return;
      }

      // Store all characteristics
      _analogChar = analog;
      _digitalChar = digital;
      _authChar = auth;
      _statusChar = status;
      // _heartbeatChar = heartbeat;

      // ✅ Version 2: Write performance check
      if (!_digitalCharWriteNoResponse) {
        _logger.w(
          'Digital characteristic does not support writeWithoutResponse — '
          'control writes will use ATT WRITE REQUEST (with ACK, ~15–40 ms '
          'round-trip per command).',
        );
      }

      // if (_heartbeatChar == null) {
      //   debugPrint('[BLE] WARNING: Heartbeat characteristic NOT found.');
      // }

      // ✅ Version 2: Progress tracking
      _emit(BleConnectionStatus.configuringNotifications);

      // ✅ Combined: Set up notifications for all characteristics
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

      // ✅ Version 2: Auto-cleanup on disconnect
      _device!.cancelWhenDisconnected(_analogSubscription!, next: true);
      _device!.cancelWhenDisconnected(_authSubscription!, next: true);
      _device!.cancelWhenDisconnected(_statusSubscription!, next: true);

      // ✅ Version 2: Safe state initialization
      _emit(BleConnectionStatus.initializingSafeState);
      await _sendSafeStatePreAuthBestEffort();

      // ✅ From Version 1: Authentication state
      _emit(BleConnectionStatus.awaitingAuthentication);
    } catch (e) {
      // ✅ From Version 2: Clean error handling
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

  Future<void> _sendSafeStatePreAuthBestEffort() async {
    if (_digitalChar == null) {
      return;
    }
    try {
      await _sendSafeStateCommand().timeout(const Duration(milliseconds: 900));
      _logger.i('Pre-auth safe-state packet sent (best effort).');
    } catch (error) {
      _logger.w('Pre-auth safe-state write failed: ${error.toString()}');
    }
  }

  Future<void> _sendSafeStateCommand() async {
    if (_digitalChar == null) {
      throw StateError('Digital characteristic is not ready.');
    }
    final plainBytes = PlcOutputCommand.emergencyStop().wireBytes.toList();
    if (_sessionAuthenticated) {
      await _writeEncryptedCharacteristic(
        characteristic: _digitalChar!,
        plaintext: plainBytes,
        withoutResponse: _digitalCharWriteNoResponse,
        label: 'safe-state',
      );
      return;
    }
    await _digitalChar!.write(
      plainBytes,
      withoutResponse: _digitalCharWriteNoResponse,
    );
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
