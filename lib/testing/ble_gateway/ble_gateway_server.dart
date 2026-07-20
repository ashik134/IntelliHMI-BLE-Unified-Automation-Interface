import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rev_crane_control_ops/core/constants/ble_constants.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/services/permission_service.dart';
import 'package:rev_crane_control_ops/testing/ble_gateway/ble_gateway_protocol.dart';

class BleGatewayServerSnapshot {
  const BleGatewayServerSnapshot({
    required this.running,
    required this.port,
    required this.ipAddresses,
    required this.tabletConnected,
    required this.bleStatus,
    this.connectedDeviceId,
    this.connectedDeviceName,
    this.lastError,
  });

  const BleGatewayServerSnapshot.initial()
    : running = false,
      port = BleGatewayProtocol.defaultPort,
      ipAddresses = const [],
      tabletConnected = false,
      bleStatus = BleConnectionStatus.disconnected,
      connectedDeviceId = null,
      connectedDeviceName = null,
      lastError = null;

  final bool running;
  final int port;
  final List<String> ipAddresses;
  final bool tabletConnected;
  final BleConnectionStatus bleStatus;
  final String? connectedDeviceId;
  final String? connectedDeviceName;
  final String? lastError;

  BleGatewayServerSnapshot copyWith({
    bool? running,
    int? port,
    List<String>? ipAddresses,
    bool? tabletConnected,
    BleConnectionStatus? bleStatus,
    String? connectedDeviceId,
    String? connectedDeviceName,
    String? lastError,
    bool clearDevice = false,
    bool clearError = false,
  }) {
    return BleGatewayServerSnapshot(
      running: running ?? this.running,
      port: port ?? this.port,
      ipAddresses: ipAddresses ?? this.ipAddresses,
      tabletConnected: tabletConnected ?? this.tabletConnected,
      bleStatus: bleStatus ?? this.bleStatus,
      connectedDeviceId: clearDevice
          ? null
          : connectedDeviceId ?? this.connectedDeviceId,
      connectedDeviceName: clearDevice
          ? null
          : connectedDeviceName ?? this.connectedDeviceName,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class BleGatewayServer {
  BleGatewayServer({PermissionService? permissionService})
    : _permissionService = permissionService ?? PermissionService();

  final PermissionService _permissionService;

  final StreamController<BleGatewayServerSnapshot> _snapshotController =
      StreamController<BleGatewayServerSnapshot>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  Stream<BleGatewayServerSnapshot> get snapshots => _snapshotController.stream;
  Stream<String> get logs => _logController.stream;

  BleGatewayServerSnapshot _snapshot =
      const BleGatewayServerSnapshot.initial();

  BleGatewayServerSnapshot get snapshot => _snapshot;

  HttpServer? _server;
  WebSocket? _client;
  BluetoothDevice? _device;
  BleScanDevice? _connectedScanDevice;

  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  final List<StreamSubscription<List<int>>> _notificationSubs = [];
  final Map<String, BluetoothCharacteristic> _characteristics = {};
  final Map<String, BleScanDevice> _scanDeviceCache = {};
  final Set<String> _sentScanKeys = {};

  Future<void> _clientCommandLane = Future<void>.value();
  bool _digitalWriteActive = false;
  List<int>? _pendingDigitalBytes;
  bool _pendingDigitalWithoutResponse = true;
  int _digitalWriteCount = 0;
  int _heartbeatWriteCount = 0;
  bool _disposed = false;

  Future<void> start({int port = BleGatewayProtocol.defaultPort}) async {
    if (_server != null) {
      return;
    }

    _log('Starting gateway server on port $port');
    await _ensureBleReady();

    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    final ips = await localIpv4Addresses();
    _updateSnapshot(
      _snapshot.copyWith(
        running: true,
        port: server.port,
        ipAddresses: ips,
        clearError: true,
      ),
    );

    _log('Gateway server listening on ${server.address.address}:${server.port}');
    unawaited(_serve(server));
  }

  Future<void> stop() async {
    _log('Stopping gateway server');
    await _closeClient();
    await _disconnectBle(emitState: false);
    await _stopScan(emitDisconnected: false);
    await _server?.close(force: true);
    _server = null;
    _updateSnapshot(
      _snapshot.copyWith(
        running: false,
        tabletConnected: false,
        bleStatus: BleConnectionStatus.disconnected,
        clearDevice: true,
      ),
    );
  }

  Future<List<String>> localIpv4Addresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final addresses = <String>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          addresses.add(address.address);
        }
      }
    }
    return addresses;
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _attachClient(socket);
        } else {
          request.response
            ..statusCode = HttpStatus.ok
            ..write('BLE gateway WebSocket is running.');
          await request.response.close();
        }
      }
    } catch (error) {
      if (!_disposed) {
        _setError('Gateway server stopped: $error');
      }
    }
  }

  void _attachClient(WebSocket socket) {
    _log('Tablet connected from ${socket.hashCode}');
    unawaited(_client?.close(WebSocketStatus.goingAway, 'New tablet client'));
    _client = socket;
    _updateSnapshot(_snapshot.copyWith(tabletConnected: true, clearError: true));
    _sendBleStatus(_snapshot.bleStatus);

    socket.listen(
      _queueClientMessage,
      onDone: () {
        if (_client == socket) {
          _log('Tablet disconnected');
          _client = null;
          _updateSnapshot(_snapshot.copyWith(tabletConnected: false));
          unawaited(_disconnectBle(emitState: false));
        }
      },
      onError: (Object error) {
        _setError('Tablet WebSocket error: $error');
      },
      cancelOnError: true,
    );
  }

  void _queueClientMessage(dynamic raw) {
    _clientCommandLane = _clientCommandLane.then((_) {
      return _handleClientMessage(raw);
    }).catchError((Object error, StackTrace stackTrace) {
      _sendError('Gateway command failed: $error');
    });
  }

  Future<void> _handleClientMessage(dynamic raw) async {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (error) {
      _sendError('Invalid JSON message: $error');
      return;
    }

    final type = message['type']?.toString();
    final isHeartbeatWrite =
        type == BleGatewayProtocol.write &&
        _normalizeUuid(message['characteristicUuid']?.toString() ?? '') ==
            BLEConstants.heartbeatCharUuid.toLowerCase();
    if (type != BleGatewayProtocol.digitalWrite && !isHeartbeatWrite) {
      _log('Tablet command: ${type ?? 'unknown'}');
    }

    try {
      switch (type) {
        case BleGatewayProtocol.scan:
          await _startScan();
        case BleGatewayProtocol.stopScan:
          await _stopScan();
        case BleGatewayProtocol.connect:
          await _connect(message['deviceId']?.toString());
        case BleGatewayProtocol.disconnect:
          await _disconnectBle();
        case BleGatewayProtocol.digitalWrite:
          await _enqueueDigitalWrite(message);
        case BleGatewayProtocol.write:
          await _writeCharacteristic(message);
        case BleGatewayProtocol.read:
          await _readCharacteristic(message);
        default:
          _sendError('Unsupported gateway command: $type');
      }
    } catch (error) {
      _sendError(error.toString());
    }
  }

  Future<void> _ensureBleReady() async {
    final permissions = await _permissionService.requestPermissions();
    if (!permissions.isGranted) {
      throw StateError('Bluetooth permissions are not granted on the phone.');
    }

    if (!kIsWeb && Platform.isAndroid) {
      final state = await FlutterBluePlus.adapterState.first;
      if (state != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    }
  }

  Future<void> _startScan() async {
    await _ensureBleReady();
    await _stopScan(emitDisconnected: false);
    _sentScanKeys.clear();
    _scanDeviceCache.clear();
    _setBleStatus(BleConnectionStatus.scanning);

    _scanSub = FlutterBluePlus.scanResults.listen(
      (results) {
        for (final result in results) {
          if (!BleScanDevice.matchesPlcFilter(result)) {
            continue;
          }

          final device = BleScanDevice.fromScanResult(result);
          _scanDeviceCache[device.id] = device;
          final key = '${device.id}:${device.rssi}:${device.name}';
          if (!_sentScanKeys.add(key)) {
            continue;
          }

          _send({
            'type': BleGatewayProtocol.scanResult,
            'deviceId': device.id,
            'name': device.name,
            'rssi': device.rssi,
            'plcType': BleGatewayProtocol.plcTypeToWire(device.plcType),
          });
          _log('Scan result: ${device.name} ${device.id} ${device.rssi} dBm');
        }
      },
      onError: (Object error) {
        _sendError('BLE scan error: $error');
      },
    );

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      androidScanMode: AndroidScanMode.balanced,
    );

    unawaited(
      FlutterBluePlus.isScanning.where((scanning) => !scanning).first.then((_) {
        if (_snapshot.bleStatus == BleConnectionStatus.scanning) {
          _setBleStatus(BleConnectionStatus.disconnected);
        }
      }),
    );
  }

  Future<void> _stopScan({bool emitDisconnected = true}) async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
    if (emitDisconnected && _snapshot.bleStatus == BleConnectionStatus.scanning) {
      _setBleStatus(BleConnectionStatus.disconnected);
    }
  }

  Future<void> _connect(String? deviceId) async {
    if (deviceId == null || deviceId.isEmpty) {
      throw ArgumentError('connect requires deviceId.');
    }

    await _ensureBleReady();
    await _stopScan(emitDisconnected: false);
    await _disconnectBle(emitState: false);

    final cachedDevice = _scanDeviceCache[deviceId];
    final device = cachedDevice?.device ?? BluetoothDevice.fromId(deviceId);
    final scanDevice =
        cachedDevice ??
        BleScanDevice(
          id: deviceId,
          name: device.platformName.isNotEmpty
              ? device.platformName
              : 'Remote PLC',
          rssi: 0,
          device: device,
        );
    _connectedScanDevice = scanDevice;
    _device = device;
    _setBleStatus(
      BleConnectionStatus.connecting,
      deviceId: scanDevice.id,
      deviceName: scanDevice.name,
    );

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 12),
        license: License.commercial,
      );
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await device.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high,
          );
          _log('BLE connection priority set to HIGH');
        } catch (error) {
          _log('BLE connection priority request skipped: $error');
        }
      }
      _connectionSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _log('BLE device disconnected');
          unawaited(_clearBleConnection(emitState: true));
        }
      });
      device.cancelWhenDisconnected(
        _connectionSub!,
        delayed: true,
        next: true,
      );

      await _discoverAndSubscribe();
    } catch (error) {
      await _clearBleConnection(emitState: false);
      _sendError('BLE connect failed: $error');
      _setBleStatus(BleConnectionStatus.error, message: error.toString());
    }
  }

  Future<void> _discoverAndSubscribe() async {
    final device = _device;
    if (device == null) {
      throw StateError('No BLE device is selected.');
    }

    _setBleStatus(BleConnectionStatus.discoveringServices);

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final mtu = await device.requestMtu(512);
        _log('BLE MTU negotiated: $mtu');
      } catch (error) {
        _log('BLE MTU request skipped: $error');
      }
    }

    final services = await device.discoverServices();
    _characteristics.clear();

    for (final service in services) {
      for (final characteristic in service.characteristics) {
        final serviceUuid = _normalizeUuid(service.uuid.toString());
        final charUuid = _normalizeUuid(characteristic.uuid.toString());
        _characteristics[_charKey(serviceUuid, charUuid)] = characteristic;
        _log(
          'Characteristic: $charUuid write=${characteristic.properties.write} '
          'writeNoResp=${characteristic.properties.writeWithoutResponse} '
          'notify=${characteristic.properties.notify} '
          'indicate=${characteristic.properties.indicate}',
        );
      }
    }

    _verifyRequiredPlcCharacteristics();
    _setBleStatus(BleConnectionStatus.configuringNotifications);

    for (final characteristic in _characteristics.values) {
      if (!characteristic.properties.notify &&
          !characteristic.properties.indicate) {
        continue;
      }

      await characteristic.setNotifyValue(true);
      final sub = characteristic.onValueReceived.listen((bytes) {
        _send({
          'type': BleGatewayProtocol.notification,
          'serviceUuid': _normalizeUuid(characteristic.serviceUuid.toString()),
          'characteristicUuid': _normalizeUuid(
            characteristic.characteristicUuid.toString(),
          ),
          'value': BleGatewayProtocol.encodeBytes(bytes),
          'encoding': 'base64',
        });
        _log(
          'Notification ${characteristic.characteristicUuid}: ${bytes.length} byte(s)',
        );
      });
      _notificationSubs.add(sub);
      _device?.cancelWhenDisconnected(sub, next: true);
    }

    _setBleStatus(BleConnectionStatus.initializingSafeState);
    await _sendPreAuthSafeState();
    _setBleStatus(BleConnectionStatus.awaitingAuthentication);
  }

  void _verifyRequiredPlcCharacteristics() {
    final missing = <String>[
      if (_findCharacteristic(
            BLEConstants.serviceUuid,
            BLEConstants.analogCharUuid,
          ) ==
          null)
        'analog',
      if (_findCharacteristic(
            BLEConstants.serviceUuid,
            BLEConstants.digitalCharUuid,
          ) ==
          null)
        'digital',
      if (_findCharacteristic(BLEConstants.serviceUuid, BLEConstants.authCharUuid) ==
          null)
        'auth',
      if (_findCharacteristic(
            BLEConstants.serviceUuid,
            BLEConstants.statusCharUuid,
          ) ==
          null)
        'status',
    ];

    if (missing.isNotEmpty) {
      throw StateError('PLC service incomplete, missing: ${missing.join(', ')}');
    }
  }

  Future<void> _sendPreAuthSafeState() async {
    final digital = _findCharacteristic(
      BLEConstants.serviceUuid,
      BLEConstants.digitalCharUuid,
    );
    if (digital == null) {
      return;
    }

    try {
      await digital.write(
        utf8.encode('[1,0,0,0]'),
        withoutResponse: digital.properties.writeWithoutResponse,
      );
      _log('Pre-auth safe state sent');
    } catch (error) {
      _log('Pre-auth safe state failed: $error');
    }
  }

  Future<void> _writeCharacteristic(Map<String, dynamic> message) async {
    final serviceUuid = message['serviceUuid']?.toString();
    final characteristicUuid = message['characteristicUuid']?.toString();
    final characteristic = _findCharacteristic(serviceUuid, characteristicUuid);
    if (characteristic == null) {
      throw StateError(
        'Characteristic not found: $serviceUuid/$characteristicUuid',
      );
    }

    final bytes = BleGatewayProtocol.decodeBytes(
      message['value'],
      encoding: message['encoding'],
    );
    final requestedWithoutResponse = message['withoutResponse'] == true;
    final withoutResponse =
        requestedWithoutResponse &&
        characteristic.properties.writeWithoutResponse;

    await characteristic.write(bytes, withoutResponse: withoutResponse);
    if (_normalizeUuid(characteristicUuid ?? '') ==
        BLEConstants.heartbeatCharUuid.toLowerCase()) {
      _heartbeatWriteCount++;
      if (_heartbeatWriteCount == 1 || _heartbeatWriteCount % 100 == 0) {
        _log('Heartbeat writes forwarded: $_heartbeatWriteCount');
      }
      return;
    }
    _log(
      'Write ${characteristic.characteristicUuid}: ${bytes.length} byte(s), '
      'withoutResponse=$withoutResponse',
    );
  }

  Future<void> _enqueueDigitalWrite(Map<String, dynamic> message) async {
    final digital = _findCharacteristic(
      BLEConstants.serviceUuid,
      BLEConstants.digitalCharUuid,
    );
    if (digital == null) {
      throw StateError('Digital characteristic is not ready.');
    }

    final bytes = BleGatewayProtocol.decodeBytes(
      message['value'],
      encoding: message['encoding'],
    );
    final requestedWithoutResponse = message['withoutResponse'] == true;

    if (_digitalWriteActive) {
      _pendingDigitalBytes = bytes;
      _pendingDigitalWithoutResponse = requestedWithoutResponse;
      return;
    }

    unawaited(
      _drainDigitalWrites(
        digital,
        initialBytes: bytes,
        initialWithoutResponse: requestedWithoutResponse,
        sentAtMs: (message['sentAtMs'] as num?)?.toInt(),
      ),
    );
  }

  Future<void> _drainDigitalWrites(
    BluetoothCharacteristic digital, {
    required List<int> initialBytes,
    required bool initialWithoutResponse,
    int? sentAtMs,
  }) async {
    _digitalWriteActive = true;
    var bytes = initialBytes;
    var requestedWithoutResponse = initialWithoutResponse;
    var sourceSentAtMs = sentAtMs;

    try {
      while (true) {
        final withoutResponse =
            requestedWithoutResponse &&
            digital.properties.writeWithoutResponse;
        await digital.write(bytes, withoutResponse: withoutResponse);
        _digitalWriteCount++;

        if (_digitalWriteCount == 1 || _digitalWriteCount % 25 == 0) {
          final lag = sourceSentAtMs == null
              ? null
              : DateTime.now().millisecondsSinceEpoch - sourceSentAtMs;
          _log(
            'Digital writes forwarded: $_digitalWriteCount'
            '${lag == null ? '' : ' latestLag=${lag}ms'}',
          );
        }

        final next = _pendingDigitalBytes;
        if (next == null) {
          break;
        }

        bytes = next;
        requestedWithoutResponse = _pendingDigitalWithoutResponse;
        sourceSentAtMs = null;
        _pendingDigitalBytes = null;
      }
    } catch (error) {
      _sendError('BLE digital write failed: $error');
    } finally {
      _digitalWriteActive = false;
    }
  }

  Future<void> _readCharacteristic(Map<String, dynamic> message) async {
    final serviceUuid = message['serviceUuid']?.toString();
    final characteristicUuid = message['characteristicUuid']?.toString();
    final characteristic = _findCharacteristic(serviceUuid, characteristicUuid);
    if (characteristic == null) {
      throw StateError(
        'Characteristic not found: $serviceUuid/$characteristicUuid',
      );
    }

    final bytes = await characteristic.read();
    _send({
      'type': BleGatewayProtocol.readResult,
      'serviceUuid': _normalizeUuid(characteristic.serviceUuid.toString()),
      'characteristicUuid': _normalizeUuid(
        characteristic.characteristicUuid.toString(),
      ),
      'value': BleGatewayProtocol.encodeBytes(bytes),
      'encoding': 'base64',
    });
    _log('Read ${characteristic.characteristicUuid}: ${bytes.length} byte(s)');
  }

  BluetoothCharacteristic? _findCharacteristic(
    String? serviceUuid,
    String? characteristicUuid,
  ) {
    if (serviceUuid == null || characteristicUuid == null) {
      return null;
    }
    return _characteristics[_charKey(serviceUuid, characteristicUuid)];
  }

  Future<void> _disconnectBle({bool emitState = true}) async {
    await _clearBleConnection(emitState: emitState, disconnectDevice: true);
  }

  Future<void> _clearBleConnection({
    required bool emitState,
    bool disconnectDevice = false,
  }) async {
    await _connectionSub?.cancel();
    _connectionSub = null;
    for (final sub in _notificationSubs) {
      await sub.cancel();
    }
    _notificationSubs.clear();
    _characteristics.clear();
    _pendingDigitalBytes = null;
    _digitalWriteActive = false;
    _heartbeatWriteCount = 0;

    final device = _device;
    _device = null;
    _connectedScanDevice = null;

    if (disconnectDevice && device != null && device.isConnected) {
      await device.disconnect();
    }

    if (emitState) {
      _setBleStatus(BleConnectionStatus.disconnected, clearDevice: true);
    } else {
      _updateSnapshot(
        _snapshot.copyWith(
          bleStatus: BleConnectionStatus.disconnected,
          clearDevice: true,
          clearError: true,
        ),
      );
    }
  }

  void _setBleStatus(
    BleConnectionStatus status, {
    String? message,
    String? deviceId,
    String? deviceName,
    bool clearDevice = false,
  }) {
    final connected = _connectedScanDevice;
    _updateSnapshot(
      _snapshot.copyWith(
        bleStatus: status,
        connectedDeviceId: deviceId ?? connected?.id,
        connectedDeviceName: deviceName ?? connected?.name,
        lastError: message,
        clearDevice: clearDevice,
        clearError: message == null,
      ),
    );
    _sendBleStatus(status, message: message, clearDevice: clearDevice);
  }

  void _sendBleStatus(
    BleConnectionStatus status, {
    String? message,
    bool clearDevice = false,
  }) {
    final connected = clearDevice ? null : _connectedScanDevice;
    _send({
      'type': BleGatewayProtocol.bleStatus,
      'state': BleGatewayProtocol.statusToWire(status),
      if (message != null) 'message': message,
      if (connected != null) ...{
        'deviceId': connected.id,
        'name': connected.name,
        'rssi': connected.rssi,
        'plcType': BleGatewayProtocol.plcTypeToWire(connected.plcType),
      },
    });
  }

  void _sendError(String message) {
    _setError(message);
    _send({'type': BleGatewayProtocol.error, 'message': message});
  }

  void _setError(String message) {
    _log('ERROR: $message');
    _updateSnapshot(_snapshot.copyWith(lastError: message));
  }

  void _send(Map<String, dynamic> message) {
    final client = _client;
    if (client == null || client.readyState != WebSocket.open) {
      return;
    }
    client.add(jsonEncode(message));
  }

  void _updateSnapshot(BleGatewayServerSnapshot snapshot) {
    _snapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void _log(String message) {
    final line = '${DateTime.now().toIso8601String()}  $message';
    debugPrint('[BLE-GATEWAY] $message');
    if (!_logController.isClosed) {
      _logController.add(line);
    }
  }

  Future<void> _closeClient() async {
    final client = _client;
    _client = null;
    await client?.close(WebSocketStatus.normalClosure, 'Gateway stopped');
  }

  String _charKey(String serviceUuid, String characteristicUuid) {
    return '${_normalizeUuid(serviceUuid)}/${_normalizeUuid(characteristicUuid)}';
  }

  String _normalizeUuid(String uuid) => uuid.toLowerCase();

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _snapshotController.close();
    await _logController.close();
  }
}
