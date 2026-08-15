import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:rev_crane_control_ops/controllers/feedback_manager.dart'
    show FeedbackSource;
import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
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

class CraneController extends ChangeNotifier
    with WidgetsBindingObserver
    implements FeedbackSource {
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
  PlcOutputCommand _commandedCommand = PlcOutputCommand.idle();
  PlcOutputCommand _reportedStatusCommand = PlcOutputCommand.idle();

  DateTime? _lastPlcStatusAt;

  // ── BLE write serializer ──────────────────────────────────────────────────

  bool _commandInFlight = false;
  List<int>? _pendingCommandBytes;

  DateTime? _analogLastSentAt;
  Timer? _analogTrailingTimer;
  List<int>? _pendingAnalogBytes;

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

  final Map<String, Set<PlcOutputVariant>> _buttonFields = {};

  final Map<PlcOutputVariant, String> _fieldOwners = {};

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

  bool get rememberCredentials => _rememberCredentials;
  bool get isBiometricAvailable => _biometricAvailable;
  bool get isBiometricEnrolled => _biometricEnrolled;

  bool get hasPendingEnrollmentOffer => _pendingEnrollmentOffer;
  PlcOutputCommand get activeCommand => _activeCommand;

  PlcOutputCommand get commandedCommand => _commandedCommand;

  PlcOutputCommand get reportedStatusCommand => _reportedStatusCommand;

  bool get hasActivePlcStatus => !_reportedStatusCommand.isIdle;
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

  @override
  int analogValue(String channelKey) => _analogValues[channelKey] ?? 0;

  @override
  bool get isPlcConnected => isConnected;

  @override
  DateTime? get lastPlcStatusAt => _lastPlcStatusAt;

  @override
  bool isCommandedFieldActive(PlcOutputVariant variant) =>
      _commandedCommand.fieldValue(variant);

  bool isConfirmedFieldActive(PlcOutputVariant variant) =>
      _reportedStatusCommand.fieldValue(variant);

  @override
  bool isReportedFieldActive(PlcOutputVariant mapping) =>
      _reportedStatusCommand.fieldValue(mapping);

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

  String get statusLabel => _activeCommand.statusLabel;

  AppScreen get currentScreen => switch (_transportConnState.status) {
    BleConnectionStatus.authenticated =>
      _pendingEnrollmentOffer
          ? AppScreen.authentication
          : _getControlScreenForPlcType(),

    BleConnectionStatus.awaitingAuthentication ||
    BleConnectionStatus.connected ||
    BleConnectionStatus.authenticating => AppScreen.authentication,
    BleConnectionStatus.error
        when _transportConnState.connectedDevice != null =>
      AppScreen.authentication,
    _ => AppScreen.connection,
  };

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
        _commandedCommand = PlcOutputCommand.idle();
        _reportedStatusCommand = PlcOutputCommand.idle();
        _lastPlcStatusAt = null;
        _estopLatched = false;
        _sessionEmail = null;
        _startupEmergencyArmedForConnection = false;
        _pendingEnrollmentOffer = false;
        _deviceTrustRejected = false;
        _buttonFields.clear();
        _fieldOwners.clear();
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
    _statusSubscription = _bleService.statusStream.listen(_handlePlcStatus);
    _adapterSubscription = FlutterBluePlus.adapterState.listen((state) {
      _bluetoothReady = state == BluetoothAdapterState.on;
      notifyListeners();
    });

    _analogSubscription = _bleService.analogStream.listen((values) {
      _analogValues = values;
      notifyListeners();
    });
  }

  @visibleForTesting
  void handlePlcStatusForTesting(PlcOutputCommand command) {
    _handlePlcStatus(command);
  }

  void _handlePlcStatus(PlcOutputCommand command) {
    ButtonStateLog.log(
      command.isIdle
          ? 'PLC_STATUS_IDLE (hardware echo, status/LED only)'
          : 'PLC_STATUS_ACTIVE (hardware echo, status/LED only)',
    );

    _reportedStatusCommand = command;
    _activeCommand = command;
    _lastPlcStatusAt = DateTime.now();
    notifyListeners();
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
    assert(command.isValid, 'Refusing to compose an invalid PlcOutputCommand');
    if (!command.isValid) return;

    _activeCommand = command;
    _commandedCommand = command;
    notifyListeners();
    final bytes = command.wireBytesFor(connectedPlcType).toList();
    if (_commandInFlight) {
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

    _buttonFields.clear();
    _fieldOwners.clear();
    final cmd = PlcOutputCommand.emergencyStop();
    _activeCommand = cmd;
    _commandedCommand = cmd;
    notifyListeners();
    final bytes = cmd.wireBytesFor(connectedPlcType).toList();

    _pendingCommandBytes = bytes;
    if (!_commandInFlight) {
      final pending = _pendingCommandBytes!;
      _pendingCommandBytes = null;
      await _writeBytes(pending);
    }
  }

  Future<void> triggerSafeDisconnect() async {
    if (!isConnected) return;

    _estopLatched = true;
    _buttonFields.clear();
    _fieldOwners.clear();
    _activeCommand = PlcOutputCommand.emergencyStop();
    _commandedCommand = _activeCommand;

    _pendingCommandBytes = null;
    notifyListeners();

    await _bleService.disconnect();
  }

  Future<void> stopAllMotion() async {
    if (_estopLatched || !isConnected) return;
    _buttonFields.clear();
    _fieldOwners.clear();
    await _sendCommand(PlcOutputCommand.idle());
  }

  Future<void> resetEStop() async {
    _estopLatched = false;
    await _sendCommand(PlcOutputCommand.idle());
  }

  Future<void> setButtonState({
    required String buttonId,
    required String stateId,
    required Set<PlcOutputVariant> activeVariants,
  }) async {
    if (_estopLatched || !isConnected) return;

    if (activeVariants.isEmpty) {
      // Release all fields this button currently owns, then mark it idle.
      _fieldOwners.removeWhere((_, owner) => owner == buttonId);
      _buttonFields.remove(buttonId);
    } else {
      final previousFields =
          _buttonFields[buttonId] ?? const <PlcOutputVariant>{};

      // Only check fields being NEWLY claimed (not already owned by this button).
      final addedFields = activeVariants.difference(previousFields);
      final blocked = addedFields.any(
        (f) => _fieldOwners.containsKey(f) && _fieldOwners[f] != buttonId,
      );

      if (!blocked) {
        // Release fields no longer needed by the new state.
        for (final f in previousFields.difference(activeVariants)) {
          _fieldOwners.remove(f);
        }
        // Claim the newly added fields.
        for (final f in addedFields) {
          _fieldOwners[f] = buttonId;
        }
        _buttonFields[buttonId] = activeVariants;
      }
    }
    await _sendCommand(_composeFromButtonFields());
  }

  Future<void> setAnalogButtonValue({
    required String buttonId,
    required double value,
    required AnalogWireConfig config,
  }) async {
    if (_estopLatched || !isConnected || !config.outputEnabled) {
      _logger.w(
        'Analog output BLOCKED for $buttonId '
        '(estopLatched=$_estopLatched, isConnected=$isConnected, '
        'outputEnabled=${config.outputEnabled}) — flip "Send to PLC" on in '
        'the POTENTIOMETER/OUTPUT MAPPING editor and commit the layout if '
        'outputEnabled is false.',
      );
      return;
    }
    final payload = config.wirePayload(value);
    _logger.d('Analog output queued for $buttonId: $payload');
    _queueAnalogWrite(utf8.encode(payload));
  }

  void _queueAnalogWrite(List<int> bytes) {
    final now = DateTime.now();
    final lastSent = _analogLastSentAt;
    final elapsed = lastSent == null
        ? SafetyConstants.analogOutputThrottle
        : now.difference(lastSent);

    if (elapsed >= SafetyConstants.analogOutputThrottle) {
      _analogTrailingTimer?.cancel();
      _analogTrailingTimer = null;
      _pendingAnalogBytes = null;
      unawaited(_sendAnalogBytes(bytes));
      return;
    }

    _pendingAnalogBytes = bytes;
    _analogTrailingTimer ??= Timer(
      SafetyConstants.analogOutputThrottle - elapsed,
      () {
        _analogTrailingTimer = null;
        final pending = _pendingAnalogBytes;
        _pendingAnalogBytes = null;
        if (pending != null) unawaited(_sendAnalogBytes(pending));
      },
    );
  }

  Future<void> _sendAnalogBytes(List<int> bytes) async {
    if (_estopLatched || !isConnected) {
      _logger.w(
        'Analog output DROPPED at send time '
        '(estopLatched=$_estopLatched, isConnected=$isConnected)',
      );
      return;
    }
    _analogLastSentAt = DateTime.now();
    try {
      await _bleService.writeAnalogOutput(bytes);
    } catch (e) {
      _logger.w('Analog output write failed: $e');
    }
  }

  bool isFieldBlockedForButton(
    String buttonId,
    Set<PlcOutputVariant> candidateFields,
  ) {
    return candidateFields.any(
      (f) => _fieldOwners.containsKey(f) && _fieldOwners[f] != buttonId,
    );
  }

  PlcOutputCommand _composeFromButtonFields() {
    final fields = <PlcOutputVariant>{};
    for (final buttonFields in _buttonFields.values) {
      fields.addAll(buttonFields);
    }
    return PlcOutputCommand.compose(fields);
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
            'DEVICE NOT AUTHORIZED\nThis device is not registered with the PLC. '
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
    _analogTrailingTimer?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
