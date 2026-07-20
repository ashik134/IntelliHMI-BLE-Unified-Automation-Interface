import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:rev_crane_control_ops/core/constants/ble_constants.dart';
import 'package:rev_crane_control_ops/core/constants/safety_constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/services/ble_crypto.dart';
import 'package:rev_crane_control_ops/services/ble_transport.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/ble_gateway_protocol.dart';

class RemoteBleTransport implements BleTransport {
  RemoteBleTransport({required this.host, required this.port});

  final String host;
  final int port;
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));

  final StreamController<bool> _readyController =
      StreamController<bool>.broadcast();
  final StreamController<BleConnectionState> _connectionController =
      StreamController<BleConnectionState>.broadcast();
  final StreamController<List<BleScanDevice>> _scanController =
      StreamController<List<BleScanDevice>>.broadcast();
  final StreamController<Map<String, int>> _analogController =
      StreamController<Map<String, int>>.broadcast();
  final StreamController<PlcOutputCommand> _statusController =
      StreamController<PlcOutputCommand>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  Stream<String> get logs => _logController.stream;

  @override
  bool get requiresLocalBluetooth => false;

  @override
  String get readinessLabel => 'Gateway';

  @override
  Stream<bool> get readyStream => _readyController.stream;

  @override
  Stream<BleConnectionState> get connectionStream =>
      _connectionController.stream;

  @override
  Stream<List<BleScanDevice>> get scanStream => _scanController.stream;

  @override
  Stream<Map<String, int>> get analogStream => _analogController.stream;

  @override
  Stream<PlcOutputCommand> get statusStream => _statusController.stream;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSub;
  bool _gatewayConnected = false;
  bool _isDisposing = false;

  BleConnectionState _snapshot = BleConnectionState.initial();
  BleScanDevice? _connectedDevice;
  final Map<String, BleScanDevice> _deviceCache = {};
  final Map<String, int> _lastAnalog = {'A1': 0, 'A2': 0};

  Completer<void>? _pendingConnectCompleter;
  Completer<BleAuthOutcome>? _pendingAuthCompleter;

  bool _sessionAuthenticated = false;
  int _cryptoSessionGeneration = 0;
  Future<void> _encryptedWriteLane = Future<void>.value();
  bool _digitalWriteFastPathEnabled = false;
  List<int>? _lastDigitalWireBytes;
  bool _lastDigitalWithoutResponse = true;
  int _digitalWriteRequestCount = 0;
  Timer? _heartbeatTimer;
  bool _heartbeatActive = false;
  bool _heartbeatWritePending = false;
  int _heartbeatWriteCount = 0;

  Future<void> connectGateway() async {
    if (_gatewayConnected) {
      return;
    }

    final uri = Uri(scheme: 'ws', host: host, port: port);
    _log('Connecting to phone gateway at $uri');
    final socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 6));

    _socket = socket;
    _gatewayConnected = true;
    _readyController.add(true);
    _log('Gateway WebSocket connected');

    _socketSub = socket.listen(
      _handleGatewayMessage,
      onDone: _handleGatewayClosed,
      onError: (Object error) {
        _log('Gateway WebSocket error: $error');
        _handleGatewayClosed();
      },
      cancelOnError: true,
    );
  }

  @override
  Future<bool> checkReady() async => _gatewayConnected;

  @override
  Future<void> ensureBluetoothReady() async {
    if (!_gatewayConnected) {
      throw StateError('Phone gateway WebSocket is not connected.');
    }
  }

  @override
  Future<void> startScan() async {
    await ensureBluetoothReady();
    _deviceCache.clear();
    _scanController.add(const []);
    _emit(BleConnectionStatus.scanning);
    _send({'type': BleGatewayProtocol.scan});
  }

  @override
  Future<void> pauseScan() async {
    if (!_gatewayConnected) {
      return;
    }
    _send({'type': BleGatewayProtocol.stopScan});
  }

  @override
  Future<void> resumeScan() async {
    await startScan();
  }

  @override
  Future<void> stopScan() async {
    if (_gatewayConnected) {
      _send({'type': BleGatewayProtocol.stopScan});
    }
    if (_snapshot.status == BleConnectionStatus.scanning) {
      _emit(BleConnectionStatus.disconnected);
    }
  }

  @override
  Future<void> connect(BleScanDevice scanDevice) async {
    await ensureBluetoothReady();
    _completePendingConnect();
    _pendingConnectCompleter = Completer<void>();

    await stopScan();
    await disconnect(emitState: false);

    _connectedDevice = scanDevice;
    _emit(BleConnectionStatus.connecting);
    _send({'type': BleGatewayProtocol.connect, 'deviceId': scanDevice.id});

    try {
      await _pendingConnectCompleter!.future.timeout(
        const Duration(seconds: 20),
      );
    } on TimeoutException {
      _emit(
        BleConnectionStatus.error,
        message: 'Phone gateway did not finish BLE connect in time.',
      );
    } finally {
      _pendingConnectCompleter = null;
    }
  }

  @override
  Future<void> cancelConnecting() async {
    _completePendingConnect();
    _pendingConnectCompleter = null;
    await disconnect();
  }

  @override
  Future<void> disconnect({bool emitState = true}) async {
    _completePendingAuth(BleAuthOutcome.failed);
    _sessionAuthenticated = false;
    _cryptoSessionGeneration++;
    _encryptedWriteLane = Future<void>.value();
    _lastDigitalWireBytes = null;
    _stopHeartbeat();
    BleCrypto.endSession();

    if (_gatewayConnected) {
      _send({'type': BleGatewayProtocol.disconnect});
    }

    _connectedDevice = null;
    _analogController.add(const {'A1': 0, 'A2': 0});
    _statusController.add(PlcOutputCommand.idle());
    if (emitState) {
      _emit(BleConnectionStatus.disconnected);
    }
  }

  @override
  Future<BleAuthOutcome> authenticate({
    required String email,
    required String password,
    required String deviceId,
  }) async {
    if (_connectedDevice == null) {
      throw StateError('Remote BLE device is not connected.');
    }

    _completePendingAuth(BleAuthOutcome.failed);
    _pendingAuthCompleter = Completer<BleAuthOutcome>();
    final authFuture = _pendingAuthCompleter!.future;
    _emit(BleConnectionStatus.authenticating);

    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _encryptedWriteLane = Future<void>.value();
    _stopHeartbeat();
    BleCrypto.endSession();
    await BleCrypto.beginSession();

    final plaintext = utf8.encode('$email|$password|$deviceId');
    final encryptedAuth = await BleCrypto.encrypt(plaintext);

    await _writeCharacteristic(
      type: BleGatewayProtocol.write,
      serviceUuid: BLEConstants.serviceUuid,
      characteristicUuid: BLEConstants.authCharUuid,
      bytes: encryptedAuth,
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
          _connectedDevice != null &&
          _snapshot.status != BleConnectionStatus.error) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
    }
  }

  @override
  Future<void> writeDigital(List<int> bytes) async {
    if (_connectedDevice == null) {
      return;
    }

    if (_sessionAuthenticated) {
      try {
        await _writeEncryptedCharacteristic(
          plaintext: bytes,
          withoutResponse: true,
          label: 'digital',
        );
        return;
      } on BleCryptoException catch (error) {
        _logger.e('Remote encryption failure on digital write: $error');
        unawaited(_cryptoSafeState('BleCryptoException during encrypt: $error'));
        return;
      } on StateError catch (error) {
        _logger.e('Remote crypto state error on digital write: $error');
        unawaited(_cryptoSafeState('StateError during encrypt: $error'));
        return;
      }
    }

    await _writeDigitalCharacteristic(
      bytes: bytes,
      withoutResponse: true,
    );
  }

  @override
  Future<void> writeAuth(List<int> bytes) async {
    await _writeCharacteristic(
      type: BleGatewayProtocol.write,
      serviceUuid: BLEConstants.serviceUuid,
      characteristicUuid: BLEConstants.authCharUuid,
      bytes: bytes,
      withoutResponse: false,
    );
  }

  Future<void> readCharacteristic({
    required String serviceUuid,
    required String characteristicUuid,
  }) async {
    await ensureBluetoothReady();
    _send({
      'type': BleGatewayProtocol.read,
      'serviceUuid': serviceUuid,
      'characteristicUuid': characteristicUuid,
    });
  }

  Future<void> _writeEncryptedCharacteristic({
    required List<int> plaintext,
    required bool withoutResponse,
    required String label,
  }) {
    final generation = _cryptoSessionGeneration;
    final writeFuture = _encryptedWriteLane.then((_) async {
      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _connectedDevice == null) {
        return;
      }

      final wireBytes = await BleCrypto.encrypt(plaintext);

      if (_isDisposing ||
          !_sessionAuthenticated ||
          generation != _cryptoSessionGeneration ||
          _connectedDevice == null) {
        return;
      }

      await _writeDigitalCharacteristic(
        bytes: wireBytes,
        withoutResponse: withoutResponse,
      );
    });

    _encryptedWriteLane = writeFuture.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _logger.w(
          'Remote encrypted write lane recovered after $label: $error',
        );
      },
    );

    return writeFuture;
  }

  Future<void> _writeDigitalCharacteristic({
    required List<int> bytes,
    required bool withoutResponse,
  }) async {
    final type = _digitalWriteFastPathEnabled
        ? BleGatewayProtocol.digitalWrite
        : BleGatewayProtocol.write;
    await _writeCharacteristic(
      type: type,
      serviceUuid: type == BleGatewayProtocol.write
          ? BLEConstants.serviceUuid
          : null,
      characteristicUuid: type == BleGatewayProtocol.write
          ? BLEConstants.digitalCharUuid
          : null,
      bytes: bytes,
      withoutResponse: withoutResponse,
    );
  }

  Future<void> _writeCharacteristic({
    required String type,
    String? serviceUuid,
    String? characteristicUuid,
    required List<int> bytes,
    required bool withoutResponse,
  }) async {
    await ensureBluetoothReady();
    if (type == BleGatewayProtocol.digitalWrite) {
      _lastDigitalWireBytes = List<int>.unmodifiable(bytes);
      _lastDigitalWithoutResponse = withoutResponse;
    }
    _send({
      'type': type,
      if (serviceUuid != null) 'serviceUuid': serviceUuid,
      if (characteristicUuid != null) 'characteristicUuid': characteristicUuid,
      'value': BleGatewayProtocol.encodeBytes(bytes),
      'encoding': 'base64',
      'withoutResponse': withoutResponse,
      'sentAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    if (type == BleGatewayProtocol.digitalWrite) {
      _digitalWriteRequestCount++;
      if (_digitalWriteRequestCount == 1 ||
          _digitalWriteRequestCount % 25 == 0) {
        _log(
          'Digital write requests sent: $_digitalWriteRequestCount '
          '(${bytes.length} byte latest)',
        );
      }
    } else if (characteristicUuid?.toLowerCase() !=
        BLEConstants.heartbeatCharUuid.toLowerCase()) {
      _log('Write request $characteristicUuid: ${bytes.length} byte(s)');
    }
  }

  void _handleGatewayMessage(dynamic raw) {
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = message['type']?.toString();
      switch (type) {
        case BleGatewayProtocol.scanResult:
          _handleScanResult(message);
        case BleGatewayProtocol.bleStatus:
          _handleBleStatus(message);
        case BleGatewayProtocol.notification:
          _handleNotification(message);
        case BleGatewayProtocol.readResult:
          _log('Read result received from gateway');
        case BleGatewayProtocol.error:
          _handleGatewayError(message['message']?.toString());
        case BleGatewayProtocol.log:
          _log(message['message']?.toString() ?? 'Gateway log');
        default:
          _log('Ignoring unknown gateway message: $type');
      }
    } catch (error) {
      _handleGatewayError('Invalid gateway message: $error');
    }
  }

  void _handleScanResult(Map<String, dynamic> message) {
    final id = message['deviceId']?.toString();
    if (id == null || id.isEmpty) {
      return;
    }

    final device = BleScanDevice(
      id: id,
      name: message['name']?.toString().trim().isNotEmpty == true
          ? message['name'].toString()
          : 'Remote PLC',
      rssi: (message['rssi'] as num?)?.toInt() ?? 0,
      device: BluetoothDevice.fromId(id),
      plcType: BleGatewayProtocol.plcTypeFromWire(
        message['plcType']?.toString(),
      ),
    );

    _deviceCache[id] = device;
    _scanController.add(List.unmodifiable(_deviceCache.values));
    _log('Scan result ${device.name} ${device.id} ${device.rssi} dBm');
  }

  void _handleBleStatus(Map<String, dynamic> message) {
    final status = BleGatewayProtocol.statusFromWire(
      message['state']?.toString(),
    );
    final remoteDevice = _deviceFromStatusMessage(message);
    if (remoteDevice != null) {
      _connectedDevice = remoteDevice;
    }

    if (status == BleConnectionStatus.disconnected) {
      _handleDisconnect();
      return;
    }

    if (status == BleConnectionStatus.error) {
      _emit(status, message: message['message']?.toString());
      _completePendingConnect();
      _completePendingAuth(BleAuthOutcome.failed);
      return;
    }

    _emit(status, message: message['message']?.toString());
    if (status == BleConnectionStatus.awaitingAuthentication ||
        status == BleConnectionStatus.connected) {
      _completePendingConnect();
    }
  }

  BleScanDevice? _deviceFromStatusMessage(Map<String, dynamic> message) {
    final id = message['deviceId']?.toString();
    if (id == null || id.isEmpty) {
      return _connectedDevice;
    }

    final plcType = BleGatewayProtocol.plcTypeFromWire(
      message['plcType']?.toString(),
    );

    return BleScanDevice(
      id: id,
      name: message['name']?.toString().trim().isNotEmpty == true
          ? message['name'].toString()
          : _connectedDevice?.name ?? 'Remote PLC',
      rssi: (message['rssi'] as num?)?.toInt() ?? _connectedDevice?.rssi ?? 0,
      device: BluetoothDevice.fromId(id),
      plcType: plcType != PlcType.unknown
          ? plcType
          : _connectedDevice?.plcType ?? PlcType.unknown,
    );
  }

  void _handleNotification(Map<String, dynamic> message) {
    final characteristicUuid = message['characteristicUuid']
        ?.toString()
        .toLowerCase();
    if (characteristicUuid == null) {
      return;
    }

    final bytes = BleGatewayProtocol.decodeBytes(
      message['value'],
      encoding: message['encoding'],
    );
    _log('Notification $characteristicUuid: ${bytes.length} byte(s)');

    if (characteristicUuid == BLEConstants.analogCharUuid.toLowerCase()) {
      _handleAnalogNotification(bytes);
    } else if (characteristicUuid == BLEConstants.statusCharUuid.toLowerCase()) {
      _handleStatusNotification(bytes);
    } else if (characteristicUuid == BLEConstants.authCharUuid.toLowerCase()) {
      _handleAuthNotification(bytes);
    }
  }

  void _handleGatewayError(String? message) {
    final text = message ?? 'Phone gateway reported an unknown error.';
    if (text.contains(
      'Unsupported gateway command: ${BleGatewayProtocol.digitalWrite}',
    )) {
      _digitalWriteFastPathEnabled = false;
      _log(
        'Phone gateway does not support digitalWrite; falling back to generic write.',
      );
      final bytes = _lastDigitalWireBytes;
      if (bytes != null) {
        unawaited(
          _writeCharacteristic(
            type: BleGatewayProtocol.write,
            serviceUuid: BLEConstants.serviceUuid,
            characteristicUuid: BLEConstants.digitalCharUuid,
            bytes: bytes,
            withoutResponse: _lastDigitalWithoutResponse,
          ),
        );
      }
      return;
    }
    _log('Gateway error: $text');
    _emit(BleConnectionStatus.error, message: text);
    _completePendingConnect();
    _completePendingAuth(BleAuthOutcome.failed);
  }

  void _handleAnalogNotification(List<int> bytes) {
    final payload = utf8.decode(bytes).trim();
    final parts = payload.split(',');

    try {
      final updated = Map<String, int>.from(_lastAnalog);
      for (final part in parts) {
        final kv = part.split(':');
        if (kv.length != 2) {
          _logger.w('Unexpected remote analog token: $part');
          continue;
        }
        final key = kv[0].trim();
        final value = int.parse(kv[1].trim());
        if (updated.containsKey(key)) {
          updated[key] = value;
        } else {
          _logger.w('Unknown remote analog key: $key');
        }
      }
      _lastAnalog
        ..['A1'] = updated['A1']!
        ..['A2'] = updated['A2']!;
      _analogController.add(Map.unmodifiable(updated));
    } catch (error) {
      _logger.e('Remote analog parse error', error: error);
    }
  }

  void _handleStatusNotification(List<int> bytes) {
    final command = PlcOutputCommand.fromStatusNotification(bytes);
    _logger.i(
      'Remote PLC status: estop=${command.estop} '
      'dir=${command.direction} speed=${command.speed}',
    );
    _statusController.add(command);
  }

  void _handleAuthNotification(List<int> bytes) {
    unawaited(_handleAuthNotificationAsync(bytes));
  }

  Future<void> _handleAuthNotificationAsync(List<int> bytes) async {
    final plainPayload = _tryDecodeUtf8(bytes)?.trim();
    if (await _handleAuthPayload(plainPayload, source: 'plain')) {
      return;
    }

    if (_pendingAuthCompleter == null || !BleCrypto.sessionActive) {
      if (plainPayload == null) {
        _logger.w(
          'Remote auth notification: non-UTF8 data (${bytes.length} bytes) ignored.',
        );
      } else {
        _logger.w('Unknown remote auth notification payload: "$plainPayload"');
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
        'Unknown encrypted remote auth notification payload: "$encryptedPayload"',
      );
    } on BleCryptoException catch (error) {
      _logger.e('Encrypted remote auth notification rejected: $error');
      await _cryptoSafeState('Auth response decrypt failed: $error');
    } on StateError catch (error) {
      _logger.e('Encrypted remote auth notification session error: $error');
      await _cryptoSafeState('Auth response session error: $error');
    } catch (error) {
      _logger.e('Encrypted remote auth notification error: $error');
      await _cryptoSafeState('Auth response error: $error');
    }
  }

  Future<bool> _handleAuthPayload(
    String? payload, {
    required String source,
  }) async {
    if (payload == null || payload.isEmpty) {
      return false;
    }

    if (payload.startsWith('AUTH_REQ:')) {
      _logger.i('Remote auth notification ($source): AUTH_REQ');
      if (_snapshot.status != BleConnectionStatus.authenticated) {
        _emit(BleConnectionStatus.awaitingAuthentication);
      }
      return true;
    }

    if (payload == BLEConstants.authSuccess) {
      _logger.i('Remote auth notification ($source): $payload');
      await _finalizeAuthenticatedSession();
      return true;
    }

    if (payload == BLEConstants.authUntrusted) {
      _logger.w('Remote auth notification ($source): $payload');
      _failAuth(BleAuthOutcome.untrusted, payload);
      return true;
    }

    if (payload == BLEConstants.authFailed ||
        payload == BLEConstants.authTimeout) {
      _logger.w('Remote auth notification ($source): $payload');
      _failAuth(
        payload == BLEConstants.authTimeout
            ? BleAuthOutcome.timedOut
            : BleAuthOutcome.failed,
        payload,
      );
      return true;
    }

    return false;
  }

  void _failAuth(BleAuthOutcome outcome, String message) {
    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _encryptedWriteLane = Future<void>.value();
    _stopHeartbeat();
    BleCrypto.endSession();
    _completePendingAuth(outcome);
    _emit(BleConnectionStatus.error, message: message);
  }

  Future<void> _finalizeAuthenticatedSession() async {
    if (!BleCrypto.sessionActive) {
      await BleCrypto.beginSession();
    }

    _sessionAuthenticated = true;
    _emit(BleConnectionStatus.authenticated);
    _startHeartbeat();
    _completePendingAuth(BleAuthOutcome.success);
    _log('Remote PLC session authenticated');
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatActive = true;
    _heartbeatTimer = Timer.periodic(
      SafetyConstants.heartbeatInterval,
      (_) => _sendHeartbeatTick(),
    );
    _sendHeartbeatTick();
    _log('Remote PLC heartbeat started');
  }

  void _stopHeartbeat() {
    _heartbeatActive = false;
    _heartbeatWritePending = false;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _sendHeartbeatTick() {
    if (!_heartbeatActive || _isDisposing || !_sessionAuthenticated) {
      return;
    }
    if (_heartbeatWritePending) {
      return;
    }

    _heartbeatWritePending = true;
    unawaited(
      _encryptAndSendHeartbeat()
          .catchError((Object error) {
            _logger.w('Remote heartbeat write failed: $error');
          })
          .whenComplete(() {
            _heartbeatWritePending = false;
          }),
    );
  }

  Future<void> _encryptAndSendHeartbeat() async {
    if (!_heartbeatActive || _isDisposing || !_sessionAuthenticated) {
      return;
    }

    final wireBytes = await BleCrypto.encrypt(
      utf8.encode(BLEConstants.heartbeatPayload),
    );

    if (!_heartbeatActive || _isDisposing || !_sessionAuthenticated) {
      return;
    }

    await _writeCharacteristic(
      type: BleGatewayProtocol.write,
      serviceUuid: BLEConstants.serviceUuid,
      characteristicUuid: BLEConstants.heartbeatCharUuid,
      bytes: wireBytes,
      withoutResponse: true,
    );

    _heartbeatWriteCount++;
    if (_heartbeatWriteCount == 1 || _heartbeatWriteCount % 100 == 0) {
      _log('Remote PLC heartbeats sent: $_heartbeatWriteCount');
    }
  }

  Future<void> _cryptoSafeState(String reason) async {
    if (_isDisposing) {
      return;
    }

    _logger.e('REMOTE CRYPTO SAFE STATE ENTERED: $reason');

    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _encryptedWriteLane = Future<void>.value();
    _stopHeartbeat();
    BleCrypto.endSession();

    _completePendingAuth(BleAuthOutcome.failed);

    _emit(
      BleConnectionStatus.error,
      message: 'Remote security error - session terminated. Please reconnect.',
    );

    await disconnect(emitState: false);
  }

  String? _tryDecodeUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return null;
    }
  }

  void _handleDisconnect() {
    if (_isDisposing) {
      return;
    }

    _cryptoSessionGeneration++;
    _sessionAuthenticated = false;
    _encryptedWriteLane = Future<void>.value();
    _stopHeartbeat();
    BleCrypto.endSession();
    _completePendingAuth(BleAuthOutcome.timedOut);
    _completePendingConnect();
    _connectedDevice = null;
    _analogController.add(const {'A1': 0, 'A2': 0});
    _statusController.add(PlcOutputCommand.idle());
    _emit(BleConnectionStatus.disconnected);
  }

  void _handleGatewayClosed() {
    if (_isDisposing) {
      return;
    }
    _log('Gateway WebSocket closed');
    _gatewayConnected = false;
    _readyController.add(false);
    _socket = null;
    _connectedDevice = null;
    _stopHeartbeat();
    _completePendingConnect();
    _completePendingAuth(BleAuthOutcome.failed);
    _emit(
      BleConnectionStatus.error,
      message: 'Phone gateway WebSocket disconnected.',
    );
  }

  void _completePendingConnect() {
    final pending = _pendingConnectCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _pendingConnectCompleter = null;
  }

  void _completePendingAuth(BleAuthOutcome outcome) {
    final pending = _pendingAuthCompleter;
    if (pending != null && !pending.isCompleted) {
      pending.complete(outcome);
    }
    _pendingAuthCompleter = null;
  }

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

  void _send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      throw StateError('Phone gateway WebSocket is not connected.');
    }
    socket.add(jsonEncode(message));
  }

  void _log(String message) {
    final line = '${DateTime.now().toIso8601String()}  $message';
    debugPrint('[REMOTE-BLE] $message');
    if (!_logController.isClosed) {
      _logController.add(line);
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _socketSub?.cancel();
    _socket?.close(WebSocketStatus.normalClosure, 'Remote transport disposed');
    _socket = null;
    _gatewayConnected = false;
    _stopHeartbeat();
    BleCrypto.endSession();
    _readyController.close();
    _connectionController.close();
    _scanController.close();
    _analogController.close();
    _statusController.close();
    _logController.close();
  }
}
