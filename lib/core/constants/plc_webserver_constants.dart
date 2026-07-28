/// Configuration for the "open PLC webserver" device-registration helper
/// (Settings → Device Identity). The PLC exposes its registration page over
/// its own Wi-Fi access point — a classic ESP32 SoftAP setup — reachable at
/// a fixed local IP once connected. The SSID/password below are defaults used
/// to prefill the registration helper; the user can edit them before
/// connecting.
abstract final class PlcWebserverConstants {
  /// Default SSID of the PLC's own Wi-Fi access point.
  static const String wifiSsid = 'RRC_PLC';

  /// Default password for [wifiSsid]. Leave empty for an open (unsecured) AP —
  /// [PlcWebserverService] treats an empty password as "no security".
  static const String wifiPassword = '12345678';

  /// Base URL of the PLC's onboard configuration/registration webserver.
  static const String webserverUrl = 'http://192.168.4.1';

  /// Entry point for the PLC webserver login page.
  ///
  /// Keep this separate from [webserverUrl] so firmware with a dedicated
  /// login route can change the controlled back target without changing the
  /// portal host.
  static const String loginUrl = webserverUrl;
}
