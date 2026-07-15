class AppConstants {
  AppConstants._();

  static const String plcName = 'IntelliHMI PLC';
  static const String appTitle = 'IntelliMotion HMI';
  static const String appVersion = '1.0.0';

  static const String prefsKeyEmail = 'saved_email';
  static const String prefsKeyPassword = 'saved_password';
  static const String prefsKeyDeviceId = 'last_device_id';

  /// Legacy single-config key from before per-PLC-type layout storage.
  /// Kept only as a one-time migration source — see
  /// [prefsKeyLayoutConfigHoistOnly] / [prefsKeyLayoutConfigFull].
  static const String prefsKeyLayoutConfig = 'control_layout_config_v2';

  /// PLC14 / PLC21 (hoist-only hardware) — shares one bucket since both
  /// route to the same control screen today.
  static const String prefsKeyLayoutConfigHoistOnly =
      'control_layout_config_v2_hoist_only';

  /// PLC38 (all three motion axes).
  static const String prefsKeyLayoutConfigFull =
      'control_layout_config_v2_full';

  static const String defaultAdminEmail = 'admin@plc.com';
  static const String defaultAdminPassword = 'Admin123';
}
