import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:logger/logger.dart';
import 'package:rev_crane_control_ops/controllers/feedback_manager.dart'
    show FeedbackSource;
import 'package:rev_crane_control_ops/models/analog_wire_config.dart';
import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/auth_log_entry.dart';
import 'package:rev_crane_control_ops/models/operator_profile.dart';
import 'package:rev_crane_control_ops/models/permission.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/repositories/operator_repository.dart';
import 'package:rev_crane_control_ops/services/auth_audit_log_service.dart';
import 'package:rev_crane_control_ops/services/authorization_service.dart';
import 'package:rev_crane_control_ops/services/biometric_service.dart';
import 'package:rev_crane_control_ops/services/ble_crypto.dart';
import 'package:rev_crane_control_ops/services/device_identity_service.dart';
import 'package:rev_crane_control_ops/services/device_setup_registry.dart';
import 'package:rev_crane_control_ops/models/ble_connection_state.dart';
import 'package:rev_crane_control_ops/models/ble_scan_device.dart';
import 'package:rev_crane_control_ops/models/hoist_notification.dart';
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
  CraneController({AuditLogger? auditLog})
    : _auditLog = auditLog ?? AuthAuditLogService();

  final BleService _bleService = BleService();
  final Logger _logger = Logger(printer: PrettyPrinter(methodCount: 0));
  final PermissionService _permissionService = PermissionService();
  final AppPreferences _preferences = AppPreferences();

  // Injected rather than reached for statically — this controller never
  // touches the filesystem/crypto/secure-storage directly, only this one
  // object. Every call site below is fire-and-forget (never awaited): a
  // slow or failing audit write must never hold up PLC authentication or
  // the BLE heartbeat.
  final AuditLogger _auditLog;

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

  // Channels queued for the next throttled DATA: flush, keyed by channel so
  // two controls changing within the same throttle window are coalesced
  // into one "DATA:A1-x,A2-y" command instead of the second overwriting the
  // first (each channel is independently addressed on the wire, unlike the
  // old single shared analog-out value).
  final Map<AnalogOutputChannel, String> _pendingAnalogDataTokens = {};

  // Last RANGE:A{n}-{min},{max} token sent per channel this session, so a
  // RANGE command only goes out once (or again after the operator edits the
  // range) rather than on every value change.
  final Map<AnalogOutputChannel, String> _sentAnalogRangeTokens = {};

  bool _initializing = true;
  Future<void>? _initializeFuture;
  bool _streamsAttached = false;
  PermissionState _permissionState = const PermissionState.initial();
  bool _bluetoothReady = false;
  bool _permissionBannerDismissed = false;
  bool _rememberOperatorEmail = false;
  bool _estopLatched = false;
  bool _startupEmergencyArmedForConnection = false;
  bool _biometricAvailable = false;
  bool _biometricEnrolled = false;

  bool _pendingEnrollmentOffer = false;

  // Shows AppScreen.faceVerification instead of AppScreen.authentication
  // when true. Seeded per-connection from the PLC's own setup record (see
  // _loadDeviceSetupState) rather than always defaulting to true: a
  // never-before-configured MAC seeds this false (straight to credentials),
  // an already-configured MAC with face enabled seeds it true. Also
  // toggled on demand by requestIdentityVerificationFallback/
  // skipFaceVerification for the fallback flows.
  bool _pendingFaceVerification = false;
  OperatorProfile? _faceVerifiedOperator;

  // ── Per-device (PLC MAC ID) setup state ───────────────────────────────────
  // A device's setup record, which identity methods it enabled, and whether
  // this session has finished loading it are all keyed to whichever MAC is
  // currently connected — see _loadDeviceSetupState and currentScreen. Reset
  // on every disconnect so a different PLC never inherits this state.
  String? _setupLoadedForMacId;
  bool _deviceSetupLoaded = false;
  DeviceSetupRecord? _deviceSetupRecord;
  bool _pendingSetupMode = false;
  ({String email, String password})? _pendingSetupCredentials;

  // ── Role-based control-access gate ────────────────────────────────────────
  // Runs once, lazily, at the single point every success path (Setup
  // Complete, Face Verification, and the credential/biometric fallback)
  // converges on: about to enter the PLC-type control screen. See
  // currentScreen/_resolveControlAccessScreen/_checkControlAccess.
  bool _controlAccessChecked = false;
  bool _accessDenied = false;
  OperatorRepository? _operatorRepository;

  // One-shot signal consumed by the connectionStream listener: set right
  // before the silent, face-triggered reauth call so that specific
  // authenticated transition never pops the biometric-enrollment offer in
  // front of the control screen — see completeFaceVerification.
  bool _suppressEnrollmentOfferOnce = false;

  String? _sessionEmail;
  String? _errorMessage;
  String _savedEmail = '';
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

  bool get rememberOperatorEmail => _rememberOperatorEmail;
  bool get isBiometricAvailable => _biometricAvailable;
  bool get isBiometricEnrolled => _biometricEnrolled;

  bool get hasPendingEnrollmentOffer => _pendingEnrollmentOffer;
  bool get needsFaceVerification => _pendingFaceVerification;
  OperatorProfile? get verifiedOperator => _faceVerifiedOperator;

  /// Whether the currently-connected PLC (by MAC ID) has already completed
  /// its one-time authentication setup. `false` for a never-before-seen
  /// device, in which case it goes straight to credentials rather than Face
  /// Verification (see [currentScreen]).
  bool get isDeviceConfigured => _deviceSetupRecord != null;

  /// True when Face Verification is being offered as an opt-in identity
  /// check ahead of first-time credential entry (requested via
  /// [requestIdentityVerificationFallback]) rather than as the mandatory
  /// primary gate on an already-configured device. Lets
  /// [FaceVerificationScreen] show a "back to credentials" affordance only
  /// when it's genuinely optional.
  bool get isFaceVerificationOptional => !isDeviceConfigured;

  /// True once a never-before-configured device has just accepted valid
  /// credentials for the first time — routes [currentScreen] to
  /// AppScreen.setupMode instead of straight to the control screen.
  bool get hasPendingSetupMode => _pendingSetupMode;

  /// True once PLC authentication succeeded but the resolved operator's
  /// role doesn't hold [Permission.controlAccess] (or no local operator
  /// profile could be resolved for the login at all). Keeps
  /// [currentScreen] on AppScreen.authentication instead of the control
  /// screen — see [_checkControlAccess].
  bool get isAccessDenied => _accessDenied;
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
  int get h1 => _analogValues[HoistNotification.hoist1Key] ?? 0;
  int get h2 => _analogValues[HoistNotification.hoist2Key] ?? 0;

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
    BleConnectionStatus.authenticated => _pendingSetupMode
        ? AppScreen.setupMode
        : _pendingEnrollmentOffer
            ? AppScreen.authentication
            : _resolveControlAccessScreen(),

    BleConnectionStatus.awaitingAuthentication ||
    BleConnectionStatus.connected ||
    BleConnectionStatus.authenticating =>
      _resolvePreAuthScreen(),
    BleConnectionStatus.error
        when _transportConnState.connectedDevice != null =>
      _resolvePreAuthScreen(),
    _ => AppScreen.connection,
  };

  /// Screen shown before PLC credential auth completes: a brief connection
  /// spinner while this MAC's setup record is still loading, then either
  /// Face Verification or the credential screen depending on
  /// [_pendingFaceVerification] (seeded per-device by
  /// [_loadDeviceSetupState], toggled on demand by
  /// [requestIdentityVerificationFallback]/[skipFaceVerification]).
  AppScreen _resolvePreAuthScreen() {
    if (!_deviceSetupLoaded) return AppScreen.connection;
    return _pendingFaceVerification
        ? AppScreen.faceVerification
        : AppScreen.authentication;
  }

  /// Screen shown once PLC authentication has fully succeeded (Setup Mode
  /// and the biometric-enrollment offer, if any, are both already
  /// resolved) — the single point every success path (first-time Setup
  /// Complete, Face Verification, and the credential/biometric fallback)
  /// converges on before the control screen. Kicks off [_checkControlAccess]
  /// at most once per authenticated session and holds on
  /// AppScreen.authentication (denial banner, or briefly, the still-checking
  /// authenticated card) until it resolves — never AppScreen.connection,
  /// which would pop the already-pushed auth/control sub-shell route.
  AppScreen _resolveControlAccessScreen() {
    if (_accessDenied) return AppScreen.authentication;
    if (!_controlAccessChecked) {
      unawaited(_checkControlAccess());
      return AppScreen.authentication;
    }
    return _getControlScreenForPlcType();
  }

  /// Resolves the authenticated operator's role — directly from
  /// [_faceVerifiedOperator] when Face Verification identified them this
  /// session, otherwise by looking up the just-used PLC login email in the
  /// local operator roster — and checks [Permission.controlAccess] via
  /// [AuthorizationService]. The PLC itself already vouched for these
  /// credentials (that's what got the session to `authenticated` at all),
  /// so a login with **no** local operator match is let through — the
  /// local roster only adds a *stricter* role-based ceiling on top of that
  /// for operators it actually knows about. Only a resolved operator whose
  /// role lacks the permission fails closed: [_accessDenied] is set and the
  /// operator stays on AppScreen.authentication with an error banner, same
  /// as every other failure in this flow.
  Future<void> _checkControlAccess() async {
    if (_controlAccessChecked) return;
    _controlAccessChecked = true;

    final macId = _transportConnState.connectedDevice?.id;
    final email = _sessionEmail;
    final operator =
        _faceVerifiedOperator ??
        (email != null ? await _resolveOperatorByEmail(email) : null);

    // A disconnect/reconnect, or a fresh authenticate() call resetting this
    // check, may have happened while the operator lookup was in flight — a
    // stale result must never flip access state for a different attempt.
    if (_transportConnState.connectedDevice?.id != macId ||
        _transportConnState.status != BleConnectionStatus.authenticated) {
      return;
    }

    final authorized =
        operator == null ||
        AuthorizationService.can(operator.role, Permission.controlAccess);

    if (!authorized) {
      _accessDenied = true;
      _errorMessage =
          'ACCESS DENIED\n${operator.role.displayName}s do not have '
          'control-access permission on this device.';
      final correlationId = await BleCrypto.sessionCorrelationId;
      unawaited(
        _auditLog.record(
          result: AuthEventResult.failed,
          method: AuthEventMethod.password,
          userIdentifier: email,
          operatorId: operator.operatorId,
          operatorNameSnapshot: operator.name,
          role: operator.role.name,
          deviceId: _deviceId,
          plcDeviceId: macId,
          connectionStatus: _transportConnState.status.name,
          sessionCorrelationId: correlationId,
          failureReason: _errorMessage,
          detailCode: 'access_denied_role_permission',
        ),
      );
    }
    notifyListeners();
  }

  Future<OperatorProfile?> _resolveOperatorByEmail(String email) async {
    final repo = _operatorRepository ??= await OperatorRepository.open();
    return repo.getByEmail(email);
  }

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
        _preferences.getOperatorEmail(),
        _preferences.clearLegacyPassword(),
      ]);
      _deviceId = results[0] as String;
      _savedEmail = (results[1] as String?) ?? '';
      _rememberOperatorEmail = _savedEmail.isNotEmpty;

      await _prepareRunTime();
      await checkBiometricStatus(macId: null);
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

      // Kick off this MAC's setup-record lookup as soon as a new device
      // appears (connectedDevice is set by BleService before the
      // `connecting` status even fires) — resolves well before the
      // credential/face-verification screens can be reached, and is keyed
      // to the MAC so a different PLC never inherits this device's state.
      final newDevice = snapshot.connectedDevice;
      if (newDevice != null && newDevice.id != _setupLoadedForMacId) {
        _setupLoadedForMacId = newDevice.id;
        _deviceSetupLoaded = false;
        _deviceSetupRecord = null;
        unawaited(_loadDeviceSetupState(newDevice.id));
      }

      if (snapshot.status == BleConnectionStatus.disconnected) {
        _activeCommand = PlcOutputCommand.idle();
        _commandedCommand = PlcOutputCommand.idle();
        _reportedStatusCommand = PlcOutputCommand.idle();
        _lastPlcStatusAt = null;
        _estopLatched = false;
        _sessionEmail = null;
        _startupEmergencyArmedForConnection = false;
        _pendingEnrollmentOffer = false;
        _pendingFaceVerification = false;
        _faceVerifiedOperator = null;
        _deviceTrustRejected = false;
        _setupLoadedForMacId = null;
        _deviceSetupLoaded = false;
        _deviceSetupRecord = null;
        _pendingSetupMode = false;
        _pendingSetupCredentials = null;
        _controlAccessChecked = false;
        _accessDenied = false;
        _suppressEnrollmentOfferOnce = false;
        _biometricEnrolled = false;
        _buttonFields.clear();
        _fieldOwners.clear();
        _lastLoggedPlcType = null;
        _analogTrailingTimer?.cancel();
        _analogTrailingTimer = null;
        _analogLastSentAt = null;
        _pendingAnalogDataTokens.clear();
        // A reconnect may hit the same channel with a stale rangeMin/
        // rangeMax the firmware no longer remembers (fresh boot, or a
        // different PLC entirely) — force RANGE to be resent on next use.
        _sentAnalogRangeTokens.clear();
      } else if (snapshot.status == BleConnectionStatus.authenticated &&
          previousStatus != BleConnectionStatus.authenticated) {
        unawaited(ensureControlEntryEmergencyLock());
        // Never interrupt a silent, face-triggered reauth with the
        // biometric-enrollment offer — that path is meant to go straight
        // to the control screen with no screen in between (see
        // completeFaceVerification/_attemptSilentReauthAfterFaceVerification).
        if (_biometricAvailable &&
            !_biometricEnrolled &&
            !_suppressEnrollmentOfferOnce) {
          _pendingEnrollmentOffer = true;
        }
        _suppressEnrollmentOfferOnce = false;
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

  /// Looks up [macId]'s setup record and seeds this connection's
  /// pre-auth screen accordingly (Face Verification first for an
  /// already-configured device with it enabled; straight to credentials
  /// otherwise). Also refreshes the per-device biometric-enrolled flag,
  /// since that too is now scoped to this MAC.
  Future<void> _loadDeviceSetupState(String macId) async {
    final record = await DeviceSetupRegistry.get(macId);
    await checkBiometricStatus(macId: macId);

    // A disconnect/reconnect (possibly to a different device) may have
    // happened while this lookup was in flight — a stale result must never
    // overwrite state for whichever device is actually connected now.
    if (_transportConnState.connectedDevice?.id != macId) return;

    _deviceSetupRecord = record;
    _pendingFaceVerification = record != null && record.faceVerificationEnabled;
    _deviceSetupLoaded = true;
    notifyListeners();
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

  Future<void> setRememberOperatorEmail(bool value) async {
    _rememberOperatorEmail = value;
    if (!value) {
      _savedEmail = '';
      await _preferences.clearOperatorEmail();
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _errorMessage = null;

    if (isConnected && !_estopLatched) {
      try {
        await _sendCommand(PlcOutputCommand.idle());
      } catch (_) {}
    }
    // No notifyListeners() here: _bleService.disconnect() emits the
    // disconnected status onto connectionStream, which _connStateSubscription
    // (see _attachStreamsIfNeeded) already turns into a notifyListeners()
    // call. Notifying again here duplicated it, so listeners keyed off
    // isDisconnected (e.g. the "Disconnected from PLC" SnackBar) fired twice.
    await _bleService.disconnect();
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
    final channel = config.outputChannel;
    if (channel == null) {
      _logger.w(
        'Analog output BLOCKED for $buttonId — no analog channel (A1..A6) '
        'assigned in the OUTPUT MAPPING editor.',
      );
      return;
    }

    // The firmware persists each channel's scaling range and applies it to
    // every subsequent DATA value, so RANGE only needs to go out once per
    // channel per session — and again if the operator edits the range.
    final rangeToken = analogRangeToken(config);
    if (rangeToken != null && _sentAnalogRangeTokens[channel] != rangeToken) {
      _sentAnalogRangeTokens[channel] = rangeToken;
      unawaited(_sendAnalogCommand('RANGE:$rangeToken'));
    }

    final dataToken = analogDataToken(config, value);
    if (dataToken == null) return;
    _logger.d('Analog output queued for $buttonId: $dataToken');
    _queueAnalogDataToken(channel, dataToken);
  }

  void _queueAnalogDataToken(AnalogOutputChannel channel, String token) {
    _pendingAnalogDataTokens[channel] = token;

    final now = DateTime.now();
    final lastSent = _analogLastSentAt;
    final elapsed = lastSent == null
        ? SafetyConstants.analogOutputThrottle
        : now.difference(lastSent);

    if (elapsed >= SafetyConstants.analogOutputThrottle) {
      _analogTrailingTimer?.cancel();
      _analogTrailingTimer = null;
      unawaited(_flushAnalogDataTokens());
      return;
    }

    _analogTrailingTimer ??= Timer(
      SafetyConstants.analogOutputThrottle - elapsed,
      () {
        _analogTrailingTimer = null;
        unawaited(_flushAnalogDataTokens());
      },
    );
  }

  Future<void> _flushAnalogDataTokens() async {
    if (_pendingAnalogDataTokens.isEmpty) return;
    final tokens = _pendingAnalogDataTokens.values.toList();
    _pendingAnalogDataTokens.clear();
    await _sendAnalogCommand('DATA:${tokens.join(',')}');
  }

  Future<void> _sendAnalogCommand(String command) async {
    if (_estopLatched || !isConnected) {
      _logger.w(
        'Analog output DROPPED at send time '
        '(estopLatched=$_estopLatched, isConnected=$isConnected)',
      );
      return;
    }
    _analogLastSentAt = DateTime.now();
    try {
      await _bleService.writeAnalogOutput(utf8.encode(command));
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

  /// [method] identifies what actually drove this PLC authentication for
  /// audit purposes — [AuthEventMethod.password] for a manually-typed
  /// login, [AuthEventMethod.biometric] when [authenticateWithBiometrics]
  /// calls through with stored credentials. The wire protocol/PLC exchange
  /// is identical either way; only the log attribution differs.
  Future<bool> authenticate({
    required String email,
    required String password,
    AuthEventMethod method = AuthEventMethod.password,
  }) async {
    _errorMessage = null;
    _deviceTrustRejected = false;
    // Every fresh attempt re-derives control-access from scratch rather
    // than reusing a stale grant/denial from a previous attempt this
    // session (e.g. retrying with a different email after a denial).
    _controlAccessChecked = false;
    _accessDenied = false;
    final macId = _transportConnState.connectedDevice?.id;

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
        if (_rememberOperatorEmail) {
          await _preferences.saveOperatorEmail(email.trim());
          _savedEmail = email.trim();
        } else {
          await _preferences.clearOperatorEmail();
          _savedEmail = '';
        }
        // A never-before-configured device routes through Setup Mode next
        // (see currentScreen) rather than straight to the control screen;
        // stash the just-validated credential in memory only so Setup Mode
        // can cache it for a future silent Face Verification reauth without
        // needing the (long-unmounted) login form's password field.
        if (macId != null && !isDeviceConfigured) {
          _pendingSetupCredentials = (email: email.trim(), password: password);
          _pendingSetupMode = true;
        }
        final correlationId = await BleCrypto.sessionCorrelationId;
        unawaited(
          _auditLog.record(
            result: AuthEventResult.success,
            method: method,
            userIdentifier: email.trim(),
            deviceId: _deviceId,
            plcDeviceName: connectedDeviceName,
            plcDeviceId: macId,
            plcType: connectedPlcType.displayName,
            connectionStatus: _transportConnState.status.name,
            sessionCorrelationId: correlationId,
          ),
        );
        notifyListeners();
        return true;
      }

      if (outcome == BleAuthOutcome.untrusted) {
        _deviceTrustRejected = true;
        _errorMessage =
            'DEVICE NOT AUTHORIZED\nThis device is not registered with the PLC. '
            'Provide your Device ID to an administrator for registration.';
        final correlationId = await BleCrypto.sessionCorrelationId;
        unawaited(
          _auditLog.record(
            result: AuthEventResult.failed,
            method: method,
            userIdentifier: email.trim(),
            deviceId: _deviceId,
            plcDeviceId: macId,
            connectionStatus: _transportConnState.status.name,
            sessionCorrelationId: correlationId,
            failureReason: _errorMessage,
            detailCode: 'device_untrusted',
          ),
        );
        notifyListeners();
        return false;
      }

      _errorMessage = outcome == BleAuthOutcome.timedOut
          ? 'PLC authentication timed out.'
          : 'Credentials were rejected by the PLC.';
      final correlationId = await BleCrypto.sessionCorrelationId;
      unawaited(
        _auditLog.record(
          result: outcome == BleAuthOutcome.timedOut
              ? AuthEventResult.error
              : AuthEventResult.failed,
          method: method,
          userIdentifier: email.trim(),
          deviceId: _deviceId,
          plcDeviceId: macId,
          connectionStatus: _transportConnState.status.name,
          sessionCorrelationId: correlationId,
          failureReason: _errorMessage,
          detailCode: outcome == BleAuthOutcome.timedOut
              ? 'ble_timeout'
              : 'ble_failed',
        ),
      );
      notifyListeners();
      return false;
    } catch (error) {
      _errorMessage = 'Authentication failed. $error';
      final correlationId = await BleCrypto.sessionCorrelationId;
      unawaited(
        _auditLog.record(
          result: AuthEventResult.error,
          method: method,
          userIdentifier: email.trim(),
          deviceId: _deviceId,
          plcDeviceId: macId,
          sessionCorrelationId: correlationId,
          failureReason: _errorMessage,
          detailCode: 'exception',
        ),
      );
      notifyListeners();
      return false;
    }
  }

  // ── Biometric authentication ──────────────────────────────────────────────

  /// [macId] identifies which PLC's cached credential state to check.
  /// `null` (only expected at app startup, before any device is connected)
  /// reports hardware availability only, with `isBiometricEnrolled` false
  /// since there's no device yet to have enrolled one for.
  Future<void> checkBiometricStatus({required String? macId}) async {
    _biometricAvailable = await BiometricService.isAvailableAndEnrolled();
    _biometricEnrolled = _biometricAvailable &&
        macId != null &&
        await SecureCredentialStore.hasCredentials(macId);
    notifyListeners();
  }

  Future<bool> enrollBiometrics({
    required String email,
    required String password,
  }) async {
    final macId = _transportConnState.connectedDevice?.id;
    if (!_biometricAvailable || macId == null) return false;
    try {
      await SecureCredentialStore.storeCredentials(
        macId: macId,
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
    final macId = _transportConnState.connectedDevice?.id;
    if (!_biometricAvailable || !_biometricEnrolled || macId == null) {
      unawaited(
        _auditLog.record(
          result: AuthEventResult.error,
          method: AuthEventMethod.biometric,
          deviceId: _deviceId,
          plcDeviceId: macId,
          connectionStatus: _transportConnState.status.name,
          failureReason:
              'Biometric authentication is not configured on this device.',
          detailCode: 'biometric_preflight_notAvailable',
        ),
      );
      return const BiometricAuthResult(
        status: BiometricAuthStatus.notAvailable,
        message: 'Biometric authentication is not configured on this device.',
      );
    }

    //  Local biometric verification (device biometric hardware gate).
    final biometricResult = await BiometricService.authenticate();
    if (!biometricResult.isSuccess) {
      unawaited(
        _auditLog.record(
          result: biometricResult.isCancelled
              ? AuthEventResult.cancelled
              : AuthEventResult.failed,
          method: AuthEventMethod.biometric,
          deviceId: _deviceId,
          plcDeviceId: macId,
          connectionStatus: _transportConnState.status.name,
          failureReason: biometricResult.message,
          detailCode: biometricResult.isCancelled
              ? 'biometric_cancelled'
              : 'biometric_hardware_failure',
        ),
      );
      return biometricResult;
    }

    // Retrieve credentials from hardware-backed secure storage.

    final credentials = await SecureCredentialStore.retrieveCredentials(macId);
    if (credentials == null) {
      await SecureCredentialStore.clearCredentials(macId);
      _biometricEnrolled = false;
      unawaited(
        _auditLog.record(
          result: AuthEventResult.error,
          method: AuthEventMethod.biometric,
          deviceId: _deviceId,
          plcDeviceId: macId,
          connectionStatus: _transportConnState.status.name,
          failureReason:
              'Stored operator credentials not found. Log in manually to re-enable biometric access.',
          detailCode: 'biometric_credentials_missing',
        ),
      );
      notifyListeners();
      return const BiometricAuthResult(
        status: BiometricAuthStatus.credentialsMissing,
        message:
            'Stored operator credentials not found. Log in manually to re-enable biometric access.',
      );
    }

    // PLC validates the operator, enforces single-operator policy, and
    // returns AUTH_OK / AUTH_FAIL as normal. `authenticate()` logs the
    // outcome itself, tagged as AuthEventMethod.biometric so the audit
    // trail correctly attributes it to the fingerprint unlock rather than
    // a manually-typed password.
    _errorMessage = null;
    final plcSuccess = await authenticate(
      email: credentials.email,
      password: credentials.password,
      method: AuthEventMethod.biometric,
    );

    if (!plcSuccess) {
      await SecureCredentialStore.clearCredentials(macId);
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
    final macId = _transportConnState.connectedDevice?.id;
    if (macId != null) {
      await SecureCredentialStore.clearCredentials(macId);
    }
    _biometricEnrolled = false;
    notifyListeners();
  }

  void completePendingEnrollmentOffer() {
    if (!_pendingEnrollmentOffer) return;
    _pendingEnrollmentOffer = false;
    notifyListeners();
  }

  // ── Face verification (identity gate ahead of PLC credential auth) ───────

  /// Called by the face-verification screen once a live camera frame has
  /// matched an enrolled, enabled operator, and — for an already-configured
  /// device — the entry point into a silent reauth that goes straight to
  /// the control screen with no credential screen shown at all. This only
  /// identifies which operator is present; it never grants PLC/control
  /// access on its own — [authenticate] (via the cached credential below,
  /// or manually on [LoginScreen]) is still what actually does that.
  void completeFaceVerification(OperatorProfile operator) {
    final macId = _transportConnState.connectedDevice?.id;
    _faceVerifiedOperator = operator;
    unawaited(
      _auditLog.record(
        result: AuthEventResult.success,
        method: AuthEventMethod.face,
        operatorId: operator.operatorId,
        operatorNameSnapshot: operator.name,
        role: operator.role.name,
        deviceId: _deviceId,
        plcDeviceName: connectedDeviceName,
        plcDeviceId: macId,
        plcType: connectedPlcType.displayName,
        connectionStatus: _transportConnState.status.name,
      ),
    );

    if (isDeviceConfigured && macId != null) {
      // Mandatory primary gate on an already-configured device — leave
      // _pendingFaceVerification true so currentScreen keeps showing
      // FaceVerificationScreen (already on its own "Welcome, {name}"
      // verified state) while the credential cached at Setup Mode is
      // silently replayed to the PLC in the background. A BLE-level
      // success is caught by currentScreen's `authenticated` case before
      // the pre-auth branch is even consulted, so the operator lands on
      // the control screen directly — no credential screen in between.
      unawaited(_attemptSilentReauthAfterFaceVerification(macId));
    } else {
      // No cached credential to replay (device not yet configured — this
      // was the opt-in identity-verification fallback) — PLC credentials
      // still have to be typed, so fall through to the login screen now.
      _pendingFaceVerification = false;
    }
    notifyListeners();
  }

  /// Silently replays the credential cached at Setup Mode completion so a
  /// face match on a configured device reaches the control screen without
  /// retyping a password. Fails safely either way: no cached credential, or
  /// a PLC rejection (e.g. a rotated password), falls through to
  /// AppScreen.authentication with the identified-operator card already
  /// shown and the biometric/manual-credential fallback still available —
  /// the same outcome [completeFaceVerification] would have produced by
  /// falling through immediately, just deferred until this attempt
  /// actually fails instead of assumed upfront.
  Future<void> _attemptSilentReauthAfterFaceVerification(String macId) async {
    final credentials = await SecureCredentialStore.retrieveCredentials(macId);
    if (credentials == null) {
      _pendingFaceVerification = false;
      notifyListeners();
      return;
    }
    _suppressEnrollmentOfferOnce = true;
    final success = await authenticate(
      email: credentials.email,
      password: credentials.password,
      method: AuthEventMethod.face,
    );
    if (success) {
      // Resolved (and awaited) here so the notifyListeners() below already
      // carries the final answer — otherwise currentScreen's lazy "not yet
      // checked" placeholder would hold on AppScreen.authentication for a
      // frame before the check catches up, putting the credential screen
      // back in front of the operator however briefly.
      await _checkControlAccess();
    }
    _pendingFaceVerification = false;
    notifyListeners();
  }

  /// Logs a face match against a disabled operator profile. The
  /// face-verification screen keeps the operator on that screen either way
  /// — this only records the attempt for the audit trail.
  void recordFaceVerificationDenied(OperatorProfile operator) {
    unawaited(
      _auditLog.record(
        result: AuthEventResult.failed,
        method: AuthEventMethod.face,
        operatorId: operator.operatorId,
        operatorNameSnapshot: operator.name,
        role: operator.role.name,
        deviceId: _deviceId,
        plcDeviceId: _transportConnState.connectedDevice?.id,
        connectionStatus: _transportConnState.status.name,
        failureReason: 'Operator account is disabled.',
        detailCode: 'operator_disabled',
      ),
    );
  }

  /// Logs a face-verification attempt that never matched any enrolled
  /// operator — no-match, a failed/timed-out liveness challenge, or a
  /// lockout being hit. No operator identity is available here (that's the
  /// point of these outcomes), so unlike [completeFaceVerification]/
  /// [recordFaceVerificationDenied] there's no operator to attach. Never
  /// pass a raw match score in [failureReason]/[detailCode] — this screen's
  /// documented invariant is that a similarity score never leaves the
  /// matching service; only categorical reasons do.
  void recordFaceVerificationFailed({
    required String detailCode,
    String? failureReason,
  }) {
    unawaited(
      _auditLog.record(
        result: AuthEventResult.failed,
        method: AuthEventMethod.face,
        deviceId: _deviceId,
        plcDeviceId: _transportConnState.connectedDevice?.id,
        connectionStatus: _transportConnState.status.name,
        failureReason: failureReason,
        detailCode: detailCode,
      ),
    );
  }

  /// Opts into an identity check (Face Verification) as a fallback after
  /// invalid credentials on a device that hasn't completed setup yet. A
  /// match here only identifies the operator as usual via
  /// [completeFaceVerification] — it does not skip PLC credential entry,
  /// since there is no cached credential yet for an unconfigured device.
  void requestIdentityVerificationFallback() {
    if (isDeviceConfigured) return;
    _pendingFaceVerification = true;
    notifyListeners();
  }

  /// Bails out of Face Verification back to the credential screen without
  /// disconnecting — used both to cancel the optional fallback above, and
  /// to jump straight to the biometric/credentials alternatives after Face
  /// Verification fails on an already-configured device.
  void skipFaceVerification() {
    _pendingFaceVerification = false;
    notifyListeners();
  }

  // ── Setup Mode (first-time device configuration) ──────────────────────────

  /// Finishes a never-before-configured device's one-time setup, persisting
  /// which identity methods it will use on every future connection to this
  /// MAC ID. [faceVerificationEnabled] reflects the Setup Mode screen's
  /// toggle; biometric's enabled state was already resolved by the
  /// preceding enrollment-offer step (see [_pendingEnrollmentOffer]/
  /// [enrollBiometrics]).
  Future<void> completeSetupMode({required bool faceVerificationEnabled}) async {
    final macId = _transportConnState.connectedDevice?.id;
    if (macId == null || !_pendingSetupMode) return;

    final biometricEnabled = _biometricEnrolled;
    final credentials = _pendingSetupCredentials;
    if (credentials != null && (faceVerificationEnabled || biometricEnabled)) {
      // No-op if the biometric-enrollment step already wrote this same
      // pair — both mechanisms replay one cached credential per MAC.
      await SecureCredentialStore.storeCredentials(
        macId: macId,
        email: credentials.email,
        password: credentials.password,
      );
    }

    await DeviceSetupRegistry.markSetupComplete(
      macId,
      faceVerificationEnabled: faceVerificationEnabled,
      biometricEnabled: biometricEnabled,
    );

    _deviceSetupRecord = DeviceSetupRecord(
      faceVerificationEnabled: faceVerificationEnabled,
      biometricEnabled: biometricEnabled,
      setupAt: DateTime.now(),
    );
    _pendingSetupCredentials = null;
    _pendingSetupMode = false;
    // Resolved here (and awaited) rather than left to currentScreen's lazy
    // trigger, so the control-access result is already known the instant
    // this Future completes — otherwise SetupModeScreen's caller would
    // briefly flash AppScreen.authentication before the check catches up.
    await _checkControlAccess();
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
