import 'package:flutter_test/flutter_test.dart';
import 'package:rev_crane_control_ops/core/constants/ble_constants.dart';
import 'package:rev_crane_control_ops/models/hoist_notification.dart';

void main() {
  test('uses the firmware analog notification characteristic UUID', () {
    expect(BLEConstants.analogCharUuid, '6e400002-b5a3-f393-e0a9-e50e24dcca9e');
  });

  group('HoistNotification.tryParse', () {
    test('parses the three firmware payload shapes', () {
      expect(HoistNotification.tryParse('H1,1234')?.values, {
        HoistNotification.hoist1Key: 1234,
      });
      expect(HoistNotification.tryParse('H2,2345')?.values, {
        HoistNotification.hoist2Key: 2345,
      });
      expect(HoistNotification.tryParse('H1,1234,H2,2345')?.values, {
        HoistNotification.hoist1Key: 1234,
        HoistNotification.hoist2Key: 2345,
      });
    });

    test('accepts the complete uint16 wire range', () {
      expect(HoistNotification.tryParse('H1,0')?.values['H1'], 0);
      expect(
        HoistNotification.tryParse('H2,65535')?.values['H2'],
        HoistNotification.maxWireValue,
      );
    });

    test('rejects legacy and malformed payloads atomically', () {
      const invalidPayloads = [
        'A1:1234',
        'A1,1234',
        'H1:1234',
        'H1,-1',
        'H1,65536',
        'H1,12.5',
        'H1,1234,H2,invalid',
        'H2,2345,H1,1234',
        'H1,1234,H1,2345',
        'H1,1234,H2,2345,',
      ];

      for (final payload in invalidPayloads) {
        expect(HoistNotification.tryParse(payload), isNull, reason: payload);
      }
    });
  });
}
