import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:wifi_iot/wifi_iot.dart';

/// Status of the PLC web portal connection helper, in the order a successful
/// run passes through them.
enum PlcWebserverStatus {
  idle,
  connectingToWifi,
  waitingForApproval,
  openingWebserver,
  opened,
  unableToConnect,
  webserverUnavailable,
}

/// Connects this app to the PLC Wi-Fi and prepares the in-app web portal.
///
/// Android scopes a WifiNetworkSpecifier connection to this app process.
/// Routing therefore stays inside IntelliHMI, where the portal WebView can use
/// it. The portal page releases process routing when it closes; this service
/// never disconnects the PLC Wi-Fi network.
class PlcWebserverService {
  final StreamController<PlcWebserverStatus> _statusController =
      StreamController<PlcWebserverStatus>.broadcast();

  Stream<PlcWebserverStatus> get statusStream => _statusController.stream;

  bool _busy = false;
  bool get isBusy => _busy;

  static const Duration _approvalHintDelay = Duration(seconds: 2);
  static const Duration _wifiConnectTimeout = Duration(seconds: 25);

  /// Connects to the configured PLC Wi-Fi and binds this app process to it.
  ///
  /// Returns true when routing is ready for the portal page. On success the
  /// route remains bound so the caller can hand ownership to the WebView page.
  Future<bool> startRegistrationFlow({
    required String wifiSsid,
    String wifiPassword = '',
  }) async {
    if (_busy) return false;
    final ssid = wifiSsid.trim();
    final password = wifiPassword;
    final hasPassword = password.trim().isNotEmpty;
    if (ssid.isEmpty) return false;

    _busy = true;
    _emit(PlcWebserverStatus.connectingToWifi);

    final approvalHintTimer = Timer(_approvalHintDelay, () {
      _emit(PlcWebserverStatus.waitingForApproval);
    });

    bool connected;
    try {
      connected = await WiFiForIoTPlugin.connect(
        ssid,
        password: hasPassword ? password : null,
        security: hasPassword ? NetworkSecurity.WPA : NetworkSecurity.NONE,
        joinOnce: true,
        withInternet: false,
        timeoutInSeconds: _wifiConnectTimeout.inSeconds,
      );
    } catch (_) {
      connected = false;
    } finally {
      approvalHintTimer.cancel();
    }

    if (!connected) {
      _emit(PlcWebserverStatus.unableToConnect);
      _busy = false;
      return false;
    }

    try {
      _emit(PlcWebserverStatus.openingWebserver);
      final routeBound = await bindWifiRouting();
      if (!routeBound) {
        _emit(PlcWebserverStatus.webserverUnavailable);
        return false;
      }

      _emit(PlcWebserverStatus.opened);
      return true;
    } catch (_) {
      _emit(PlcWebserverStatus.webserverUnavailable);
      return false;
    } finally {
      _busy = false;
    }
  }

  /// Routes this app process through Wi-Fi without changing the phone-wide
  /// default network.
  static Future<bool> bindWifiRouting() async {
    try {
      return await WiFiForIoTPlugin.forceWifiUsage(true);
    } catch (_) {
      return false;
    }
  }

  /// Restores normal app-process routing without disconnecting the PLC Wi-Fi.
  static Future<void> releaseWifiRouting() async {
    try {
      await WiFiForIoTPlugin.forceWifiUsage(false);
    } catch (_) {
      // Routing will also be released by Android when the process ends.
    }
  }

  /// Opens the system Wi-Fi settings as a manual connection fallback.
  Future<void> openWifiSettingsManually() {
    return AppSettings.openAppSettings(type: AppSettingsType.wifi);
  }

  void _emit(PlcWebserverStatus status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void dispose() {
    _statusController.close();
  }
}
