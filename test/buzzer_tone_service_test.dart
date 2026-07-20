import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/horn_config.dart';
import 'package:rev_crane_control_ops/services/buzzer_tone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(BuzzerToneService.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('start sends buzzer id, sound pattern, and priority', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await BuzzerToneService.start(
      id: 'horn-1',
      pattern: HornSoundPattern.doubleBeep,
      priority: AlarmPriority.high,
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'start');
    expect(calls.single.arguments, {
      'id': 'horn-1',
      'pattern': 'doubleBeep',
      'priority': 'high',
    });
  });

  test('stop sends the buzzer id', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });

    await BuzzerToneService.stop(id: 'horn-1');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'stop');
    expect(calls.single.arguments, {'id': 'horn-1'});
  });
}
