import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rev_crane_control_ops/services/ble_crypto.dart';
import 'package:rev_crane_control_ops/services/ble_transport.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';

class BleService implements BleTransport {
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<BleScanDevice>> _scanController =
      StreamController<List<BleScanDevice>>.broadcast();
  final StreamController<Map<String, int>> _analogController =
      StreamController<Map<String, int>>.broadcast();
  final StreamController<PlcOutputCommand> _statusController =
      StreamController<PlcOutputCommand>.broadcast();

  @override
  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;

  @override
  Stream<List<BleScanDevice>> get scanStream => _scanController.stream;

  @override
  Stream<Map<String, int>> get analogStream => _analogController.stream;

  @override
  Stream<PlcOutputCommand> get statusStream => _statusController.stream;

  @override
  bool get requiresLocalBluetooth => true;

  @override
  String get readinessLabel => 'Bluetooth';

  @override
  Stream<bool> get readyStream => FlutterBluePlus.adapterState
      .map((state) => state == BluetoothAdapterState.on)
      .distinct();

  BleConnectionState _snapshot = BleConnectionState.initial();
  BluetoothDevice? _device;
  BleScanDevice? _connectedDevice;

  BluetoothCharacteristic? _analogChar;
  BluetoothCharacteristic? _digitalChar;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _heartbeatChar;
  // true when the digital characteristic supports WriteWithoutResponse
  // (lower-latency control writes; logged as a warning if absent).
  bool _digitalCharWriteNoResponse = false;

  StreamSubscription<BluetoothConnectionState>? _connStateSub;
  StreamSubscription<List<int>>? _analogSubscription;
  StreamSubscription<List<int>>? _authSubscription;
  StreamSubscription<List<int>>? _statusSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSub;

  bool _isDisposing = false;
  bool _scanContinue = false;
  bool _scanPaused = false;

  final Map<String, BleScanDevice> _deviceCache = {};
  final Map<String, int> _lastAnalog = {'A1': 0, 'A2': 0};

  DateTime? _scanDeadline;
  Timer? _pruneTimer;
  Timer? _rssiTimer;
  static const Duration _deviceExpireTimeout = Duration(seconds: 20);
  static const Duration _pruneInterval = Duration(seconds: 3);

  Timer? _heartbeatTimer;
  bool _heartbeatActive = false;
  bool _heartbeatWritePending = false;

  bool _connectCancelled = false;

  static const Duration _scanBurstDuration = Duration(seconds: 6);
  static const Duration _scanPauseDuration = Duration(milliseconds: 1500);
  static const Duration _maxScanDuration = Duration(minutes: 3);

  Completer<BleAuthOutcome>? _pendingAuthCompleter;
  Completer<void>? _pendingSafeStateCompleter;
  bool _sessionAuthenticated = false;

  int _cryptoSessionGeneration = 0;
  Future<void> _encryptedWriteLane = Future<void>.value();

  // ── Bluetooth adapter ──────────────────────────────────────────────────────

  @override
  Future<bool> checkReady() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  @override
  Future<void> ensureBluetoothReady() async {
    if (!kIsWeb && Platform.isAndroid) {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  // ── broadcasts new connection status to all listening UI screens ──────────────────────────────────────────────────────

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

  @override
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

  // ── Pause Scanning ───────────────────────────────────────────────────────────────

  @override
  Future<void> pauseScan() async {
    if (_scanDeadline == null) return;
    if (_scanPaused) return;
    _scanPaused = true;
    _scanContinue = false;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _freezeCache();
  }

  // ── Resume Scanning ───────────────────────────────────────────────────────────────

  @override
  Future<void> resumeScan() async {
    if (_scanContinue) return;
    final deadline = _scanDeadline;
    if (deadline == null) return;

    if (deadline.difference(DateTime.now()).inSeconds < 1) {
      _scanPaused = false;
      _scanDeadline = null;
      _pruneTimer?.cancel();
      _pruneTimer = null;
      if (_snapshot.status == BleConnectionStatus.scanning) {
        _emit(BleConnectionStatus.disconnected);
      }
      return;
    }

    _scanPaused = false;
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
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

  @override
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

  // ── Remove the Stale Devices ───────────────────────────────────────────────────────────────

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

  @override
  Future<void> connect(BleScanDevice scanDevice) async {
    _connectCancelled = false;

    await stopScan();
    if (_connectCancelled) return;
    await disconnect(emitState: false);
    if (_connectCancelled) return;

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    _emit(BleConnectionStatus.connecting);

    try {
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 12),
        license: License.commercial,
      );
    } catch (e) {
      if (_connectCancelled) return;
      _clearConnectionState();
      _emit(
        BleConnectionStatus.error,
        message: _friendlyConnectionError(e.toString()),
      );
      _logger.e('BLE connect failed: $e');
      _scheduleErrorRecovery();

      return;
    }

    if (_connectCancelled) {
      final device = _device;
      _clearConnectionState();
      await _safeDisconnectDevice(device);
      return;
    }
    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _logger.w('Device disconnected unexpectedly');
        _handleDisconnect();
      }
    });
    _device!.cancelWhenDisconnected(_connStateSub!, delayed: true, next: true);

    try {
      await _discoverServices();
    } catch (e) {
      if (_connectCancelled) return;
      final dev = _device;
      _clearConnectionState();
      await _safeDisconnectDevice(dev);
      _emit(
        BleConnectionStatus.error,
        message: 'Service setup failed: ${e.toString()}',
      );
      _logger.e('Service discovery failed: $e');
      return;
    }

    if (_connectCancelled) return;

    _connStateSub?.cancel();
    _connStateSub = _device!.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        _handleDisconnect();
      }
    });

    _device!.cancelWhenDisconnected(_connStateSub!, delayed: true, next: true);
    _emit(BleConnectionStatus.awaitingAuthentication);
  }

  //  ── Discover services and map characteristics. ─────────────────────────────────────────────────────────────

  Future<void> _discoverServices() async {
    try {
      _emit(BleConnectionStatus.discoveringServices);

      if (!kIsWeb && Platform.isAndroid) {
        try {
          final mtu = await _device!.requestMtu(512);
          debugPrint('[BLE] MTU negotiated: $mtu bytes');
        } catch (e) {
          _logger.w(
            'MTU negotiation skipped — proceeding with default MTU: $e',
          );
          debugPrint('[BLE] MTU negotiation failed: $e');
        }
      }

      final services = await _device!.discoverServices();

      BluetoothCharacteristic? analog;
      BluetoothCharacteristic? digital;
      BluetoothCharacteristic? auth;
      BluetoothCharacteristic? status;

      _digitalChar = null;
      _authChar = null;
      _analogChar = null;
      _statusChar = null;
      _heartbeatChar = null;
      _digitalCharWriteNoResponse = false;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            BLEConstants.serviceUuid.toLowerCase()) {
          continue;
        }
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          debugPrint(
            '[BLE] Char discovered: $uuid '
            '| write=${char.properties.write} '
            '| writeNoResp=${char.properties.writeWithoutResponse} '
            '| notify=${char.properties.notify}',
          );

          if (uuid == BLEConstants.digitalCharUuid.toLowerCase()) {
            digital = char;
            _digitalCharWriteNoResponse = char.properties.writeWithoutResponse;
          } else if (uuid == BLEConstants.analogCharUuid.toLowerCase()) {
            analog = char;
          } else if (uuid == BLEConstants.authCharUuid.toLowerCase()) {
            auth = char;
          } else if (uuid == BLEConstants.statusCharUuid.toLowerCase()) {
            status = char;
          } else if (uuid == BLEConstants.heartbeatCharUuid.toLowerCase()) {
            _heartbeatChar = char;
            debugPrint(
              '[BLE] Heartbeat characteristic found '
              '(write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse})',
            );
          }
        }
      }

      if (digital == null || auth == null || status == null || analog == null) {
        final missing = [
          if (digital == null) 'digital',
          if (auth == null) 'auth',
          if (status == null) 'status',
          if (analog == null) 'analog',
        ].join(', ');

        await _device!.disconnect();
        _connectedDevice = null;
        _emit(
          BleConnectionStatus.error,
          message: 'PLC service incomplete — missing: $missing.',
        );
        return;
      }

      if (!_digitalCharWriteNoResponse) {
        _logger.w(
          'Digital characteristic does not support WriteWithoutResponse — '
          'control writes will incur an ATT round-trip (~15\u201340 ms per command).',
        );
      }
      if (_heartbeatChar == null) {
        debugPrint(
          '[BLE] WARNING: Heartbeat characteristic NOT found '
          '(UUID: ${BLEConstants.heartbeatCharUuid}). '
          'Heartbeat will be disabled.',
        );
      }

      _analogChar = analog;
      _digitalChar = digital;
      _authChar = auth;
      _statusChar = status;

      _emit(BleConnectionStatus.configuringNotifications);

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

      _emit(BleConnectionStatus.initializingSafeState);
      await _sendSafeStatePreAuthBestEffort();
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

  // ── Cancel Connecting ─────────────────────────────────────────────────────

  @override
  Future<void> cancelConnecting() async {
    const cancellableStatuses = {
      BleConnectionStatus.connecting,
      BleConnectionStatus.discoveringServices,
      BleConnectionStatus.configuringNotifications,
    };
    if (!cancellableStatuses.contains(_snapshot.status)) return;

    _connectCancelled = true;

    await _analogSubscription?.cancel();
    await _authSubscription?.cancel();
    await _statusSubscription?.cancel();
    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;

    final device = _device;
    _clearConnectionState();
    await _safeDisconnectDevice(device);

    _connectCancelled = false;
    _emit(BleConnectionStatus.disconnected);
  }

  // ── Connection helpers ─────────────────────────────────────────────────────

  void _clearConnectionState() {
    _connStateSub?.cancel();
    _connStateSub = null;
    _device = null;
    _connectedDevice = null;
    _analogChar = null;
    _digitalChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;
    _digitalCharWriteNoResponse = false;
  }

  Future<void> _safeDisconnectDevice(BluetoothDevice? device) async {
    try {
      if (device != null && device.isConnected) await device.disconnect();
    } catch (_) {}
  }

  String _friendlyConnectionError(String error) {
    final err = error.toLowerCase();
    if (err.contains('timed out') || err.contains('timeout')) {
      return 'Connection timed out - device is out of range or unresponsive';
    } else if (err.contains('not found') || err.contains('not discoverable')) {
      return 'Device not found - please ensure it\'s powered on and in range';
    } else if (err.contains('already connecting')) {
      return 'Already connecting - please wait';
    } else if (err.contains('connection refused')) {
      return 'Connection refused - device may be busy';
    } else if (err.contains('permission denied')) {
      return 'Permission denied - please check Bluetooth permissions';
    } else {
      return 'Connection failed: ${error.replaceFirst('Exception: ', '')}';
    }
  }

  void _scheduleErrorRecovery() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!_isDisposing && _snapshot.status == BleConnectionStatus.error) {
        _emit(BleConnectionStatus.disconnected);
      }
    });
  }

  // ── Disconnect Device ─────────────────────────────────────────────────────

  @override
  Future<void> disconnect({bool emitState = true}) async {
    _stopRssiPolling();
    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;
    final pendingSafeState = _pendingSafeStateCompleter;
    if (pendingSafeState != null && !pendingSafeState.isCompleted) {
      pendingSafeState.complete();
    }
    _pendingSafeStateCompleter = null;

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
    _heartbeatChar = null;
    _digitalCharWriteNoResponse = false;

    if (device != null && device.isConnected) {
      await device.disconnect();
    }

    if (emitState) {
      _handleDisconnect();
    } else {
      _connectedDevice = null;
    }
  }

  // ── Run Disconnect ─────────────────────────────────────────────────────

  void _handleDisconnect() {
    if (_isDisposing) {
      return;
    }
    _stopRssiPolling();
    _stopHeartbeat();
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();
    _pendingAuthCompleter?.complete(BleAuthOutcome.timedOut);
    _pendingAuthCompleter = null;

    _device = null;
    _connectedDevice = null;
    _connStateSub?.cancel();
    _connStateSub = null;

    _analogChar = null;
    _authChar = null;
    _digitalChar = null;
    _statusChar = null;
    _heartbeatChar = null;
    _digitalCharWriteNoResponse = false;

    _analogSubscription?.cancel();
    _authSubscription?.cancel();
    _statusSubscription?.cancel();

    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    _analogController.add(const {'A1': 0, 'A2': 0});

    if (!_statusController.isClosed) {
      _statusController.add(PlcOutputCommand.idle());
    }
    _emit(BleConnectionStatus.disconnected);
    _freezeCache(forceEmit: true);
  }

  // ── Characteristic callbacks ───────────────────────────────────────────────
  // ── Processes raw sensor bytes and sends the values to the analogStream ────

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

  // ── Processes raw status bytes and sends them to the statusStream ──────────

  void _handleStatusNotification(List<int> bytes) {
    final command = PlcOutputCommand.fromStatusNotification(bytes);
    if (command.estop || command.isIdle) {
      final pending = _pendingSafeStateCompleter;
      if (pending != null && !pending.isCompleted) {
        pending.complete();
      }
      _pendingSafeStateCompleter = null;
    }
    _logger.i(
      'PLC status: estop=${command.estop} dir=${command.direction} speed=${command.speed}',
    );
    _statusController.add(command);
  }

  // ── Processes the crane controller's login response ────────────────────────

  void _handleAuthNotification(List<int> bytes) {
    unawaited(_handleAuthNotificationAsync(bytes));
  }

  // RUN Auth Notification
  Future<void> _handleAuthNotificationAsync(List<int> bytes) async {
    final plainPayload = _tryDecodeUtf8(bytes)?.trim();
    if (await _handleAuthPayload(plainPayload, source: 'plain')) {
      return;
    }

    if (_pendingAuthCompleter == null || !BleCrypto.sessionActive) {
      if (plainPayload == null) {
        _logger.w(
          'Auth notification: non-UTF8 data (${bytes.length} bytes) ignored.',
        );
      } else {
        _logger.w('Unknown auth notification payload: "$plainPayload"');
      }
      return;
    }

    try {
      final decrypted = await BleCrypto.decrypt(bytes);
      final encryptedPayload = _tryDecodeUtf8(decrypted)?.trim();
      if (await _handleAuthPayload(encryptedPayload, source: 'encrypted')) {
        return;
      }
      _logger.w(
        'Unknown encrypted auth notification payload: "$encryptedPayload"',
      );
    } on BleCryptoException catch (e) {
      _logger.e('Encrypted auth notification rejected: $e');
      await _cryptoSafeState('Auth response decrypt failed: $e');
    } on StateError catch (e) {
      _logger.e('Encrypted auth notification session error: $e');
      await _cryptoSafeState('Auth response session error: $e');
    } catch (e) {
      _logger.e('Encrypted auth notification error: $e');
      await _cryptoSafeState('Auth response error: $e');
    }
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

  // ── Reads and acts on specific login result messages ──────────────────────

  Future<bool> _handleAuthPayload(
    String? payload, {
    required String source,
  }) async {
    if (payload == null || payload.isEmpty) {
      return false;
    }

    if (payload.startsWith('AUTH_REQ:')) {
      _logger.i('Auth notification ($source): AUTH_REQ');
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return true;
    }

    if (payload == BLEConstants.authSuccess) {
      _logger.i('Auth notification ($source): $payload');
      await _finalizeAuthenticatedSession();
      return true;
    }

    // if (payload == BLEConstants.authUntrusted) {
    //   _logger.w('Auth notification ($source): $payload');
    //   _cryptoSessionGeneration++;
    //   _sessionAuthenticated = false;
    //   _heartbeatWritePending = false;
    //   _encryptedWriteLane = Future<void>.value();
    //   BleCrypto.endSession();
    //   _pendingAuthCompleter?.complete(BleAuthOutcome.untrusted);
    //   _pendingAuthCompleter = null;
    //   _emit(BleConnectionStatus.error, message: payload);

    //   unawaited(disconnect(emitState: false));
    //   return true;
    // }

    if (payload == BLEConstants.authFailed ||
        payload == BLEConstants.authTimeout) {
      _logger.w('Auth notification ($source): $payload');
      _cryptoSessionGeneration++;
      _sessionAuthenticated = false;
      _heartbeatWritePending = false;
      _encryptedWriteLane = Future<void>.value();
      BleCrypto.endSession();
      _pendingAuthCompleter?.complete(
        payload == BLEConstants.authTimeout
            ? BleAuthOutcome.timedOut
            : BleAuthOutcome.failed,
      );
      _pendingAuthCompleter = null;
      _emit(BleConnectionStatus.error, message: payload);
      return true;
    }

    return false;
  }

  String? _tryDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  // ── If encryption fails, immediately go to safe state ──────────────────────

  Future<void> _cryptoSafeState(String reason) async {
    if (_isDisposing) return;

    _logger.e('CRYPTO SAFE STATE ENTERED: $reason');
    debugPrint('[SECURITY] Entering crypto safe state — reason: $reason');

    _stopHeartbeat();

    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();

    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = null;

    _emit(
      BleConnectionStatus.error,
      message: 'Security error — session terminated. Please reconnect.',
    );

    await disconnect(emitState: false);
  }

  // ── Completes the login ────────────────────────────────────────────────────

  Future<void> _finalizeAuthenticatedSession() async {
    if (!BleCrypto.sessionActive) {
      await BleCrypto.beginSession();
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _device!.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        debugPrint('[BLE] Connection priority set to HIGH.');
      } catch (e) {
        _logger.w('Could not set connection priority: $e');
      }
    }

    _sessionAuthenticated = true;
    _emit(BleConnectionStatus.authenticated);
    _pendingAuthCompleter?.complete(BleAuthOutcome.success);
    _pendingAuthCompleter = null;
    _startRssiPolling();
    _startHeartbeat();
  }

  // ── Autheticate the device ─────────────────────────────────────────────────

  @override
  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    if (_authChar == null) {
      throw StateError('Authentication characteristic is not ready.');
    }

    _pendingAuthCompleter?.complete(BleAuthOutcome.failed);
    _pendingAuthCompleter = Completer<BleAuthOutcome>();
    final authFuture = _pendingAuthCompleter!.future;
    _emit(BleConnectionStatus.authenticating);
    // await _authChar!.write(
    //       utf8.encode('$email|$password'),
    //       withoutResponse: false,
    //     );
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();
    await BleCrypto.beginSession();

    final plaintext = utf8.encode('$email|$password|$deviceId');
    final encryptedAuth = await BleCrypto.encrypt(plaintext);

    await _authChar!.write(encryptedAuth, withoutResponse: false);

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

  // ── Heartbeat helpers

  void _startHeartbeat() {
    _stopHeartbeat();
    if (_heartbeatChar == null) {
      _logger.w('Heartbeat characteristic not found — heartbeat disabled.');
      return;
    }

    final bool useWithoutResponse =
        _heartbeatChar!.properties.writeWithoutResponse;
    if (!useWithoutResponse) {
      _logger.w(
        'HB: ESP32 heartbeat characteristic does not support '
        'writeWithoutResponse — using ATT WRITE REQUEST (~15 ms round-trip). ',
      );
    }

    _heartbeatActive = true;
    _heartbeatTimer = Timer.periodic(
      SafetyConstants.heartbeatInterval,
      (_) => _sendHeartbeatTick(useWithoutResponse),
    );
  }

  void _stopHeartbeat() {
    _heartbeatActive = false;
    _heartbeatWritePending = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeatTick(bool useWithoutResponse) {
    if (!_heartbeatActive || _isDisposing) return;
    if (_heartbeatWritePending) return;
    final char = _heartbeatChar;
    if (char == null) return;
    _heartbeatWritePending = true;
    // AES-128-GCM encrypted heartbeat — fire-and-forget.
    unawaited(
      _encryptAndSendHeartbeat(char, useWithoutResponse)
          .catchError((Object e) {
            _logger.w('Heartbeat write failed: $e');
          })
          .whenComplete(() {
            _heartbeatWritePending = false;
          }),
    );
  }

  Future<void> _encryptAndSendHeartbeat(
    BluetoothCharacteristic char,
    bool useWithoutResponse,
  ) async {
    if (!_heartbeatActive || _isDisposing) return;
    await _writeEncryptedCharacteristic(
      characteristic: char,
      plaintext: utf8.encode(BLEConstants.heartbeatPayload),
      withoutResponse: useWithoutResponse,
      label: 'heartbeat',
    );
  }

  // ── Start RSSI polling ─────────────────────────────────────────────────────

  void _startRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final device = _device;
      final connectedDevice = _connectedDevice;
      if (device == null ||
          !device.isConnected ||
          connectedDevice == null ||
          _isDisposing) {
        return;
      }
      try {
        final rssi = await device.readRssi();

        _connectedDevice = connectedDevice.copyWith(rssi: rssi);

        _emit(_snapshot.status);
      } catch (e) {
        _logger.w('RSSI poll failed: $e');
      }
    });
  }

  // ── Stop RSSI polling ─────────────────────────────────────────────────────

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  // ── Write helpers ──────────────────────────────────────────────────────────

  Future<void> _writeEncryptedCharacteristic({
    required BluetoothCharacteristic characteristic,
    required List<int> plaintext,
    required bool withoutResponse,
    required String label,
  }) {
    final generation = _cryptoSessionGeneration;
    final writeFuture = _encryptedWriteLane.then((_) async {
      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _device?.isConnected != true) {
        return;
      }

      final wireBytes = await BleCrypto.encrypt(plaintext);

      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _device?.isConnected != true) {
        return;
      }

      await characteristic.write(wireBytes, withoutResponse: withoutResponse);
    });

    _encryptedWriteLane = writeFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.w('Encrypted BLE write lane recovered after $label: $error');
      },
    );

    return writeFuture;
  }

  @override
  Future<void> writeDigital(List<int> bytes) async {
    if (_digitalChar == null) return;
    if (_sessionAuthenticated) {
      try {
        await _writeEncryptedCharacteristic(
          characteristic: _digitalChar!,
          plaintext: bytes,
          withoutResponse: _digitalCharWriteNoResponse,
          label: 'digital',
        );
        return;
      } on BleCryptoException catch (e) {
        _logger.e('Encryption failure on digital write: $e');
        unawaited(_cryptoSafeState('BleCryptoException during encrypt: $e'));
        return;
      } on StateError catch (e) {
        _logger.e('Crypto session state error on digital write: $e');
        unawaited(_cryptoSafeState('StateError during encrypt: $e'));
        return;
      }
    }
    await _digitalChar!.write(
      bytes,
      withoutResponse: _digitalCharWriteNoResponse,
    );
  }

  @override
  Future<void> writeAuth(List<int> bytes) async {
    if (_authChar == null) return;
    await _authChar!.write(bytes);
  }

  @override
  void dispose() {
    _isDisposing = true;
    _scanPaused = false;
    _scanDeadline = null;
    _stopRssiPolling();
    _stopHeartbeat();
    _scanResultsSub?.cancel();
    _authSubscription?.cancel();
    _statusSubscription?.cancel();
    _connStateSub?.cancel();
    if (FlutterBluePlus.isScanningNow) {
      FlutterBluePlus.stopScan();
    }
    stopScan();
    final device = _device;
    _device = null;
    _connectedDevice = null;

    _digitalChar = null;
    _analogChar = null;
    _authChar = null;
    _statusChar = null;
    _heartbeatChar = null;

    if (device != null && device.isConnected) {
      device.disconnect();
    }
    disconnect();

    _connectionController.close();
    _scanController.close();
    _analogController.close();
    _statusController.close();
  }
}
