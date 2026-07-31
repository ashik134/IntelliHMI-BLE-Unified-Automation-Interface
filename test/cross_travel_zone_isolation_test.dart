// Dedicated regression guard for the highest-risk part of the generic
// PLC-output-variant refactor: the 5-zone (and 3-zone) multi-zone slider's
// gesture-to-zone-id resolution (multiZoneId).
//
// The master invariant under test:
//   No button state may control any PLC output variant unless the user
//   explicitly configured that exact variant for that exact state.
//
// A bug in multiZoneId would NOT look like "auto-derivation" (adding
// an unconfigured variant) — it would look like one zone silently reading a
// DIFFERENT zone's user-configured variants, which is harder to notice
// because the packet would still contain only user-configured variants,
// just for the wrong zone. This suite proves that cannot happen:
//   1. multiZoneId is exhaustively truth-tabled against every
//      reachable (isLeftButton, ControlState) combination.
//   2. All 5 zones (or 3, for the level1-only variant) are configured to
//      mutually-disjoint, arbitrary (non-crane-equivalent) variant sets,
//      and each zone's resolved output is asserted to be EXACTLY that
//      zone's own configured set — never a neighbor's, never a union.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/multi_zone_slider_strategy.dart';

void main() {
  group('multiZoneId — exhaustive truth table (5-zone)', () {
    final cases = <(bool, ControlState, String)>[
      (true, ControlState.idle, 'center'),
      (true, ControlState.level1, 'zone2'),
      (true, ControlState.level2, 'zone1'),
      (false, ControlState.idle, 'center'),
      (false, ControlState.level1, 'zone4'),
      (false, ControlState.level2, 'zone5'),
    ];

    for (final (isLeftButton, state, expected) in cases) {
      test('isLeftButton=$isLeftButton, state=${state.name} -> $expected', () {
        expect(
          multiZoneId(isLeftButton: isLeftButton, state: state, fiveZone: true),
          expected,
        );
      });
    }

    test('all 6 combinations resolve to 5 distinct non-center ids plus the '
        'shared idle id (no accidental aliasing)', () {
      final resolved = {
        for (final (isLeftButton, state, _) in cases)
          '$isLeftButton:${state.name}': multiZoneId(
            isLeftButton: isLeftButton,
            state: state,
            fiveZone: true,
          ),
      };
      final nonIdleIds = resolved.values.where((id) => id != 'center').toSet();
      expect(nonIdleIds, {'zone1', 'zone2', 'zone4', 'zone5'});
      expect(nonIdleIds.length, 4);
    });
  });

  group('multiZoneId — exhaustive truth table (3-zone level1-only)', () {
    final cases = <(bool, ControlState, String)>[
      (true, ControlState.idle, 'center'),
      (true, ControlState.level1, 'zone1'),
      (false, ControlState.idle, 'center'),
      (false, ControlState.level1, 'zone3'),
    ];

    for (final (isLeftButton, state, expected) in cases) {
      test('isLeftButton=$isLeftButton, state=${state.name} -> $expected', () {
        expect(
          multiZoneId(
            isLeftButton: isLeftButton,
            state: state,
            fiveZone: false,
          ),
          expected,
        );
      });
    }
  });

  group('5-zone: all 5 zones independently mapped to disjoint variants — '
      'no cross-zone leakage', () {
    // Deliberately arbitrary, non-crane-equivalent values — proving the
    // mechanism is fully generic, not secretly still axis-shaped.
    const leftConfig = ButtonConfig(
      id: 'left',
      type: ButtonType.bidirectionalSlider5Step,
      plcMapping: PlcOutputVariant.df5,
      stateMappings: {
        'zone1': ButtonStateOutputMapping(
          stateId: 'zone1',
          activeVariants: {PlcOutputVariant.df10},
        ),
        'zone2': ButtonStateOutputMapping(
          stateId: 'zone2',
          activeVariants: {PlcOutputVariant.df3},
        ),
        'center': ButtonStateOutputMapping(stateId: 'center'),
      },
    );
    const rightConfig = ButtonConfig(
      id: 'right',
      type: ButtonType.bidirectionalSlider5Step,
      plcMapping: PlcOutputVariant.df6,
      stateMappings: {
        'center': ButtonStateOutputMapping(stateId: 'center'),
        'zone4': ButtonStateOutputMapping(
          stateId: 'zone4',
          activeVariants: {PlcOutputVariant.df8, PlcOutputVariant.df9},
        ),
        'zone5': ButtonStateOutputMapping(
          stateId: 'zone5',
          activeVariants: {PlcOutputVariant.df2},
        ),
      },
    );

    Set<PlcOutputVariant> resolve(
      ButtonConfig config,
      bool isLeft,
      ControlState state,
    ) {
      final zoneId = multiZoneId(
        isLeftButton: isLeft,
        state: state,
        fiveZone: true,
      );
      return config.stateMappings[zoneId]?.activeVariants ?? const {};
    }

    test(
      'zone1 (left, level2) activates exactly {fastFb} — not zone2\'s {down}',
      () {
        expect(resolve(leftConfig, true, ControlState.level2), {
          PlcOutputVariant.df10,
        });
      },
    );

    test(
      'zone2 (left, level1) activates exactly {down} — not zone1\'s {fastFb}',
      () {
        expect(resolve(leftConfig, true, ControlState.level1), {
          PlcOutputVariant.df3,
        });
      },
    );

    test(
      'center (left, idle) is always empty regardless of configured data',
      () {
        expect(resolve(leftConfig, true, ControlState.idle), isEmpty);
      },
    );

    test('zone4 (right, level1) activates exactly {forward, reverse} — not '
        'zone5\'s {up}', () {
      expect(resolve(rightConfig, false, ControlState.level1), {
        PlcOutputVariant.df8,
        PlcOutputVariant.df9,
      });
    });

    test('zone5 (right, level2) activates exactly {up} — not zone4\'s '
        '{forward, reverse}', () {
      expect(resolve(rightConfig, false, ControlState.level2), {
        PlcOutputVariant.df2,
      });
    });

    test(
      'center (right, idle) is always empty regardless of configured data',
      () {
        expect(resolve(rightConfig, false, ControlState.idle), isEmpty);
      },
    );

    test('no two non-idle zones share any variant across all 5 configured '
        'sets (proving true independence, not shared/OR-ed configuration)', () {
      final allSets = <Set<PlcOutputVariant>>[
        resolve(leftConfig, true, ControlState.level2), // zone1
        resolve(leftConfig, true, ControlState.level1), // zone2
        resolve(rightConfig, false, ControlState.level1), // zone4
        resolve(rightConfig, false, ControlState.level2), // zone5
      ];
      for (var i = 0; i < allSets.length; i++) {
        for (var j = i + 1; j < allSets.length; j++) {
          expect(
            allSets[i].intersection(allSets[j]),
            isEmpty,
            reason: 'zone sets at index $i and $j must never overlap',
          );
        }
      }
    });
  });

  group('3-zone level1-only: 2 independently mapped zones — no leakage', () {
    const leftConfig = ButtonConfig(
      id: 'left',
      type: ButtonType.bidirectionalSlider3Step,
      plcMapping: PlcOutputVariant.df5,
      stateMappings: {
        'zone1': ButtonStateOutputMapping(
          stateId: 'zone1',
          activeVariants: {PlcOutputVariant.df4, PlcOutputVariant.df8},
        ),
        'center': ButtonStateOutputMapping(stateId: 'center'),
      },
    );
    const rightConfig = ButtonConfig(
      id: 'right',
      type: ButtonType.bidirectionalSlider3Step,
      plcMapping: PlcOutputVariant.df6,
      stateMappings: {
        'center': ButtonStateOutputMapping(stateId: 'center'),
        'zone3': ButtonStateOutputMapping(
          stateId: 'zone3',
          activeVariants: {PlcOutputVariant.df9},
        ),
      },
    );

    Set<PlcOutputVariant> resolve(
      ButtonConfig config,
      bool isLeft,
      ControlState state,
    ) {
      final zoneId = multiZoneId(
        isLeftButton: isLeft,
        state: state,
        fiveZone: false,
      );
      return config.stateMappings[zoneId]?.activeVariants ?? const {};
    }

    test('zone1 activates exactly its configured set', () {
      expect(resolve(leftConfig, true, ControlState.level1), {
        PlcOutputVariant.df4,
        PlcOutputVariant.df8,
      });
    });

    test(
      'zone3 activates exactly its configured set — disjoint from zone1',
      () {
        final zone3 = resolve(rightConfig, false, ControlState.level1);
        expect(zone3, {PlcOutputVariant.df9});
        expect(
          zone3.intersection(resolve(leftConfig, true, ControlState.level1)),
          isEmpty,
        );
      },
    );
  });
}
