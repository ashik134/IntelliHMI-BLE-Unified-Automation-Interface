import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/services/biometric_service.dart';
import 'package:rev_crane_control_ops/services/device_identity_service.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';
import 'package:rev_crane_control_ops/services/ble_service.dart';
import 'package:rev_crane_control_ops/services/permission_service.dart';
import 'package:rev_crane_control_ops/services/secure_credential_store.dart';
import 'package:rev_crane_control_ops/utils/constants.dart';
import 'package:rev_crane_control_ops/utils/preferences.dart';
import 'package:rev_crane_control_ops/utils/button_state_log.dart';

class CraneController extends ChangeNotifier with WidgetsBindingObserver {
  final BleService _bleService = BleService();
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  final PermissionService _permissionService = PermissionService();
  final AppPreferences _preferences = AppPreferences();

  StreamSubscription<BleConnectionState>? _connStateSubscription;
  StreamSubscription<List<BleScanDevice>>? _scanSubscription;
  StreamSubscription<Map<String, int>>? _analogSubscription;
  StreamSubscription<PlcOutputCommand>? _statusSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;

  BleConnectionState _transportConnState = BleConnectionState.initial();
  BleConnectionStatus _lastConnectionStatus = BleConnectionStatus.disconnected;
  List<BleScanDevice> _devices = const [];
  Map<String, int> _analogValues = {};

  PlcOutputCommand _activeCommand = PlcOutputCommand.idle();

  // ── BLE write serializer ──────────────────────────────────────────────────

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
  bool _startupEmergencyArmedForConnection = false;
  bool _biometricAvailable = false;
  bool _biometricEnrolled = false;

  bool _pendingEnrollmentOffer = false;
  String? _sessionEmail;
  String? _errorMessage;
  String _savedEmail = '';
  String _savedPassword = '';
  String _deviceId = '';

  bool _deviceTrustRejected = false;

  // ── PLC38 independent axis states ─────────────────────────────────────────
  bool _p38VertIsUp = true;
  ControlState _p38VertState = ControlState.idle;
  bool _p38TravIsLeft = true;
  ControlState _p38TravState = ControlState.idle;
  bool _p38TripIsForward = true;
  ControlState _p38TripState = ControlState.idle;

  // ── Button-centric PLC38 state ────────────────────────────────────────────
  // buttonId -> ControlState. Independent of the legacy _p38* fields above —
  // populated only when the button-centric screens call setButtonCommand.
  // The two paths are mutually exclusive in practice (a screen either fully
  // uses the legacy per-axis setters or fully uses setButtonCommand), but
  // both compose into the same PlcOutputCommand shape so either can be live
  // during the incremental migration (see CraneController.setButtonCommand).
  final Map<String, ControlState> _p38ButtonStates = {};

  // ── Shared-field ownership ────────────────────────────────────────────────
  // PlcMapping field → the buttonId that currently owns (actively asserts)
  // that field. Enforces the invariant that each PLC field is driven by at
  // most one button at a time. A second button attempting to activate the
  // same field while it is already owned is silently discarded; the UI layer
  // reads isFieldBlockedForButton() to clamp the slider before the drag
  // reaches the zone boundary, giving a physical "stuck" sensation.
  final Map<PlcMapping, String> _fieldOwners = {};
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
  bool get isBiometricAvailable => _biometricAvailable;
  bool get isBiometricEnrolled => _biometricEnrolled;

  bool get hasPendingEnrollmentOffer => _pendingEnrollmentOffer;
  PlcOutputCommand get activeCommand => _activeCommand;
  bool get estopLatched => _estopLatched;
  String? get sessionEmail => _sessionEmail;
  String? get errorMessage => _errorMessage ?? _transportConnState.message;
  List<BleScanDevice> get devices => _devices;
  Map<String, int> get analogValues => _analogValues;
  String get savedEmail => _savedEmail;
  String get savedPassword => _savedPassword;

  /// The PLC model type detected from BLE manufacturer data during scan.
  PlcType get connectedPlcType =>
      _transportConnState.connectedDevice?.plcType ?? PlcType.unknown;

  // ── PLC38 axis state getters ───────────────────────────────────────────────
  TraverseDirection get traverseDir => _activeCommand.traverseDirection;
  bool get traverseFast => _activeCommand.fastLr && !_activeCommand.estop;
  TravelDirection get travelDir => _activeCommand.travelDirection;
  bool get travelFast => _activeCommand.fastFb && !_activeCommand.estop;
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
  String get deviceId => _deviceId;

  bool get isDeviceTrustRejected => _deviceTrustRejected;

  bool get isCancellingConnection => _cancellingConnection;

  BleScanDevice? get cancellingDevice => _cancellingDevice;

  // ── Analog sensor values ────────────────────────────────────────────────
  int get a1 => _analogValues['A1'] ?? 0;
  int get a2 => _analogValues['A2'] ?? 0;

  // ── LED indicator states (sourced from PLC) ───────────────────────────────
  bool get ledEstop => _activeCommand.estop;
  bool get ledUp => _activeCommand.up && !_activeCommand.estop;
  bool get ledDown => _activeCommand.down && !_activeCommand.estop;
  bool get ledFast => _activeCommand.fastUd && !_activeCommand.estop;
  // PLC38 extended LED states
  bool get ledLeft => _activeCommand.left && !_activeCommand.estop;
  bool get ledRight => _activeCommand.right && !_activeCommand.estop;
  bool get ledFastLr => _activeCommand.fastLr && !_activeCommand.estop;
  bool get ledForward => _activeCommand.forward && !_activeCommand.estop;
  bool get ledReverse => _activeCommand.reverse && !_activeCommand.estop;
  bool get ledFastFb => _activeCommand.fastFb && !_activeCommand.estop;

  // ── Connected device name ─────────────────────────────────────────────────
  String? get connectedDeviceName => _transportConnState.connectedDevice?.name;
  int? get connectedDeviceRssi => _transportConnState.connectedDevice?.rssi;

  String get connectedDeviceTitle {
    final name = connectedDeviceName ?? BLEConstants.deviceName;
    final plc = connectedPlcType;
    if (plc != PlcType.unknown) {
      return '$name \u2022 ${plc.displayName}';
    }
    return name;
  }

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

  String get statusLabel => _activeCommand.statusLabel;

  AppScreen get currentScreen => switch (_transportConnState.status) {
    BleConnectionStatus.authenticated =>
      _pendingEnrollmentOffer
          ? AppScreen.authentication
          : _getControlScreenForPlcType(),

    BleConnectionStatus.awaitingAuthentication ||
    BleConnectionStatus.authenticating => AppScreen.authentication,
    BleConnectionStatus.error
        when _transportConnState.connectedDevice != null =>
      AppScreen.authentication,
    _ => AppScreen.connection,
  };

  // currentScreen (and this helper) is a getter re-evaluated on every read —
  // including every notifyListeners() tick from the PLC status stream, not
  // just on an actual navigation change. _lastLoggedPlcType makes the log a
  // one-shot per resolved PLC type instead of misleadingly repeating
  // "navigating" on every unrelated rebuild.
  PlcType? _lastLoggedPlcType;

  AppScreen _getControlScreenForPlcType() {
    final plcType = connectedPlcType;
    final isNewlyResolved = plcType != _lastLoggedPlcType;
    _lastLoggedPlcType = plcType;

    // If PLC type is unknown, default to generic control
    if (plcType == PlcType.unknown) {
      if (isNewlyResolved) {
        _logger.w(
          '⚠️ Unknown PLC type detected, defaulting to generic control screen',
        );
      }
      return AppScreen.control;
    }

    // Navigate to PLC38-specific screen for PLC38
    if (plcType == PlcType.plc38) {
      if (isNewlyResolved) {
        _logger.i('✅ PLC38 detected - navigating to PLC38 control screen');
      }
      return AppScreen.plc38Control;
    }

    // PLC14 and PLC21 use generic control screen
    if (isNewlyResolved) {
      _logger.i(
        '✅ ${plcType.displayName} detected - navigating to generic control screen',
      );
    }
    return AppScreen.control;
  }

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

  // bool verifyLocalPassword(String password) {
  //   return password == 'Admin123';
  // }

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
      final results = await Future.wait<dynamic>([
        DeviceIdentityService.getOrCreate(),
        _preferences.getEmail(),
        _preferences.getPassword(),
      ]);
      _deviceId = results[0] as String;
      _savedEmail = (results[1] as String?) ?? '';
      _savedPassword = (results[2] as String?) ?? '';
      _rememberCredentials =
          _savedEmail.isNotEmpty && _savedPassword.isNotEmpty;

      await _prepareRunTime();
      await checkBiometricStatus();
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
    WidgetsBinding.instance.addObserver(this);

    _connStateSubscription = _bleService.connectionStream.listen((snapshot) {
      final previousStatus = _lastConnectionStatus;
      _lastConnectionStatus = snapshot.status;
      _transportConnState = snapshot;
      if (snapshot.status == BleConnectionStatus.disconnected) {
        _activeCommand = PlcOutputCommand.idle();
        _estopLatched = false;
        _sessionEmail = null;
        _startupEmergencyArmedForConnection = false;
        _pendingEnrollmentOffer = false;
        _deviceTrustRejected = false;
        _p38VertState = ControlState.idle;
        _p38TravState = ControlState.idle;
        _p38TripState = ControlState.idle;
        _lastLoggedPlcType = null;
      } else if (snapshot.status == BleConnectionStatus.authenticated &&
          previousStatus != BleConnectionStatus.authenticated) {
        unawaited(ensureControlEntryEmergencyLock());
        if (_biometricAvailable && !_biometricEnrolled) {
          _pendingEnrollmentOffer = true;
        }
      }
      notifyListeners();
    });

    _scanSubscription = _bleService.scanStream.listen((devices) {
      if (isConnectionActive || isConnected) return;
      _devices = devices;
      notifyListeners();
    });
    _statusSubscription = _bleService.statusStream.listen((command) {
      // This is the PLC's own hardware echo, arriving asynchronously over
      // BLE — it can lag behind a command the operator has already released
      // locally. It updates `_activeCommand`/`hoistState` for status/output
      // indicators (LEDs, status chip) ONLY. Button VISUAL active state is
      // sourced from each control screen's local touch state
      // (_activeStateForButton / _localActive), never from this stream, so
      // a late/stale echo here cannot flicker a button back to active.
      ButtonStateLog.log(
        command.estop ||
                command.up ||
                command.down ||
                command.left ||
                command.right ||
                command.forward ||
                command.reverse
            ? 'PLC_STATUS_ACTIVE (hardware echo, status/LED only)'
            : 'PLC_STATUS_IDLE (hardware echo, status/LED only)',
      );
      _activeCommand = command;
      if (command.estop) _estopLatched = true;
      notifyListeners();
    });
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _bluetoothReady = state == BluetoothAdapterState.on;
      notifyListeners();
    });

    _analogSubscription = _bleService.analogStream.listen((values) {
      _analogValues = values;
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
          'Bluetooth must be enabled before scanning for PLC devices. Please enable Bluetooth and try again.';
    }
    notifyListeners();
  }

  Future<void> ensureControlEntryEmergencyLock() async {
    if (!isConnected || _startupEmergencyArmedForConnection) return;
    _startupEmergencyArmedForConnection = true;
    if (_activeCommand.estop || _estopLatched) return;
    await triggerEStop();
  }

  Future<void> pauseScan() async {
    await _bleService.pauseScan();
  }

  Future<void> resumeScan() async {
    if (!bluetoothReady || !permissionsGranted) return;
    await _bleService.resumeScan();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _bleService.pauseScan();
    } else if (state == AppLifecycleState.resumed) {
      if (currentScreen == AppScreen.connection) {
        resumeScan();
      }
    }
  }

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

  Future<void> cancelConnecting() async {
    if (_cancellingConnection) return;
    _errorMessage = null;

    _cancellingDevice = _transportConnState.connectedDevice;
    _cancellingConnection = true;
    notifyListeners();
    await _bleService.cancelConnecting();
    _cancellingConnection = false;
    _cancellingDevice = null;
    notifyListeners();
  }

  void setRememberCredentials(bool value) {
    _rememberCredentials = value;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _errorMessage = null;

    if (isConnected && !_estopLatched) {
      try {
        await _sendCommand(PlcOutputCommand.idle());
      } catch (_) {}
    }
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
    // Defense-in-depth: mutual exclusion is enforced upstream (UI-level
    // isDisabled gating, plus button-centric config validation), so an
    // invalid command should be unreachable here. Refusing to transmit one
    // is strictly safer than the alternative and matches existing intent —
    // this is additive, not a behavior change to any valid, reachable
    // command.
    assert(command.isValid, 'Refusing to compose an invalid PlcOutputCommand');
    if (!command.isValid) return;

    _activeCommand = command;
    notifyListeners();
    final bytes = command.wireBytesFor(connectedPlcType).toList();
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
    // Reset PLC38 axis states so resumed motion starts clean.
    _p38VertState = ControlState.idle;
    _p38TravState = ControlState.idle;
    _p38TripState = ControlState.idle;
    // Clear button-centric state and field ownership so buttons are not stuck
    // in a blocked state after estop is cleared (since setButtonCommand is
    // guarded by _estopLatched, the normal idle-on-release path never runs).
    _p38ButtonStates.clear();
    _fieldOwners.clear();
    final cmd = PlcOutputCommand.emergencyStop();
    _activeCommand = cmd;
    notifyListeners();
    final bytes = cmd.wireBytesFor(connectedPlcType).toList();
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

  Future<void> triggerSafeDisconnect() async {
    if (!isConnected) return;

    _estopLatched = true;
    _p38VertState = ControlState.idle;
    _p38TravState = ControlState.idle;
    _p38TripState = ControlState.idle;
    _activeCommand = PlcOutputCommand.emergencyStop();

    _pendingCommandBytes = null;
    notifyListeners();

    await _bleService.disconnect();
  }

  /// Stops all crane motion by sending an idle command and resetting PLC38 axis
  /// state. No-op when estop is latched (PLC outputs are already off) or when
  /// not connected.
  Future<void> stopAllMotion() async {
    if (_estopLatched || !isConnected) return;
    _p38VertState = ControlState.idle;
    _p38TravState = ControlState.idle;
    _p38TripState = ControlState.idle;
    _p38ButtonStates.clear();
    _fieldOwners.clear();
    await _sendCommand(PlcOutputCommand.idle());
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
    final PlcOutputCommand cmd;
    if (connectedPlcType == PlcType.plc38) {
      _p38VertIsUp = isUp;
      _p38VertState = state;
      cmd = _composePlc38Command();
    } else {
      cmd = switch (state) {
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
    }
    await _sendCommand(cmd);
  }

  /// Horizontal traverse command — PLC38 only.
  Future<void> setTraverseCommand({
    required bool isLeft,
    required ControlState state,
  }) async {
    if (_estopLatched || !isConnected) return;
    _p38TravIsLeft = isLeft;
    _p38TravState = state;
    await _sendCommand(_composePlc38Command());
  }

  /// Longitudinal travel command — PLC38 only.
  Future<void> setTravelCommand({
    required bool isForward,
    required ControlState state,
  }) async {
    if (_estopLatched || !isConnected) return;
    _p38TripIsForward = isForward;
    _p38TripState = state;
    await _sendCommand(_composePlc38Command());
  }

  /// Builds a full PLC38 command from the three independent axis states.
  PlcOutputCommand _composePlc38Command() {
    return PlcOutputCommand.compose(
      estop: false,
      up: _p38VertIsUp && _p38VertState != ControlState.idle,
      down: !_p38VertIsUp && _p38VertState != ControlState.idle,
      fastUd: _p38VertState == ControlState.fast,
      left: _p38TravIsLeft && _p38TravState != ControlState.idle,
      right: !_p38TravIsLeft && _p38TravState != ControlState.idle,
      fastLr: _p38TravState == ControlState.fast,
      forward: _p38TripIsForward && _p38TripState != ControlState.idle,
      reverse: !_p38TripIsForward && _p38TripState != ControlState.idle,
      fastFb: _p38TripState == ControlState.fast,
    );
  }

  /// Button-centric analogue of setHoistCommand/setTraverseCommand/
  /// setTravelCommand — the generalized composition entry point for the
  /// button-centric screens. [buttonId] is a ButtonConfig.id (== a
  /// ControlRole.name value; the closed set is enforced by callers, which
  /// only ever pass ids sourced from ControlLayoutConfig.buttons, itself
  /// derived from the closed ControlRole enum).
  ///
  /// PLC14 (single hoist axis, no independent per-axis state needed today)
  /// delegates to the existing setHoistCommand for hoistUp/hoistDown ids,
  /// keeping PLC14's single source of truth exactly where it is today.
  Future<void> setButtonCommand({
    required String buttonId,
    required ControlState state,
    PlcMapping? plcMapping,
    bool plcMappingEnabled = true,
  }) async {
    if (_estopLatched || !isConnected) return;
    final explicitMapping = plcMappingEnabled ? plcMapping : null;

    if (connectedPlcType != PlcType.plc38) {
      if (explicitMapping == PlcMapping.up ||
          buttonId == ControlRole.hoistUp.name) {
        await setHoistCommand(isUp: true, state: state);
      } else if (explicitMapping == PlcMapping.down ||
          buttonId == ControlRole.hoistDown.name) {
        await setHoistCommand(isUp: false, state: state);
      } else {
        final joystickField = joystickVirtualFieldFor(buttonId);
        if (joystickField == PlcMapping.up) {
          await setHoistCommand(isUp: true, state: state);
        } else if (joystickField == PlcMapping.down) {
          await setHoistCommand(isUp: false, state: state);
        }
      }
      return;
    }

    if (state == ControlState.idle) {
      // Release all fields this button currently owns, then mark it idle.
      _fieldOwners.removeWhere((_, owner) => owner == buttonId);
      _p38ButtonStates[buttonId] = state;
    } else {
      final previousState = _p38ButtonStates[buttonId] ?? ControlState.idle;
      final previousFields = _fieldsFor(
        buttonId,
        previousState,
        explicitMapping: explicitMapping,
      );
      final newFields = _fieldsFor(
        buttonId,
        state,
        explicitMapping: explicitMapping,
      );

      // Only check fields being NEWLY claimed (not already owned by this button).
      final addedFields = newFields.difference(previousFields);
      final blocked = addedFields.any(
        (f) => _fieldOwners.containsKey(f) && _fieldOwners[f] != buttonId,
      );

      if (!blocked) {
        // Release fields no longer needed by the new state.
        for (final f in previousFields.difference(newFields)) {
          _fieldOwners.remove(f);
        }
        // Claim the newly added fields.
        for (final f in addedFields) {
          _fieldOwners[f] = buttonId;
        }
        _p38ButtonStates[buttonId] = state;
      }
      // Blocked commands are silently discarded; the slider's physical clamp
      // (isFieldBlockedForButton) prevents the gesture from reaching here in
      // normal operation.
    }
    await _sendCommand(_composeFromButtonStates());
  }

  // ── Shared-field ownership helpers ────────────────────────────────────────

  /// Returns the set of PLC fields that [buttonId] would assert when its
  /// state is [state]. Used to check ownership before accepting a command and
  /// to release ownership when a button goes idle.
  Set<PlcMapping> _fieldsFor(
    String buttonId,
    ControlState state, {
    PlcMapping? explicitMapping,
  }) {
    if (state == ControlState.idle) return const {};

    if (explicitMapping != null) {
      final fields = <PlcMapping>{explicitMapping};
      if (state == ControlState.fast) {
        final fastField = explicitMapping.correspondingRole?.axis?.fastMapping;
        if (fastField != null) fields.add(fastField);
      }
      return fields;
    }

    // Virtual fast-modifier keys (traverse-only for now; extend via
    // kVirtualFastKeyFields for future axes).
    final virtualField = kVirtualFastKeyFields[buttonId];
    if (virtualField != null) return {virtualField};

    final joystickField = joystickVirtualFieldFor(buttonId);
    if (joystickField != null) {
      final fields = <PlcMapping>{joystickField};
      if (state == ControlState.fast) {
        final fastField = joystickField.correspondingRole?.axis?.fastMapping;
        if (fastField != null) fields.add(fastField);
      }
      return fields;
    }

    // Standard ControlRole buttons matched by role name.
    ControlRole? role;
    for (final r in ControlRole.values) {
      if (r.name == buttonId) {
        role = r;
        break;
      }
    }
    final mapping = role?.plcMapping;
    if (mapping == null) return const {};

    final fields = <PlcMapping>{mapping};
    // Fast state also claims the axis speed-modifier field.
    if (state == ControlState.fast) {
      final fastField = role!.axis?.fastMapping;
      if (fastField != null) fields.add(fastField);
    }
    return fields;
  }

  /// Returns true if any PLC field that [buttonId] would activate is
  /// currently owned by a DIFFERENT button. The UI layer calls this to
  /// apply a per-zone drag clamp on the slider (physical "stuck" sensation)
  /// before the drag enters the blocked zone.
  bool isFieldBlockedForButton(String buttonId) {
    final fields = _fieldsFor(
      buttonId,
      ControlState.slow,
    ); // representative non-idle state
    return fields.any(
      (f) => _fieldOwners.containsKey(f) && _fieldOwners[f] != buttonId,
    );
  }

  /// Generalizes _composePlc38Command(): derives each PlcOutputCommand field
  /// from whichever button state maps to it via ControlRole.plcMapping,
  /// instead of the three hardcoded IsX/State field pairs. Produces
  /// byte-identical output to _composePlc38Command() for every reachable
  /// state because the derivation rule is unchanged: a field is true iff its
  /// role's ControlState != idle; a fast flag is true iff its role's
  /// ControlState == fast.
  PlcOutputCommand _composeFromButtonStates() {
    bool fieldActive(PlcMapping field) {
      for (final entry in _p38ButtonStates.entries) {
        if (_fieldsFor(entry.key, entry.value).contains(field)) return true;
      }
      return false;
    }

    return PlcOutputCommand.compose(
      estop: false,
      up: fieldActive(PlcMapping.up),
      down: fieldActive(PlcMapping.down),
      fastUd: fieldActive(PlcMapping.fastUd),
      left: fieldActive(PlcMapping.left),
      right: fieldActive(PlcMapping.right),
      fastLr: fieldActive(PlcMapping.fastLr),
      forward: fieldActive(PlcMapping.forward),
      reverse: fieldActive(PlcMapping.reverse),
      fastFb: fieldActive(PlcMapping.fastFb),
    );
  }

  Future<bool> authenticate({
    required String email,
    required String password,
  }) async {
    _errorMessage = null;
    _deviceTrustRejected = false;

    if (_deviceId.isEmpty) {
      _deviceId = await DeviceIdentityService.getOrCreate();
    }

    try {
      final outcome = await _bleService.authenticate(
        email: email.trim(),
        password: password,
        deviceId: _deviceId,
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

      if (outcome == BleAuthOutcome.untrusted) {
        _deviceTrustRejected = true;
        _errorMessage =
            'DEVICE NOT AUTHORIZED\nThis device is not registered with PLC 14. '
            'Provide your Device ID to an administrator for registration.';
        notifyListeners();
        return false;
      }

      _errorMessage = outcome == BleAuthOutcome.timedOut
          ? 'PLC authentication timed out.'
          : 'Credentials were rejected by the PLC.';
      notifyListeners();
      return false;
    } catch (error) {
      _errorMessage = 'Authentication failed. $error';
      notifyListeners();
      return false;
    }
  }

  // ── Biometric authentication ──────────────────────────────────────────────

  Future<void> checkBiometricStatus() async {
    _biometricAvailable = await BiometricService.isAvailableAndEnrolled();
    _biometricEnrolled =
        _biometricAvailable && await SecureCredentialStore.hasCredentials();
    notifyListeners();
  }

  Future<bool> enrollBiometrics({
    required String email,
    required String password,
  }) async {
    if (!_biometricAvailable) return false;
    try {
      await SecureCredentialStore.storeCredentials(
        email: email,
        password: password,
      );
      _biometricEnrolled = true;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<BiometricAuthResult> authenticateWithBiometrics() async {
    if (!_biometricAvailable || !_biometricEnrolled) {
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notAvailable,
        message: 'Biometric authentication is not configured on this device.',
      );
    }

    //  Local biometric verification (device biometric hardware gate).
    final biometricResult = await BiometricService.authenticate();
    if (!biometricResult.isSuccess) {
      return biometricResult;
    }

    // Retrieve credentials from hardware-backed secure storage.

    final credentials = await SecureCredentialStore.retrieveCredentials();
    if (credentials == null) {
      _biometricEnrolled = false;
      notifyListeners();
      return const BiometricAuthResult(
        status: BiometricAuthStatus.credentialsMissing,
        message:
            'Stored operator credentials not found. Log in manually to re-enable biometric access.',
      );
    }

    // PLC validates the operator, enforces single-operator policy,
    // and returns AUTH_OK / AUTH_FAIL as normal.
    _errorMessage = null;
    final plcSuccess = await authenticate(
      email: credentials.email,
      password: credentials.password,
    );

    if (!plcSuccess) {
      await SecureCredentialStore.clearCredentials();
      _biometricEnrolled = false;
      notifyListeners();
      return BiometricAuthResult(
        status: BiometricAuthStatus.failure,
        message:
            _errorMessage ??
            'PLC rejected stored operator credentials. Please log in manually.',
      );
    }

    return const BiometricAuthResult(status: BiometricAuthStatus.success);
  }

  Future<void> clearBiometricEnrollment() async {
    await SecureCredentialStore.clearCredentials();
    _biometricEnrolled = false;
    notifyListeners();
  }

  void completePendingEnrollmentOffer() {
    if (!_pendingEnrollmentOffer) return;
    _pendingEnrollmentOffer = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _analogSubscription?.cancel();
    _statusSubscription?.cancel();
    _adapterSubscription?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
