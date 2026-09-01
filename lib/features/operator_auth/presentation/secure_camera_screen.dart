import 'package:flutter/services.dart';

class SecureCameraScreen {
  SecureCameraScreen._();

  static const MethodChannel _channel = MethodChannel(
    'rev_crane_control_ops/security',
  );

  static Future<void> setEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setSecureScreen', {
        'enabled': enabled,
      });
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not install the Android
      // channel. Production Android camera screens still fail closed through
      // their own no-camera/no-SDK states.
    }
  }
}
