import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:logger/logger.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rev_crane_control_ops/services/ble_crypto.dart';

import 'package:rev_crane_control_ops/utils/constants.dart';

import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/hoist_notification.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';

class _StaleBleSessionException implements Exception {
  const _StaleBleSessionException(this.message);

  final String message;

  @override
  String toString() => message;
}

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

  BluetoothCharacteristic? _digitalChar;
  BluetoothCharacteristic? _authChar;
  BluetoothCharacteristic? _heartbeatChar;
  BluetoothCharacteristic? _analogOutChar;
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

  // True from startScan() until stopScan() — i.e. "a scan session is the
  // user's current intent," independent of whether the burst loop is
  // literally running right now (it may be mid-pause, see pauseScan()).
  bool _scanSessionActive = false;

  // Bumped on every startScan()/resumeScan()/stopScan(). Lets a scan loop
  // that's mid-burst notice it's been superseded by a newer call and return
  // without touching shared state — see _runScanSession().
  int _scanGeneration = 0;

  final Map<String, BleScanDevice> _deviceCache = {};
  final Map<String, int> _lastHoistValues = {
    HoistNotification.hoist1Key: 0,
    HoistNotification.hoist2Key: 0,
  };

  Timer? _pruneTimer;
  Timer? _rssiTimer;
  static const Duration _deviceExpireTimeout = Duration(seconds: 20);
  static const Duration _pruneInterval = Duration(seconds: 3);

  Timer? _heartbeatTimer;
  bool _heartbeatActive = false;
  bool _heartbeatWritePending = false;
  bool _cryptoSafeStateActive = false;

  /// When the most recent heartbeat write to the PLC last completed without
  /// error. Null until the first attempt. Mirrors [BleService]'s own status-
  /// notification recency tracking (see CraneController._lastPlcStatusAt) so
  /// FeedbackManager can treat a stalled heartbeat write the same way it
  /// treats a silent status characteristic — see FeedbackManager._resolveComms.
  DateTime? _lastHeartbeatSuccessAt;
  DateTime? get lastHeartbeatSuccessAt => _lastHeartbeatSuccessAt;

  // ── Diagnostic counters ────────────────────────────────────────────────
  // Plain counts of real traffic already flowing over the existing wire
  // protocol (heartbeat/digital/analog-out writes, and every raw
  // notification received) — surfaced read-only for the Diagnostics screen.
  // Reset per connection attempt in [_connect] so they describe the current
  // session rather than accumulating across a whole app lifetime.
  int _txPacketCount = 0;
  int _rxPacketCount = 0;
  int _commErrorCount = 0;

  int get txPacketCount => _txPacketCount;
  int get rxPacketCount => _rxPacketCount;
  int get commErrorCount => _commErrorCount;

  bool _connectCancelled = false;
  Future<void>? _activeConnectFuture;
  Future<BleAuthOutcome>? _activeAuthFuture;
  bool _rssiReadPending = false;
  int _rssiPollGeneration = 0;

  static const Duration _scanBurstDuration = Duration(seconds: 6);
  static const Duration _scanPauseDuration = Duration(milliseconds: 1500);

  Completer<BleAuthOutcome>? _pendingAuthCompleter;
  bool _sessionAuthenticated = false;

  int _cryptoSessionGeneration = 0;
  Future<void> _encryptedWriteLane = Future<void>.value();
  // The firmware uses one monotonically increasing nonce counter for every
  // encrypted notification characteristic. Preserve BLE arrival order across
  // auth, analog and status decryptions so replay protection sees that same
  // ordering even though the characteristic callbacks are asynchronous.
  Future<void> _encryptedReadLane = Future<void>.value();

  // ── Bluetooth adapter ──────────────────────────────────────────────────────

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

  void _emitScanSnapshot() {
    if (_isDisposing || _scanController.isClosed) return;
    _scanController.add(List.unmodifiable(_deviceCache.values.toList()));
  }

  // ── Scanning ───────────────────────────────────────────────────────────────

  Future<void> startScan() async {
    if (_isDisposing) return;
    final generation = ++_scanGeneration;
    _scanContinue = false;

    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;

    // Deliberately not clearing _deviceCache: previously-seen devices carry
    // forward frozen (see _freezeCache), and _runScanSession's _unfreezeCache
    // call below is what un-freezes them and gives them a fresh grace
    // window — clearing here would discard that and force every card to be
    // rebuilt from scratch off the next advertisement's timestamp, which is
    // exactly the stale-then-active flash this is avoiding.
    _scanSessionActive = true;
    _scanPaused = false;
    await _runScanSession(generation);
  }

  // ── Pause Scanning ───────────────────────────────────────────────────────────────

  Future<void> pauseScan() async {
    if (!_scanSessionActive || _scanPaused) return;
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

  Future<void> resumeScan() async {
    if (!_scanSessionActive || !_scanPaused) return;

    final generation = ++_scanGeneration;
    _scanPaused = false;
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
    await _runScanSession(generation);
  }

  // ── Run Scan Burst Section ───────────────────────────────────────────────────────────────
  //
  // Runs scan bursts (6s scan / 1.5s pause) back-to-back with no overall
  // time limit. The loop only ends when stopScan()/pauseScan() flips
  // _scanContinue to false, or when a newer startScan()/resumeScan() call
  // bumps `generation` past the value this call captured — that check is
  // what prevents two sessions from ever running concurrently: a superseded
  // call notices it's been replaced and returns quietly instead of racing
  // the newer session's scan-result subscription and cache/state teardown.
  Future<void> _runScanSession(int generation) async {
    _unfreezeCache();
    _emit(BleConnectionStatus.scanning);
    _scanContinue = true;

    if (_deviceCache.isNotEmpty) {
      _emitScanSnapshot();
    }

    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(_pruneInterval, (_) => _pruneStaleDevices());

    _scanResultsSub = FlutterBluePlus.scanResults.listen(
      (results) {
        if (_isDisposing || !_scanContinue || generation != _scanGeneration) {
          return;
        }
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
          _emitScanSnapshot();
        }
      },
      onError: (e) {
        if (_isDisposing || generation != _scanGeneration) return;
        _scanContinue = false;
        _emit(
          BleConnectionStatus.error,
          message: 'Scan error: ${e.toString()}',
        );
      },
    );

    while (_scanContinue && !_isDisposing && generation == _scanGeneration) {
      try {
        await FlutterBluePlus.startScan(
          timeout: _scanBurstDuration,
          androidScanMode: AndroidScanMode.balanced,
        );
        await FlutterBluePlus.isScanning.where((s) => !s).first;
      } catch (e, stackTrace) {
        if (_scanContinue && !_isDisposing && generation == _scanGeneration) {
          _scanContinue = false;
          _logger.e('BLE scan burst failed', error: e, stackTrace: stackTrace);
          _emit(
            BleConnectionStatus.error,
            message: 'Scan failed: ${e.toString()}',
          );
        }
        break;
      }
      if (!_scanContinue || _isDisposing || generation != _scanGeneration) {
        break;
      }
      await Future.delayed(_scanPauseDuration);
    }

    // A newer startScan()/resumeScan() call already owns this scan lane's
    // subscription and state — let its own teardown run instead of racing it.
    if (generation != _scanGeneration) return;

    await _scanResultsSub?.cancel();
    _scanResultsSub = null;

    _freezeCache();

    if (!_scanPaused) {
      _scanSessionActive = false;
      if (_snapshot.status == BleConnectionStatus.scanning) {
        _emit(BleConnectionStatus.disconnected);
      }
    }
  }

  // ── Stop Scanning ───────────────────────────────────────────────────────────────

  Future<void> stopScan() async {
    _scanGeneration++;
    _scanSessionActive = false;
    _scanPaused = false;
    _scanContinue = false;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await FlutterBluePlus.stopScan();
    await _scanResultsSub?.cancel();
    _scanResultsSub = null;
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
        // Freeze to whatever the card is actually showing right now, not
        // unconditionally "active" — a device that had already gone stale
        // before the user stopped scanning should stay stale while frozen.
        _deviceCache[id] = d.copyWith(frozenStatus: d.staleStatus);
        changed = true;
      }
    }
    if (changed || forceEmit) {
      _emitScanSnapshot();
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
      _emitScanSnapshot();
    }
  }

  // ── Connection ─────────────────────────────────────────────────────────────

  Future<void> connect(BleScanDevice scanDevice) async {
    if (_isDisposing) return;
    final activeConnect = _activeConnectFuture;
    if (activeConnect != null) {
      _logger.w(
        'Ignoring duplicate BLE connect request while setup is active.',
      );
      await activeConnect;
      return;
    }

    final connectFuture = _connect(scanDevice);
    _activeConnectFuture = connectFuture;
    try {
      await connectFuture;
    } finally {
      if (identical(_activeConnectFuture, connectFuture)) {
        _activeConnectFuture = null;
      }
    }
  }

  Future<void> _connect(BleScanDevice scanDevice) async {
    _connectCancelled = false;

    await stopScan();
    if (_connectCancelled) return;
    await disconnect(emitState: false, cancelPendingConnection: false);
    if (_connectCancelled) return;

    _cryptoSafeStateActive = false;
    _txPacketCount = 0;
    _rxPacketCount = 0;
    _commErrorCount = 0;
    _connectedDevice = scanDevice;
    final device = scanDevice.device;
    _device = device;
    _emit(BleConnectionStatus.connecting);

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 12),
        // MTU is requested once in _discoverServices, immediately before
        // refreshing and reading the GATT table.
        mtu: null,
        license: License.commercial,
      );
    } catch (e, stackTrace) {
      if (_connectCancelled) return;
      await _clearConnectionState();
      await _safeDisconnectDevice(device);
      _emit(
        BleConnectionStatus.error,
        message: _friendlyConnectionError(e.toString()),
      );
      _logger.e('BLE connect failed', error: e, stackTrace: stackTrace);
      _scheduleErrorRecovery();

      return;
    }

    if (_connectCancelled) return;
    if (!identical(_device, device)) {
      await _safeDisconnectDevice(device);
      return;
    }
    await _connStateSub?.cancel();
    final connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          identical(_device, device) &&
          !_connectCancelled) {
        _logger.w('Device disconnected unexpectedly');
        _handleDisconnect();
      }
    });
    _connStateSub = connectionSubscription;
    if (!identical(_device, device) || device.isDisconnected) {
      await connectionSubscription.cancel();
      if (identical(_connStateSub, connectionSubscription)) {
        _connStateSub = null;
      }
      if (identical(_device, device)) {
        await _clearConnectionState();
        await _safeDisconnectDevice(device);
        _emit(
          BleConnectionStatus.error,
          message: 'Device disconnected during connection setup.',
        );
      }
      return;
    }
    device.cancelWhenDisconnected(
      connectionSubscription,
      delayed: true,
      next: true,
    );

    try {
      await _discoverServices(device);
    } catch (e, stackTrace) {
      if (_connectCancelled) return;
      if (!identical(_device, device)) return;

      await _clearConnectionState();
      await _safeDisconnectDevice(device);
      _emit(
        BleConnectionStatus.error,
        message: 'Service setup failed: ${e.toString()}',
      );
      _logger.e('BLE service setup failed', error: e, stackTrace: stackTrace);
      return;
    }
  }

  //  ── Discover services and map characteristics. ─────────────────────────────────────────────────────────────

  Future<void> _discoverServices(BluetoothDevice device) async {
    _emit(BleConnectionStatus.discoveringServices);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final mtu = await device.requestMtu(512);
        debugPrint('[BLE] MTU negotiated: $mtu bytes');
      } catch (e) {
        _logger.w('MTU negotiation skipped — proceeding with default MTU: $e');
        debugPrint('[BLE] MTU negotiation failed: $e');
      }

      try {
        await device.clearGattCache();
        debugPrint('[BLE] GATT cache cleared.');
      } catch (e) {
        _logger.w('GATT cache clear skipped: $e');
        debugPrint('[BLE] GATT cache clear failed: $e');
      }
    }

    _ensureConnectionSetupActive(device);
    final services = await device.discoverServices(
      subscribeToServicesChanged: false,
    );
    _ensureConnectionSetupActive(device);

    BluetoothCharacteristic? analog;
    BluetoothCharacteristic? digital;
    BluetoothCharacteristic? auth;
    BluetoothCharacteristic? status;

    _digitalChar = null;
    _authChar = null;
    _heartbeatChar = null;
    _analogOutChar = null;
    _digitalCharWriteNoResponse = false;
    var analogOutSeen = false;
    var analogOutFoundButNotWritable = false;
    final plcServiceUuid = BLEConstants.serviceUuid.toLowerCase();
    final analogOutUuid = BLEConstants.analogOutCharUuid.toLowerCase();

    for (final service in services) {
      final serviceUuid = service.uuid.toString().toLowerCase();
      final isPlcService = serviceUuid == plcServiceUuid;
      debugPrint(
        '[BLE] Service discovered: $serviceUuid '
        '| primary=${service.isPrimary} '
        '| chars=${service.characteristics.length}',
      );

      for (final char in service.characteristics) {
        final uuid = char.uuid.toString().toLowerCase();
        debugPrint(
          '[BLE] Char discovered: service=$serviceUuid chr=$uuid '
          '| write=${char.properties.write} '
          '| writeNoResp=${char.properties.writeWithoutResponse} '
          '| notify=${char.properties.notify}',
        );

        if (uuid == analogOutUuid) {
          analogOutSeen = true;
          final writable =
              char.properties.write || char.properties.writeWithoutResponse;
          if (writable) {
            _analogOutChar = char;
            debugPrint(
              '[BLE] Analog-out characteristic found on service '
              '$serviceUuid (write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse})',
            );
            if (!isPlcService) {
              _logger.w(
                'Analog-out characteristic was found outside the PLC '
                'service ($serviceUuid instead of '
                '${BLEConstants.serviceUuid}). The app will use it, but '
                'the firmware should expose it under the PLC service.',
              );
            }
          } else {
            analogOutFoundButNotWritable = true;
            _logger.w(
              'Analog-out characteristic found but it is not writable '
              '(service=$serviceUuid, uuid=$uuid). Firmware must enable '
              'PROPERTY_WRITE or PROPERTY_WRITE_NR.',
            );
          }
        }

        if (!isPlcService) {
          continue;
        }

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

      throw StateError('PLC service incomplete — missing: $missing.');
    }

    final analogChar = analog;
    final digitalChar = digital;
    final authChar = auth;
    final statusChar = status;

    final invalidCapabilities = [
      if (!digitalChar.properties.write &&
          !digitalChar.properties.writeWithoutResponse)
        'digital is not writable',
      if (!analogChar.properties.notify && !analogChar.properties.indicate)
        'analog cannot notify/indicate',
      if (!authChar.properties.write) 'auth does not support write requests',
      if (!authChar.properties.notify && !authChar.properties.indicate)
        'auth cannot notify/indicate',
      if (!statusChar.properties.notify && !statusChar.properties.indicate)
        'status cannot notify/indicate',
    ];
    if (invalidCapabilities.isNotEmpty) {
      throw StateError(
        'PLC characteristic capabilities are invalid: '
        '${invalidCapabilities.join(', ')}.',
      );
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
    if (_analogOutChar == null) {
      final reason = analogOutFoundButNotWritable
          ? 'it was found, but firmware did not mark it writable'
          : analogOutSeen
          ? 'it was found, but no usable writable instance was selected'
          : 'Android did not report that UUID in the discovered GATT table';
      debugPrint(
        '[BLE] WARNING: Analog-out characteristic NOT found '
        '(UUID: ${BLEConstants.analogOutCharUuid}). '
        'Analog output will be disabled because $reason.',
      );
    }

    _ensureConnectionSetupActive(device);
    _digitalChar = digitalChar;
    _authChar = authChar;

    _emit(BleConnectionStatus.configuringNotifications);

    // Attach listeners first so an immediate notification cannot be missed.
    final analogSubscription = analogChar.onValueReceived.listen(
      _handleAnalogNotification,
    );
    final authSubscription = authChar.onValueReceived.listen(
      _handleAuthNotification,
    );
    final statusSubscription = statusChar.onValueReceived.listen(
      _handleStatusNotification,
    );
    _analogSubscription = analogSubscription;
    _authSubscription = authSubscription;
    _statusSubscription = statusSubscription;

    device.cancelWhenDisconnected(analogSubscription, next: true);
    device.cancelWhenDisconnected(authSubscription, next: true);
    device.cancelWhenDisconnected(statusSubscription, next: true);

    await analogChar.setNotifyValue(true);
    _ensureConnectionSetupActive(device);
    await authChar.setNotifyValue(true);
    _ensureConnectionSetupActive(device);
    await statusChar.setNotifyValue(true);
    _ensureConnectionSetupActive(device);

    _emit(BleConnectionStatus.initializingSafeState);
    await _sendSafeStatePreAuthBestEffort();
    _ensureConnectionSetupActive(device);
    _emit(BleConnectionStatus.awaitingAuthentication);
  }

  void _ensureConnectionSetupActive(BluetoothDevice device) {
    if (_connectCancelled ||
        !identical(_device, device) ||
        device.isDisconnected) {
      throw StateError('BLE connection ended during service setup.');
    }
  }

  // ── Cancel Connecting ─────────────────────────────────────────────────────

  Future<void> cancelConnecting() async {
    const cancellableStatuses = {
      BleConnectionStatus.connecting,
      BleConnectionStatus.discoveringServices,
      BleConnectionStatus.configuringNotifications,
      BleConnectionStatus.initializingSafeState,
    };
    if (!cancellableStatuses.contains(_snapshot.status)) return;

    await disconnect();
  }

  // ── Connection helpers ─────────────────────────────────────────────────────

  Future<void> _clearConnectionState() async {
    final analogSubscription = _analogSubscription;
    final authSubscription = _authSubscription;
    final statusSubscription = _statusSubscription;
    final connectionSubscription = _connStateSub;

    _analogSubscription = null;
    _authSubscription = null;
    _statusSubscription = null;
    _connStateSub = null;
    _device = null;
    _connectedDevice = null;
    _digitalChar = null;
    _authChar = null;
    _heartbeatChar = null;
    _analogOutChar = null;
    _digitalCharWriteNoResponse = false;

    try {
      await Future.wait<void>([
        if (analogSubscription != null) analogSubscription.cancel(),
        if (authSubscription != null) authSubscription.cancel(),
        if (statusSubscription != null) statusSubscription.cancel(),
        if (connectionSubscription != null) connectionSubscription.cancel(),
      ]);
    } catch (e) {
      _logger.w('BLE subscription cleanup failed: $e');
    }
  }

  Future<void> _safeDisconnectDevice(BluetoothDevice? device) async {
    if (device == null) return;
    try {
      // queue:false also cancels a native connection that has not reached the
      // connected state yet; checking isConnected would miss that case.
      await device.disconnect(queue: false);
    } catch (e) {
      _logger.w('BLE disconnect cleanup failed: $e');
    }
  }

  void _endCryptoSession({required BleAuthOutcome authOutcome}) {
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _heartbeatWritePending = false;
    _encryptedWriteLane = Future<void>.value();
    BleCrypto.endSession();

    final pendingAuth = _pendingAuthCompleter;
    if (pendingAuth != null && !pendingAuth.isCompleted) {
      pendingAuth.complete(authOutcome);
    }
    _pendingAuthCompleter = null;
  }

  void _publishDisconnectedState({required bool emitConnectionState}) {
    _connectedDevice = null;
    _resetHoistValues(emit: !_isDisposing);
    if (!_isDisposing && !_statusController.isClosed) {
      _statusController.add(PlcOutputCommand.idle());
    }
    if (emitConnectionState) {
      _emit(BleConnectionStatus.disconnected);
      _freezeCache(forceEmit: true);
    }
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

  Future<void> disconnect({
    bool emitState = true,
    bool cancelPendingConnection = true,
  }) async {
    if (cancelPendingConnection) {
      _connectCancelled = true;
    }
    _stopRssiPolling();
    _stopHeartbeat();
    _endCryptoSession(authOutcome: BleAuthOutcome.failed);

    final device = _device;
    await _clearConnectionState();
    await _safeDisconnectDevice(device);
    _publishDisconnectedState(emitConnectionState: emitState);
  }

  // ── Run Disconnect ─────────────────────────────────────────────────────

  void _handleDisconnect() {
    if (_isDisposing) {
      return;
    }
    _stopRssiPolling();
    _stopHeartbeat();
    _endCryptoSession(authOutcome: BleAuthOutcome.timedOut);
    unawaited(_clearConnectionState());
    _publishDisconnectedState(emitConnectionState: true);
  }

  // ── Characteristic callbacks ───────────────────────────────────────────────
  // ── Decrypts hoist sensor packets and publishes H1/H2 snapshots ────

  void _handleAnalogNotification(List<int> bytes) {
    _rxPacketCount++;
    unawaited(_handleAnalogNotificationAsync(bytes));
  }

  Future<void> _handleAnalogNotificationAsync(List<int> bytes) async {
    if (!_sessionAuthenticated || !BleCrypto.sessionActive) {
      _logger.w(
        'Encrypted hoist notification received outside an authenticated '
        'session; ignored.',
      );
      return;
    }

    try {
      final decrypted = await _decryptNotification(bytes, label: 'analog');
      final payload = _tryDecodeUtf8(decrypted)?.trim();
      if (_applyHoistPayload(payload)) {
        return;
      }
      _logger.w('Invalid decrypted hoist payload ignored: "$payload"');
    } on _StaleBleSessionException catch (e) {
      _logger.w('Stale analog notification ignored: $e');
    } on BleCryptoException catch (e) {
      _logger.e('Encrypted analog notification rejected: $e');
      await _cryptoSafeState('Analog notification decrypt failed: $e');
    } on StateError catch (e) {
      _logger.e('Encrypted analog notification session error: $e');
      await _cryptoSafeState('Analog notification session error: $e');
    } catch (e) {
      _logger.e('Encrypted analog notification error: $e');
      await _cryptoSafeState('Analog notification error: $e');
    }
  }

  bool _applyHoistPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return false;
    }

    final notification = HoistNotification.tryParse(payload);
    if (notification == null) return false;

    _lastHoistValues.addAll(notification.values);
    if (!_analogController.isClosed) {
      _analogController.add(
        Map.unmodifiable(Map<String, int>.from(_lastHoistValues)),
      );
    }
    return true;
  }

  void _resetHoistValues({required bool emit}) {
    _lastHoistValues
      ..[HoistNotification.hoist1Key] = 0
      ..[HoistNotification.hoist2Key] = 0;
    if (emit && !_analogController.isClosed) {
      _analogController.add(
        Map.unmodifiable(Map<String, int>.from(_lastHoistValues)),
      );
    }
  }

  // ── Processes raw status bytes and sends them to the statusStream ──────────

  void _handleStatusNotification(List<int> bytes) {
    _rxPacketCount++;
    unawaited(_handleStatusNotificationAsync(bytes));
  }

  Future<void> _handleStatusNotificationAsync(List<int> bytes) async {
    if (!_sessionAuthenticated || !BleCrypto.sessionActive) {
      _logger.w(
        'Encrypted status notification received outside an authenticated '
        'session; ignored.',
      );
      return;
    }

    try {
      final decrypted = await _decryptNotification(bytes, label: 'status');
      final payload = _tryDecodeUtf8(decrypted)?.trim();
      final command = PlcOutputCommand.tryParseStatusNotification(decrypted);
      if (command == null) {
        _logger.w('Invalid decrypted PLC status payload ignored: "$payload"');
        return;
      }
      _logger.i('Decrypted PLC status payload: $payload');
      _publishStatus(command);
    } on _StaleBleSessionException catch (e) {
      _logger.w('Stale status notification ignored: $e');
    } on BleCryptoException catch (e) {
      _logger.e('Encrypted status notification rejected: $e');
      await _cryptoSafeState('Status notification decrypt failed: $e');
    } on StateError catch (e) {
      _logger.e('Encrypted status notification session error: $e');
      await _cryptoSafeState('Status notification session error: $e');
    } catch (e) {
      _logger.e('Encrypted status notification error: $e');
      await _cryptoSafeState('Status notification error: $e');
    }
  }

  void _publishStatus(PlcOutputCommand command) {
    _logger.i(
      'PLC status: estop=${command.estop} activeFields=${command.activeFields}',
    );
    if (!_isDisposing && !_statusController.isClosed) {
      _statusController.add(command);
    }
  }

  // ── Processes the crane controller's login response ────────────────────────

  void _handleAuthNotification(List<int> bytes) {
    _rxPacketCount++;
    unawaited(_handleAuthNotificationAsync(bytes));
  }

  // RUN Auth Notification
  Future<void> _handleAuthNotificationAsync(List<int> bytes) async {
    try {
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

      final decrypted = await _decryptNotification(bytes, label: 'auth');
      final encryptedPayload = _tryDecodeUtf8(decrypted)?.trim();
      if (await _handleAuthPayload(encryptedPayload, source: 'encrypted')) {
        return;
      }
      _logger.w(
        'Unknown encrypted auth notification payload: "$encryptedPayload"',
      );
    } on _StaleBleSessionException catch (e) {
      _logger.w('Stale auth notification ignored: $e');
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
    if (_digitalChar == null) return;
    try {
      await _sendSafeStateCommand().timeout(const Duration(milliseconds: 900));
      _logger.i('Pre-auth safe-state packet sent (best effort).');
    } catch (error) {
      _logger.w('Pre-auth safe-state write failed: ${error.toString()}');
    }
  }

  Future<void> _sendSafeStateCommand() async {
    final digitalChar = _digitalChar;
    if (digitalChar == null) {
      throw StateError('Digital characteristic is not ready.');
    }
    final plainBytes = PlcOutputCommand.emergencyStop().wireBytes.toList();
    await digitalChar.write(
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
      final pendingAuth = _pendingAuthCompleter;
      if (pendingAuth == null || pendingAuth.isCompleted) {
        _logger.w('Unsolicited auth success ignored ($source).');
        return true;
      }
      _logger.i('Auth notification ($source): $payload');
      await _finalizeAuthenticatedSession();
      return true;
    }

    final failureOutcome = _authFailureOutcome(payload);
    if (failureOutcome != null) {
      final pendingAuth = _pendingAuthCompleter;
      if (pendingAuth == null || pendingAuth.isCompleted) {
        _logger.w('Unsolicited auth failure ignored ($source): $payload');
        return true;
      }
      _logger.w('Auth notification ($source): $payload');
      _endCryptoSession(authOutcome: failureOutcome);
      _emit(BleConnectionStatus.error, message: payload);
      return true;
    }

    return false;
  }

  BleAuthOutcome? _authFailureOutcome(String payload) {
    if (payload == BLEConstants.authTimeout) {
      return BleAuthOutcome.timedOut;
    }

    if (payload == BLEConstants.authUntrusted) {
      return BleAuthOutcome.untrusted;
    }

    if (payload == BLEConstants.authFailed) {
      return BleAuthOutcome.failed;
    }

    if (!payload.startsWith(BLEConstants.authFailedPrefix)) {
      return null;
    }

    final reason = payload
        .substring(BLEConstants.authFailedPrefix.length)
        .trim()
        .toUpperCase();
    if (reason == BLEConstants.authUntrustedDeviceReason) {
      return BleAuthOutcome.untrusted;
    }

    return BleAuthOutcome.failed;
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
    if (_isDisposing || _cryptoSafeStateActive) return;
    _cryptoSafeStateActive = true;
    _commErrorCount++;

    _logger.e('CRYPTO SAFE STATE ENTERED: $reason');
    debugPrint('[SECURITY] Entering crypto safe state — reason: $reason');

    _emit(
      BleConnectionStatus.error,
      message: 'Security error — session terminated. Please reconnect.',
    );

    await disconnect(emitState: false);
  }

  // ── Completes the login ────────────────────────────────────────────────────

  Future<void> _finalizeAuthenticatedSession() async {
    final pendingAuth = _pendingAuthCompleter;
    final device = _device;
    if (pendingAuth == null || pendingAuth.isCompleted) {
      throw const _StaleBleSessionException(
        'Authentication completed without a pending request.',
      );
    }
    if (device == null || !device.isConnected || !BleCrypto.sessionActive) {
      throw const _StaleBleSessionException(
        'Authentication completed after the BLE session ended.',
      );
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await device.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        debugPrint('[BLE] Connection priority set to HIGH.');
      } catch (e) {
        _logger.w('Could not set connection priority: $e');
      }
    }

    if (!identical(_device, device) ||
        !device.isConnected ||
        !identical(_pendingAuthCompleter, pendingAuth) ||
        !BleCrypto.sessionActive) {
      throw const _StaleBleSessionException(
        'Authentication session changed while finalizing.',
      );
    }

    _sessionAuthenticated = true;
    _emit(BleConnectionStatus.authenticated);
    pendingAuth.complete(BleAuthOutcome.success);
    _pendingAuthCompleter = null;
    _startRssiPolling();
    _startHeartbeat();
  }

  // ── Autheticate the device ─────────────────────────────────────────────────

  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    if (_isDisposing) {
      throw StateError('BLE service has been disposed.');
    }
    final activeAuth = _activeAuthFuture;
    if (activeAuth != null) {
      _logger.w('Ignoring duplicate authentication request.');
      return activeAuth;
    }

    final authFuture = _authenticate(
      email: email,
      password: password,
      deviceId: deviceId,
    );
    _activeAuthFuture = authFuture;
    try {
      return await authFuture;
    } finally {
      if (identical(_activeAuthFuture, authFuture)) {
        _activeAuthFuture = null;
      }
    }
  }

  Future<BleAuthOutcome> _authenticate({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    final authChar = _authChar;
    final device = _device;
    if (authChar == null || device == null || !device.isConnected) {
      throw StateError('Authentication characteristic is not ready.');
    }

    _endCryptoSession(authOutcome: BleAuthOutcome.failed);
    _emit(BleConnectionStatus.authenticating);

    Completer<BleAuthOutcome>? pendingAuth;
    try {
      // Do not reset BleCrypto while a notification from the previous session
      // is still finishing AES-GCM work against its shared counters.
      await _encryptedReadLane;
      if (!identical(_device, device) || !device.isConnected) {
        throw StateError('BLE connection ended before authentication started.');
      }

      await BleCrypto.beginSession();
      if (!identical(_device, device) || !device.isConnected) {
        throw StateError('BLE connection ended during authentication setup.');
      }

      pendingAuth = Completer<BleAuthOutcome>();
      _pendingAuthCompleter = pendingAuth;

      final plaintext = utf8.encode('$email|$password|$deviceId');
      final encryptedAuth = await BleCrypto.encrypt(plaintext);

      if (!identical(_device, device) ||
          !identical(_authChar, authChar) ||
          !device.isConnected ||
          !identical(_pendingAuthCompleter, pendingAuth)) {
        throw StateError('BLE connection ended before authentication write.');
      }

      await authChar.write(encryptedAuth, withoutResponse: false);

      return await pendingAuth.future.timeout(
        SafetyConstants.authReplyTimeout,
        onTimeout: () {
          if (identical(_pendingAuthCompleter, pendingAuth)) {
            _endCryptoSession(authOutcome: BleAuthOutcome.timedOut);
          }
          _emit(
            BleConnectionStatus.awaitingAuthentication,
            message: 'PLC authentication timed out.',
          );
          return BleAuthOutcome.timedOut;
        },
      );
    } catch (_) {
      if (pendingAuth == null ||
          identical(_pendingAuthCompleter, pendingAuth)) {
        _endCryptoSession(authOutcome: BleAuthOutcome.failed);
      }
      rethrow;
    } finally {
      if (_snapshot.status != BleConnectionStatus.authenticated &&
          identical(_device, device) &&
          device.isConnected &&
          _snapshot.status != BleConnectionStatus.awaitingAuthentication &&
          _snapshot.status != BleConnectionStatus.error) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
    }
  }

  // ── Heartbeat helpers

  void _startHeartbeat() {
    _stopHeartbeat();
    final heartbeatChar = _heartbeatChar;
    if (heartbeatChar == null) {
      _logger.w('Heartbeat characteristic not found — heartbeat disabled.');
      return;
    }

    final useWithoutResponse = heartbeatChar.properties.writeWithoutResponse;
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
    _lastHeartbeatSuccessAt = null;
  }

  void _sendHeartbeatTick(bool useWithoutResponse) {
    if (!_heartbeatActive || _isDisposing) return;
    if (_heartbeatWritePending) return;
    final char = _heartbeatChar;
    if (char == null) return;
    final generation = _cryptoSessionGeneration;
    _heartbeatWritePending = true;
    // AES-128-GCM encrypted heartbeat — fire-and-forget.
    unawaited(
      _encryptAndSendHeartbeat(char, useWithoutResponse)
          .then((_) {
            if (generation == _cryptoSessionGeneration) {
              _lastHeartbeatSuccessAt = DateTime.now();
            }
          })
          .catchError((Object e) {
            _logger.w('Heartbeat write failed: $e');
            _commErrorCount++;
          })
          .whenComplete(() {
            if (generation == _cryptoSessionGeneration) {
              _heartbeatWritePending = false;
            }
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
    _rssiReadPending = false;
    final generation = ++_rssiPollGeneration;
    _rssiTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(_pollRssi(generation)),
    );
  }

  Future<void> _pollRssi(int generation) async {
    if (_rssiReadPending || generation != _rssiPollGeneration || _isDisposing) {
      return;
    }

    final device = _device;
    final connectedDevice = _connectedDevice;
    if (device == null || !device.isConnected || connectedDevice == null) {
      return;
    }

    _rssiReadPending = true;
    try {
      final rssi = await device.readRssi();
      if (_isDisposing ||
          generation != _rssiPollGeneration ||
          !identical(_device, device) ||
          _connectedDevice?.id != connectedDevice.id) {
        return;
      }

      _connectedDevice = connectedDevice.copyWith(rssi: rssi);
      _emit(_snapshot.status);
    } catch (e) {
      if (generation == _rssiPollGeneration && !_isDisposing) {
        _logger.w('RSSI poll failed: $e');
      }
    } finally {
      if (generation == _rssiPollGeneration) {
        _rssiReadPending = false;
      }
    }
  }

  // ── Stop RSSI polling ─────────────────────────────────────────────────────

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    _rssiPollGeneration++;
    _rssiReadPending = false;
  }

  // ── Write helpers ──────────────────────────────────────────────────────────

  Future<List<int>> _decryptNotification(
    List<int> wireBytes, {
    required String label,
  }) {
    final generation = _cryptoSessionGeneration;
    final readFuture = _encryptedReadLane.then((_) async {
      if (_isDisposing ||
          generation != _cryptoSessionGeneration ||
          !BleCrypto.sessionActive) {
        throw _StaleBleSessionException(
          'Encrypted $label notification belongs to an inactive session.',
        );
      }

      final List<int> plaintext;
      try {
        plaintext = await BleCrypto.decrypt(wireBytes);
      } catch (_) {
        if (_isDisposing || generation != _cryptoSessionGeneration) {
          throw _StaleBleSessionException(
            'Encrypted $label notification failed after its session ended.',
          );
        }
        rethrow;
      }
      if (_isDisposing || generation != _cryptoSessionGeneration) {
        throw _StaleBleSessionException(
          'Encrypted $label notification completed after its session ended.',
        );
      }
      return plaintext;
    });

    _encryptedReadLane = readFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.w('Encrypted BLE read lane recovered after $label: $error');
      },
    );

    return readFuture;
  }

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
      _txPacketCount++;
    });

    _encryptedWriteLane = writeFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.w('Encrypted BLE write lane recovered after $label: $error');
      },
    );

    return writeFuture;
  }

  Future<void> writeDigital(List<int> bytes) async {
    if (_isDisposing) return;
    final digitalChar = _digitalChar;
    if (digitalChar == null) return;
    if (_sessionAuthenticated) {
      try {
        await _writeEncryptedCharacteristic(
          characteristic: digitalChar,
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
    await digitalChar.write(
      bytes,
      withoutResponse: _digitalCharWriteNoResponse,
    );
    _txPacketCount++;
  }

  /// Writes an encrypted RANGE:A{n}-{min},{max} or DATA:A{n}-{value}[,...]
  /// command to the analog-out characteristic — see
  /// CraneController.setAnalogButtonValue for how those command strings are
  /// built. Unlike [writeDigital], there is no pre-auth plaintext fallback —
  /// the firmware's AnalogOutputCallbacks::onWrite only ever attempts
  /// decrypt+validate, so a write while unauthenticated is silently dropped
  /// by [_writeEncryptedCharacteristic] rather than sent in the clear.
  Future<void> writeAnalogOutput(List<int> bytes) async {
    if (_isDisposing) return;
    final char = _analogOutChar;
    if (char == null) {
      _logger.w(
        'Analog output write skipped — analog-out characteristic was never '
        'discovered (UUID: ${BLEConstants.analogOutCharUuid}). Check the '
        '"[BLE] Service discovered" and "[BLE] Char discovered" lines logged '
        'at connect time. If no chr=${BLEConstants.analogOutCharUuid} line '
        'appears, the firmware is not exposing that UUID in Android\'s GATT '
        'table. If it appears with write=false and writeNoResp=false, the '
        'firmware created it without write support.',
      );
      return;
    }
    if (!_sessionAuthenticated) {
      _logger.w('Analog output write skipped — session not authenticated yet.');
      return;
    }
    debugPrint('[BLE] Analog-out write: ${utf8.decode(bytes)}');
    try {
      await _writeEncryptedCharacteristic(
        characteristic: char,
        plaintext: bytes,
        withoutResponse: char.properties.writeWithoutResponse,
        label: 'analog-out',
      );
    } on BleCryptoException catch (e) {
      _logger.e('Encryption failure on analog-out write: $e');
      unawaited(_cryptoSafeState('BleCryptoException during encrypt: $e'));
    } on StateError catch (e) {
      _logger.e('Crypto session state error on analog-out write: $e');
      unawaited(_cryptoSafeState('StateError during encrypt: $e'));
    }
  }

  void dispose() {
    if (_isDisposing) return;
    _isDisposing = true;
    _connectCancelled = true;
    _scanContinue = false;
    _scanPaused = false;
    _scanSessionActive = false;
    _scanGeneration++;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    _stopRssiPolling();
    _stopHeartbeat();
    _endCryptoSession(authOutcome: BleAuthOutcome.failed);

    final device = _device;
    final scanSubscription = _scanResultsSub;
    _scanResultsSub = null;
    final connectionCleanup = _clearConnectionState();

    unawaited(
      _disposeResources(
        device: device,
        scanSubscription: scanSubscription,
        connectionCleanup: connectionCleanup,
      ),
    );
  }

  Future<void> _disposeResources({
    required BluetoothDevice? device,
    required StreamSubscription<List<ScanResult>>? scanSubscription,
    required Future<void> connectionCleanup,
  }) async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      _logger.w('BLE scan shutdown failed during dispose: $e');
    }

    try {
      await scanSubscription?.cancel();
    } catch (e) {
      _logger.w('BLE scan subscription cleanup failed: $e');
    }

    await connectionCleanup;
    await _safeDisconnectDevice(device);

    try {
      await Future.wait<void>([
        if (!_connectionController.isClosed) _connectionController.close(),
        if (!_scanController.isClosed) _scanController.close(),
        if (!_analogController.isClosed) _analogController.close(),
        if (!_statusController.isClosed) _statusController.close(),
      ]);
    } catch (e) {
      _logger.w('BLE stream cleanup failed during dispose: $e');
    }
  }
}
