import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/services/ble_service.dart';
import 'package:rev_crane_control_ops/services/permission_service.dart';
import 'package:rev_crane_control_ops/utils/preferences.dart';

enum HoistState { idle, upSlow, upFast, downSlow, downFast }

class CraneController extends ChangeNotifier {
  final BleService _bleService = BleService();
  final PermissionService _permissionService = PermissionService();
  final AppPreferences _preferences = AppPreferences();

  StreamSubscription<BleConnectionState>? _connStateSubscription;
  StreamSubscription<List<BleScanDevice>>? _scanSubscription;
  StreamSubscription<Map<String, int>>? _analogSubscription;
  StreamSubscription<PlcOutputCommand>? _statusSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  BleConnectionState _transportConnState = BleConnectionState.initial();
  List<BleScanDevice> _devices = const [];
  Map<String, int> _analogValues = {};
  PlcOutputCommand _activeCommand = PlcOutputCommand.idle();

  // ── BLE write serializer ──────────────────────────────────────────────────
  // Prevents BLE queue flooding when commands arrive faster than writes complete.
  // Only one write is in flight at a time; the latest pending command wins.
  bool _commandInFlight = false;
  List<int>? _pendingCommandBytes;

  bool _initializing = true;
  Future<void>? _initializeFuture;
  bool _streamsAttached = false;
  PermissionState _permissionState = const PermissionState.initial();
  bool _bluetoothReady = false;
  bool _permissionBannerDismissed = false;
  bool _rememberCredentials = true;
  bool _estopLatched = false;
  String? _sessionEmail;
  String? _errorMessage;
  String _savedEmail = '';
  String _savedPassword = '';
  // bool _conflictActive = false;
  // bool _upActive = false;
  // bool _downActive = false;
  // bool _fastActive = false;

  bool _cancellingConnection = false;
  BleScanDevice? _cancellingDevice;

  bool get isInitializing => _initializing;
  bool get bluetoothReady => _bluetoothReady;
  bool get permissionsGranted => _permissionState.isGranted;
  bool get showPermissionBanner =>
      !permissionsGranted && !_permissionBannerDismissed;

  void dismissPermissionBanner() {
    _permissionBannerDismissed = true;
    notifyListeners();
  }
  //  bool get conflictActive => _conflictActive;
  //  bool get upActive => _upActive;
  // bool get downActive => _downActive;
  // bool get fastActive => _fastActive;

  bool get rememberCredentials => _rememberCredentials;
  PlcOutputCommand get activeCommand => _activeCommand;
  bool get estopLatched => _estopLatched;
  String? get sessionEmail => _sessionEmail;
  String? get errorMessage => _errorMessage ?? _transportConnState.message;
  List<BleScanDevice> get devices => _devices;
  Map<String, int> get analogValues => _analogValues;
  String get savedEmail => _savedEmail;
  String get savedPassword => _savedPassword;
  //////////////////////////////////////////////////////////////////////////
  BleConnectionState get connectionState => _transportConnState;
  bool get isScanning =>
      _transportConnState.status == BleConnectionStatus.scanning;
  bool get isConnecting =>
      _transportConnState.status == BleConnectionStatus.connecting;
  bool get isDiscoveringServices =>
      _transportConnState.status == BleConnectionStatus.discoveringServices;
  bool get isConfiguringNotifications =>
      _transportConnState.status ==
      BleConnectionStatus.configuringNotifications;
  bool get isInitializingSafeState =>
      _transportConnState.status == BleConnectionStatus.initializingSafeState;
  bool get isAuthenticating =>
      _transportConnState.status == BleConnectionStatus.authenticating;
  bool get isAuthenticated =>
      _transportConnState.status == BleConnectionStatus.authenticated;
  bool get isAwaitingAuthentication =>
      _transportConnState.status == BleConnectionStatus.awaitingAuthentication;
  bool get isConnected =>
      _transportConnState.status == BleConnectionStatus.connected ||
      _transportConnState.status == BleConnectionStatus.authenticated;
  bool get isDisconnected =>
      _transportConnState.status == BleConnectionStatus.disconnected;
  bool get isConnectionActive =>
      _transportConnState.status == BleConnectionStatus.connecting ||
      _transportConnState.status == BleConnectionStatus.discoveringServices ||
      _transportConnState.status ==
          BleConnectionStatus.configuringNotifications ||
      _transportConnState.status == BleConnectionStatus.initializingSafeState ||
      _transportConnState.status ==
          BleConnectionStatus.awaitingAuthentication ||
      _transportConnState.status == BleConnectionStatus.authenticating;
  ////////////////////////////////////////////////////////////////////////////////////////////
  // ── Analog sensor values ────────────────────────────────────────────────
  int get a1 => _analogValues['A1'] ?? 0;
  int get a2 => _analogValues['A2'] ?? 0;

  // ── LED indicator states (sourced from PLC) ───────────────────────────────
  bool get ledEstop => _activeCommand.estop;
  bool get ledUp =>
      _activeCommand.direction == HoistDirection.up && !_activeCommand.estop;
  bool get ledDown =>
      _activeCommand.direction == HoistDirection.down && !_activeCommand.estop;
  bool get ledFast =>
      _activeCommand.speed == HoistSpeed.fast && !_activeCommand.estop;

  bool get isCancellingConnection => _cancellingConnection;
  BleScanDevice? get cancellingDevice => _cancellingDevice;

  // ── Connected device name ─────────────────────────────────────────────────
  String? get connectedDeviceName => _transportConnState.connectedDevice?.name;

  // ── Hoist state derived from active command ───────────────────────────────
  HoistState get hoistState {
    if (_activeCommand.estop) return HoistState.idle;
    return switch ((_activeCommand.direction, _activeCommand.speed)) {
      (HoistDirection.up, HoistSpeed.slow) => HoistState.upSlow,
      (HoistDirection.up, HoistSpeed.fast) => HoistState.upFast,
      (HoistDirection.down, HoistSpeed.slow) => HoistState.downSlow,
      (HoistDirection.down, HoistSpeed.fast) => HoistState.downFast,
      _ => HoistState.idle,
    };
  }

  //  ControlState get upStage {
  //   if (_estopLatched || _conflictActive || !_upActive) {
  //     return ControlState.idle;
  //   }
  //   return _fastActive ? ControlState.fast : ControlState.slow;
  // }

  //  ControlState get downStage {
  //   if (_estopLatched || _conflictActive || !_downActive) {
  //     return ControlState.idle;
  //   }
  //   return _fastActive ? ControlState.fast : ControlState.slow;
  // }

  String get statusLabel => _activeCommand.statusLabel;

  AppScreen get currentScreen => switch (_transportConnState.status) {
    BleConnectionStatus.authenticated => AppScreen.control,
    BleConnectionStatus.awaitingAuthentication ||
    BleConnectionStatus.authenticating => AppScreen.authentication,
    BleConnectionStatus.error
        when _transportConnState.connectedDevice != null =>
      AppScreen.authentication,
    _ => AppScreen.connection,
  };

  // Future<void> sendCommand({
  //   required bool estop,
  //   required bool up,
  //   required bool down,
  //   required bool fast,
  //   bool conflict = false,
  // }) async {
  //   if (estop) {
  //     _estopLatched = true;
  //     _upActive = false;
  //     _downActive = false;
  //     _fastActive = false;
  //     _conflictActive = false;
  //     notifyListeners();
  //     debugPrint("E-STOP ACTIVATED! Sending E-STOP command to PLC...");
  //     return;
  //   }

  //   if (_conflictActive && !conflict) {
  //     return;
  //   }

  //   if (conflict || (up && down)) {
  //     _conflictActive = true;
  //     _upActive = false;
  //     _downActive = false;
  //     _fastActive = false;
  //     notifyListeners();
  //     debugPrint("CONFLICT DETECTED! Sending conflict state to PLC...");
  //     return;
  //   }
  //   _estopLatched= false;
  //   _conflictActive = false;
  //   _upActive = up;
  //   _downActive = down;
  //   _fastActive = fast && (_upActive || _downActive);
  //   notifyListeners();
  // }
  //  void clearConflict() {
  //   _conflictActive = false;
  //   _upActive = false;
  //   _downActive = false;
  //   _fastActive = false;
  //   notifyListeners();
  // }

  bool verifyLocalPassword(String password) {
    return password == 'Admin123';
  }

  // Initialization and Cleanup //////////////////////////////////////////////////////////////////////////////
  Future<void> initialize() {
    if (_initializeFuture != null) {
      return _initializeFuture!;
    }

    _initializing = true;
    notifyListeners();
    _initializeFuture = _initializeInternal();
    return _initializeFuture!;
  }

  Future<void> _initializeInternal() async {
    _attachStreamsIfNeeded();

    try {
      final values = await Future.wait<String?>([
        _preferences.getEmail(),
        _preferences.getPassword(),
      ]);
      _savedEmail = values[0] ?? '';
      _savedPassword = values[1] ?? '';
      _rememberCredentials =
          _savedEmail.isNotEmpty && _savedPassword.isNotEmpty;

      await _prepareRunTime();
      debugPrint(
        'Initialization complete. Bluetooth ready: $bluetoothReady, Permissions granted: $permissionsGranted',
      );
    } catch (error) {
      _errorMessage = 'Startup initialization failed. $error';
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  void _attachStreamsIfNeeded() {
    if (_streamsAttached) {
      return;
    }
    _streamsAttached = true;

    _connStateSubscription = _bleService.connectionStream.listen((snapshot) {
      _transportConnState = snapshot;
      if (snapshot.status == BleConnectionStatus.disconnected) {
        _activeCommand = PlcOutputCommand.idle();
        _estopLatched = false;
        _sessionEmail = null;
      }
      notifyListeners();
    });

    _scanSubscription = _bleService.scanStream.listen((devices) {
      _devices = devices;
      notifyListeners();
    });

    _analogSubscription = _bleService.analogStream.listen((values) {
      _analogValues = values;
      notifyListeners();
    });

    _statusSubscription = _bleService.statusStream.listen((command) {
      _activeCommand = command;
      _estopLatched = command.estop;
      notifyListeners();
    });

    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _bluetoothReady = state == BluetoothAdapterState.on;
      notifyListeners();
    });
  }

  Future<void> _prepareRunTime() async {
    _permissionState = await _permissionService.requestPermissions();
    if (permissionsGranted) {
      await enableBluetooth();
    }
  }

  Future<void> refreshPermissions() async {
    _permissionState = await _permissionService.requestPermissions();
    _permissionBannerDismissed = false;
    if (permissionsGranted) {
      await enableBluetooth();
    }
    notifyListeners();
  }

  Future<void> openSettings() async {
    await _permissionService.openSettings();
  }

  Future<void> enableBluetooth() async {
    try {
      await _bleService.ensureBluetoothReady();
      final state = await FlutterBluePlus.adapterState.first;
      _bluetoothReady = state == BluetoothAdapterState.on;
    } catch (e) {
      _errorMessage =
          'Bluetooth must be enabled before scanning for PLC 14. Please enable Bluetooth and try again.';
    }
    notifyListeners();
  }

  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  /// Device Scanning and Connection //////////////////////////////////////////////////////////////////////////////////
  Future<void> scanForDevices() async {
    _errorMessage = null;

    if (!permissionsGranted) {
      await refreshPermissions();
      if (!permissionsGranted) {
        _errorMessage =
            'Required permissions not granted. Please grant permissions and try again.';
        notifyListeners();
        return;
      }
    }
    if (!bluetoothReady) {
      await enableBluetooth();
      if (!bluetoothReady) {
        _errorMessage =
            'Bluetooth is not enabled. Please enable Bluetooth and try again.';
        notifyListeners();
        return;
      }
    }
    try {
      await _bleService.startScan();
    } catch (e) {
      _errorMessage = _friendlyScanError(e);
      notifyListeners();
    }
  }

  String _friendlyScanError(Object error) {
    final message = error.toString();

    if (message.contains('ACCESS_FINE_LOCATION')) {
      return 'This Android device is requesting location access for BLE scan. '
          'Please allow location permission once, then scan again.';
    }

    if (message.contains('BLUETOOTH_SCAN')) {
      return 'Bluetooth scan permission was denied.';
    }

    if (message.contains('Location services are required for Bluetooth scan')) {
      return 'Android location services are turned off. Enable them and try again.';
    }

    return 'Failed to start PLC scan. $message';
  }

  //////////////////////////////////////////////////////////////////////////////////////////////

  Future<void> connectToDevice(BleScanDevice device) async {
    _errorMessage = null;

    try {
      await _bleService.connect(device);
    } catch (e) {
      _errorMessage = 'Could not connect to ${device.name}: ${e.toString()}';
      notifyListeners();
    }
  }

  void setRememberCredentials(bool value) {
    _rememberCredentials = value;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _errorMessage = null;
    await _bleService.disconnect();
    notifyListeners();
  }

  Future<void> stopScan() async {
    _errorMessage = null;
    await _bleService.stopScan();
    // State transitions via _connStateSubscription when startScan() resolves.
  }

  // ── Command helpers ───────────────────────────────────────────────────────

  Future<void> _sendCommand(PlcOutputCommand command) async {
    _activeCommand = command;
    notifyListeners();
    final bytes = command.wireBytes.toList();
    if (_commandInFlight) {
      // Replace whatever was pending — latest command wins.
      _pendingCommandBytes = bytes;
      return;
    }
    await _writeBytes(bytes);
  }

  Future<void> _writeBytes(List<int> bytes) async {
    _commandInFlight = true;
    try {
      await _bleService.writeDigital(bytes);
      // Drain at most one pending command queued while this write was in flight.
      final next = _pendingCommandBytes;
      _pendingCommandBytes = null;
      if (next != null) {
        _commandInFlight = false;
        await _writeBytes(next);
        return;
      }
    } catch (e) {
      _pendingCommandBytes = null;
      _errorMessage = 'Failed to send command: ${e.toString()}';
      notifyListeners();
    }
    _commandInFlight = false;
  }

  Future<void> triggerEStop() async {
    _estopLatched = true;
    final cmd = PlcOutputCommand.emergencyStop();
    _activeCommand = cmd;
    notifyListeners();
    final bytes = cmd.wireBytes.toList();
    // E-stop bypasses the serializer: preempts any pending command and sends
    // immediately after the current in-flight write (or right now if idle).
    _pendingCommandBytes = bytes;
    if (!_commandInFlight) {
      final pending = _pendingCommandBytes!;
      _pendingCommandBytes = null;
      await _writeBytes(pending);
    }
    // If a write is in flight it will drain _pendingCommandBytes next,
    // ensuring the E-stop is the very next thing written.
  }

  Future<void> resetEStop() async {
    _estopLatched = false;
    await _sendCommand(PlcOutputCommand.idle());
  }

  Future<void> tapHoistButton({required bool isUp}) async {
    if (_estopLatched || !isConnected) return;
    final PlcOutputCommand next;
    if (isUp) {
      next = switch (hoistState) {
        HoistState.upSlow => PlcOutputCommand.motion(
          direction: HoistDirection.up,
          speed: HoistSpeed.fast,
        ),
        HoistState.upFast => PlcOutputCommand.idle(),
        _ => PlcOutputCommand.motion(
          direction: HoistDirection.up,
          speed: HoistSpeed.slow,
        ),
      };
    } else {
      next = switch (hoistState) {
        HoistState.downSlow => PlcOutputCommand.motion(
          direction: HoistDirection.down,
          speed: HoistSpeed.fast,
        ),
        HoistState.downFast => PlcOutputCommand.idle(),
        _ => PlcOutputCommand.motion(
          direction: HoistDirection.down,
          speed: HoistSpeed.slow,
        ),
      };
    }
    await _sendCommand(next);
  }

  Future<void> setHoistCommand({
    required bool isUp,
    required ControlState state,
  }) async {
    if (_estopLatched || !isConnected) return;
    final PlcOutputCommand cmd = switch (state) {
      ControlState.idle => PlcOutputCommand.idle(),
      ControlState.slow => PlcOutputCommand.motion(
        direction: isUp ? HoistDirection.up : HoistDirection.down,
        speed: HoistSpeed.slow,
      ),
      ControlState.fast => PlcOutputCommand.motion(
        direction: isUp ? HoistDirection.up : HoistDirection.down,
        speed: HoistSpeed.fast,
      ),
    };
    await _sendCommand(cmd);
  }

  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    _errorMessage = null;

    try {
      final outcome = await _bleService.authenticate(
        email: email.trim(),
        password: password,
      );

      if (outcome == BleAuthOutcome.success) {
        _sessionEmail = email.trim();
        if (_rememberCredentials) {
          await _preferences.saveCredentials(email.trim(), password);
          _savedEmail = email.trim();
          _savedPassword = password;
        } else {
          await _preferences.clearCredentials();
          _savedEmail = '';
          _savedPassword = '';
        }
        notifyListeners();
        return true;
      }

      _errorMessage = outcome == BleAuthOutcome.timedOut
          ? 'PLC authentication timed out.'
          : 'Credentials were rejected by PLC 14.';
      notifyListeners();
      return false;
    } catch (error) {
      _errorMessage = 'Authentication failed. $error';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _connStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _analogSubscription?.cancel();
    _statusSubscription?.cancel();
    _adapterSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
