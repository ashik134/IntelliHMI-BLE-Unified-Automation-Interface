import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/models/feedback/analog_feedback_config.dart';
import 'package:rev_crane_control_ops/models/hoist_notification.dart';

void main() {
  test('default readers match the firmware hoist channels and scale', () {
    expect(
      kDefaultAnalogFeedbackChannels.map((channel) => channel.channelKey),
      [HoistNotification.hoist1Key, HoistNotification.hoist2Key],
    );
    expect(kDefaultAnalogFeedbackChannels.map((channel) => channel.rawMax), [
      HoistNotification.firmwareFullScale,
      HoistNotification.firmwareFullScale,
    ]);
  });

  test('migrates legacy A1/A2 sources and former default range', () {
    final hoist1 = AnalogFeedbackConfig.fromJson({
      'channelKey': 'A1',
      'rawMax': 4095,
      'displayMax': 4095,
    });
    final hoist2 = AnalogFeedbackConfig.fromJson({
      'channelKey': 'A2',
      'rawMax': 4095,
      'displayMax': 25,
    });

    expect(hoist1.channelKey, HoistNotification.hoist1Key);
    expect(hoist1.rawMax, HoistNotification.firmwareFullScale);
    expect(hoist1.displayMax, HoistNotification.firmwareFullScale);

    expect(hoist2.channelKey, HoistNotification.hoist2Key);
    expect(hoist2.rawMax, HoistNotification.firmwareFullScale);
    expect(hoist2.displayMax, 25);
  });
}
