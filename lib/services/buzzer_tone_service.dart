import 'package:flutter/services.dart';

import 'package:rev_crane_control_ops/models/horn_config.dart';

class BuzzerToneService {
  BuzzerToneService._();

  static const String channelName = 'rev_crane_control_ops/buzzer';
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<void> start({
    required String id,
    required HornSoundPattern pattern,
    required AlarmPriority priority,
  }) async {
    try {
      await _channel.invokeMethod<void>('start', {
        'id': id,
        'pattern': pattern.name,
        'priority': priority.name,
      });
    } on MissingPluginException {
      await _fallbackAlert();
    } catch (_) {
      await _fallbackAlert();
    }
  }

  static Future<void> stop({required String id}) async {
    try {
      await _channel.invokeMethod<void>('stop', {'id': id});
    } catch (_) {}
  }

  static Future<void> stopAll() async {
    try {
      await _channel.invokeMethod<void>('stopAll');
    } catch (_) {}
  }

  static Future<void> _fallbackAlert() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
  }
}
