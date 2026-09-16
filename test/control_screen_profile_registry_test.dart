import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/services/control_screen_profile_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ControlScreenProfileRegistry', () {
    test('returns null for an (operator, PLC) pair never saved', () async {
      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        isNull,
      );
    });

    test('save then get round-trips the chosen profile', () async {
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:01',
        ControlScreenProfile.safetyOnly,
      );

      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        ControlScreenProfile.safetyOnly,
      );
    });

    test('two PLCs under the same operator are independent', () async {
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:01',
        ControlScreenProfile.standard,
      );
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:02',
        ControlScreenProfile.safetyOnly,
      );

      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        ControlScreenProfile.standard,
      );
      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:02'),
        ControlScreenProfile.safetyOnly,
      );
    });

    test(
      'the same PLC MAC under two different operators is independent',
      () async {
        // This is the actual requirement: Operator A + PLC14 -> Standard,
        // Operator B + the same PLC14 -> Safety.
        await ControlScreenProfileRegistry.save(
          'operator-a',
          'AA:BB:CC:DD:EE:14',
          ControlScreenProfile.standard,
        );
        await ControlScreenProfileRegistry.save(
          'operator-b',
          'AA:BB:CC:DD:EE:14',
          ControlScreenProfile.safetyOnly,
        );

        expect(
          await ControlScreenProfileRegistry.get(
            'operator-a',
            'AA:BB:CC:DD:EE:14',
          ),
          ControlScreenProfile.standard,
        );
        expect(
          await ControlScreenProfileRegistry.get(
            'operator-b',
            'AA:BB:CC:DD:EE:14',
          ),
          ControlScreenProfile.safetyOnly,
        );
      },
    );

    test('overwriting a saved profile replaces it', () async {
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:01',
        ControlScreenProfile.standard,
      );
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:01',
        ControlScreenProfile.safetyOnly,
      );

      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        ControlScreenProfile.safetyOnly,
      );
    });

    test('a corrupted stored value decodes to null, not a crash', () async {
      SharedPreferences.setMockInitialValues({
        'control_screen_profile_registry_v1':
            '{"op-1": {"AA:BB:CC:DD:EE:01": "not-a-real-profile"}}',
      });

      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        isNull,
      );
    });

    test('resetForTesting clears every saved profile', () async {
      await ControlScreenProfileRegistry.save(
        'op-1',
        'AA:BB:CC:DD:EE:01',
        ControlScreenProfile.safetyOnly,
      );

      await ControlScreenProfileRegistry.resetForTesting();

      expect(
        await ControlScreenProfileRegistry.get('op-1', 'AA:BB:CC:DD:EE:01'),
        isNull,
      );
    });
  });
}
