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

  bool _connectCancelled = false;

  static const Duration _scanBurstDuration = Duration(seconds: 6);
  static const Duration _scanPauseDuration = Duration(milliseconds: 1500);
  static const Duration _maxScanDuration = Duration(minutes: 3);

  Completer<BleAuthOutcome>? _pendingAuthCompleter;
  Completer<void>? _pendingSafeStateCompleter;

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
    _connectCancelled = false;
    await stopScan();
    await disconnect(emitState: false);

    _connectedDevice = scanDevice;
    _device = scanDevice.device;
    _emit(
      BleConnectionStatus.connecting,
      message: 'Connecting to ${scanDevice.name}\u2026',
    );

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
      await _safeDisconnectDevice(_device);
      _clearConnectionState();
      return;
    }

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

  // Discover services and map characteristics.

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
    } catch (e) {
      await _device!.disconnect();
      _connectedDevice = null;
      _emit(
        BleConnectionStatus.error,
        message: 'Service discovery failed: ${e.toString()}',
      );
    }
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
    _digitalCharWriteNoResponse = false;
  }

  Future<void> _safeDisconnectDevice(BluetoothDevice? device) async {
    try {
      if (device != null && device.isConnected) await device.disconnect();
    } catch (_) {}
  }

  String _friendlyConnectionError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('timed out') || lower.contains('timeout')) {
      return 'Controller unreachable — device is out of range or offline.';
    }
    if (lower.contains('cancelled') || lower.contains('canceled')) {
      return 'Connection was cancelled.';
    }
    return 'Connection failed: $raw';
  }

  void _scheduleErrorRecovery() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!_isDisposing && _snapshot.status == BleConnectionStatus.error) {
        _emit(BleConnectionStatus.disconnected);
      }
    });
  }

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

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  void _handleDisconnect() {
    if (_isDisposing) {
      return;
    }
    _stopRssiPolling();
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

  // Keeps the last known values so single-channel updates don't zero out the other channel.


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
