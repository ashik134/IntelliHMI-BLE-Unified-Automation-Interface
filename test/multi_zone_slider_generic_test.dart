// Regression guard for the generic (role==null) multi-zone slider path:
// a free-standing ButtonConfig — no ControlRole, no crane/traverse pairing —
// must resolve its own PLC outputs directly from its own
// ButtonConfig.stateMappings, keyed by exactly the zone id
// MultiZoneSliderButton reports. Unlike the legacy paired crane path (see
// cross_travel_zone_isolation_test.dart), there is no crossTravelZoneId
// translation step in this path at all.
//
// Also covers:
//   - zoneIdToSideAndState is the exact inverse of crossTravelZoneId (the
//     legacy paired path's only translation step).
//   - grid sizing: 3-zone defaults to 1x1, 5-zone defaults to 2x1 and can be
//     resized to a vertical 1x2 (but never anything else).

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/plc_output_variant.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';
import 'package:rev_crane_control_ops/widgets/buttons/strategy/multi_zone_slider_strategy.dart';

void main() {
  group('MultiZoneSliderStateId — zone sets', () {
    test('five-zone values are exactly center/zone1/zone2/zone4/zone5', () {
      expect(MultiZoneSliderStateId.fiveZoneValues, {
        MultiZoneSliderStateId.center,
        MultiZoneSliderStateId.zone1,
        MultiZoneSliderStateId.zone2,
        MultiZoneSliderStateId.zone4,
        MultiZoneSliderStateId.zone5,
      });
    });

    test('three-zone values are exactly center/zone1/zone3', () {
      expect(MultiZoneSliderStateId.threeZoneValues, {
        MultiZoneSliderStateId.center,
        MultiZoneSliderStateId.zone1,
        MultiZoneSliderStateId.zone3,
      });
    });

    test('normalize falls back to center for an id outside the variant', () {
      expect(
        MultiZoneSliderStateId.normalize('zone4', fiveZone: false),
        MultiZoneSliderStateId.center,
      );
      expect(
        MultiZoneSliderStateId.normalize('zone3', fiveZone: true),
        MultiZoneSliderStateId.center,
      );
    });

    test('normalize passes through a value already in the variant', () {
      expect(
        MultiZoneSliderStateId.normalize('zone2', fiveZone: true),
        'zone2',
      );
    });
  });

  group('Generic (role==null) 5-zone: each zone resolves exactly its own '
      'configured outputs — no ControlRole, no pairing, no leakage', () {
    // A free-standing button, deliberately with disjoint/arbitrary variants
    // per zone (not the crane-equivalent shared left/right sets) — proving
    // the generic path is a pure 1:1 stateMappings lookup.
    const config = ButtonConfig(
      id: 'custom_multi_zone_1',
      type: ButtonType.bidirectionalSlider5Step,
      plcMapping: PlcOutputVariant.df2,
      role: null,
      label: 'Freestanding',
      stateMappings: {
        'zone1': ButtonStateOutputMapping(
          stateId: 'zone1',
          activeVariants: {PlcOutputVariant.df10},
        ),
        'zone2': ButtonStateOutputMapping(
          stateId: 'zone2',
          activeVariants: {PlcOutputVariant.df4},
        ),
        'center': ButtonStateOutputMapping(stateId: 'center'),
        'zone4': ButtonStateOutputMapping(
          stateId: 'zone4',
          activeVariants: {PlcOutputVariant.df7, PlcOutputVariant.df9},
        ),
        'zone5': ButtonStateOutputMapping(
          stateId: 'zone5',
          activeVariants: {PlcOutputVariant.df3},
        ),
      },
    );

    test('has no ControlRole at all', () {
      expect(config.role, isNull);
    });

    test('zone1 resolves exactly its configured set', () {
      expect(config.stateMappings['zone1']?.activeVariants, {
        PlcOutputVariant.df10,
      });
    });

    test('zone2 resolves exactly its configured set — disjoint from zone1', () {
      expect(config.stateMappings['zone2']?.activeVariants, {
        PlcOutputVariant.df4,
      });
    });

    test('center always resolves to no active outputs', () {
      expect(config.stateMappings['center']?.activeVariants, isEmpty);
    });

    test('zone4 resolves exactly its configured set', () {
      expect(config.stateMappings['zone4']?.activeVariants, {
        PlcOutputVariant.df7,
        PlcOutputVariant.df9,
      });
    });

    test('zone5 resolves exactly its configured set — disjoint from zone4', () {
      expect(config.stateMappings['zone5']?.activeVariants, {
        PlcOutputVariant.df3,
      });
    });

    test('no two non-center zones share any configured variant', () {
      final sets = [
        config.stateMappings['zone1']!.activeVariants,
        config.stateMappings['zone2']!.activeVariants,
        config.stateMappings['zone4']!.activeVariants,
        config.stateMappings['zone5']!.activeVariants,
      ];
      for (var i = 0; i < sets.length; i++) {
        for (var j = i + 1; j < sets.length; j++) {
          expect(
            sets[i].intersection(sets[j]),
            isEmpty,
            reason: 'zone sets at index $i and $j must never overlap',
          );
        }
      }
    });
  });

  group('Generic (role==null) 3-zone: independently mapped zones', () {
    const config = ButtonConfig(
      id: 'custom_multi_zone_2',
      type: ButtonType.bidirectionalSlider3Step,
      plcMapping: PlcOutputVariant.df2,
      role: null,
      label: 'Freestanding 3-zone',
      stateMappings: {
        'zone1': ButtonStateOutputMapping(
          stateId: 'zone1',
          activeVariants: {PlcOutputVariant.df8},
        ),
        'center': ButtonStateOutputMapping(stateId: 'center'),
        'zone3': ButtonStateOutputMapping(
          stateId: 'zone3',
          activeVariants: {PlcOutputVariant.df9},
        ),
      },
    );

    test('has no ControlRole at all', () {
      expect(config.role, isNull);
    });

    test('zone1 resolves exactly its configured set', () {
      expect(config.stateMappings['zone1']?.activeVariants, {
        PlcOutputVariant.df8,
      });
    });

    test('center always resolves to no active outputs', () {
      expect(config.stateMappings['center']?.activeVariants, isEmpty);
    });

    test('zone3 resolves exactly its configured set — disjoint from zone1', () {
      final zone3 = config.stateMappings['zone3']?.activeVariants;
      expect(zone3, {PlcOutputVariant.df9});
      expect(
        zone3!.intersection(config.stateMappings['zone1']!.activeVariants),
        isEmpty,
      );
    });
  });

  group('zoneIdToSideAndState is the exact inverse of crossTravelZoneId '
      '(legacy paired path only)', () {
    test('5-zone: every reachable (isLeftButton, state) round-trips', () {
      for (final isLeftButton in [true, false]) {
        for (final state in ControlState.values) {
          final zoneId = crossTravelZoneId(
            isLeftButton: isLeftButton,
            state: state,
            fiveZone: true,
          );
          final resolved = zoneIdToSideAndState(
            zoneId: zoneId,
            fiveZone: true,
          );
          if (state == ControlState.idle) {
            // idle always maps to 'center', which zoneIdToSideAndState
            // resolves back with isLeftButton=true by convention — the
            // caller special-cases idle before consulting isLeftButton
            // (see MultiZoneSliderStrategy.buildPaired).
            expect(resolved.state, ControlState.idle);
          } else {
            expect(
              resolved,
              (isLeftButton: isLeftButton, state: state),
              reason: 'zoneId=$zoneId must round-trip to the same side/state',
            );
          }
        }
      }
    });

    test('3-zone: every reachable slow-state round-trips', () {
      for (final isLeftButton in [true, false]) {
        final zoneId = crossTravelZoneId(
          isLeftButton: isLeftButton,
          state: ControlState.slow,
          fiveZone: false,
        );
        final resolved = zoneIdToSideAndState(zoneId: zoneId, fiveZone: false);
        expect(resolved, (isLeftButton: isLeftButton, state: ControlState.slow));
      }
    });

    test('throws on an unrecognized zone id rather than silently defaulting '
        'to center', () {
      expect(
        () => zoneIdToSideAndState(zoneId: 'zone5', fiveZone: false),
        throwsArgumentError,
      );
      expect(
        () => zoneIdToSideAndState(zoneId: 'bogus', fiveZone: true),
        throwsArgumentError,
      );
    });
  });

  group('Grid sizing', () {
    test('3-zone default size is 1x1', () {
      expect(
        ButtonConfig.defaultGridSizeFor(ButtonType.bidirectionalSlider3Step),
        (1, 1),
      );
    });

    test('5-zone default size is 2x1 (horizontal)', () {
      expect(
        ButtonConfig.defaultGridSizeFor(ButtonType.bidirectionalSlider5Step),
        (2, 1),
      );
    });

    test('3-zone ButtonConfig reports a 1x1 grid span by default', () {
      const config = ButtonConfig(
        id: 'g1',
        type: ButtonType.bidirectionalSlider3Step,
        plcMapping: PlcOutputVariant.df2,
      );
      expect(config.gridColumnSpan, 1);
      expect(config.gridRowSpan, 1);
    });

    test('5-zone ButtonConfig reports a 2x1 grid span by default', () {
      const config = ButtonConfig(
        id: 'g2',
        type: ButtonType.bidirectionalSlider5Step,
        plcMapping: PlcOutputVariant.df2,
      );
      expect(config.gridColumnSpan, 2);
      expect(config.gridRowSpan, 1);
    });

    test(
      '5-zone ButtonConfig honors an explicit vertical 1x2 override',
      () {
        const config = ButtonConfig(
          id: 'g3',
          type: ButtonType.bidirectionalSlider5Step,
          plcMapping: PlcOutputVariant.df2,
          gridColumns: 1,
          gridRows: 2,
        );
        expect(config.gridColumnSpan, 1);
        expect(config.gridRowSpan, 2);
      },
    );

    test('buildButtonResize snaps a 5-zone request toward vertical (1x2) '
        'when rows > columns are requested', () {
      const selected = ButtonConfig(
        id: 'r1',
        type: ButtonType.bidirectionalSlider5Step,
        plcMapping: PlcOutputVariant.df2,
        gridColumns: 2,
        gridRows: 1,
        slotIndex: 0,
      );
      final result = buildButtonResize(
        buttons: {selected.id: selected},
        selected: selected,
        gridColumns: 1,
        gridRows: 2,
      );
      expect(result.isValid, isTrue);
      final resized = result.buttons![selected.id]!;
      expect(resized.gridColumns, 1);
      expect(resized.gridRows, 2);
    });

    test('buildButtonResize snaps a 5-zone request toward horizontal (2x1) '
        'when columns >= rows are requested', () {
      const selected = ButtonConfig(
        id: 'r2',
        type: ButtonType.bidirectionalSlider5Step,
        plcMapping: PlcOutputVariant.df2,
        gridColumns: 1,
        gridRows: 2,
        slotIndex: 0,
      );
      final result = buildButtonResize(
        buttons: {selected.id: selected},
        selected: selected,
        gridColumns: 2,
        gridRows: 1,
      );
      expect(result.isValid, isTrue);
      final resized = result.buttons![selected.id]!;
      expect(resized.gridColumns, 2);
      expect(resized.gridRows, 1);
    });

    test('buildButtonResize never leaves a 5-zone slider at 1x1', () {
      const selected = ButtonConfig(
        id: 'r3',
        type: ButtonType.bidirectionalSlider5Step,
        plcMapping: PlcOutputVariant.df2,
        gridColumns: 2,
        gridRows: 1,
        slotIndex: 0,
      );
      final result = buildButtonResize(
        buttons: {selected.id: selected},
        selected: selected,
        gridColumns: 1,
        gridRows: 1,
      );
      expect(result.isValid, isTrue);
      final resized = result.buttons![selected.id]!;
      expect(resized.gridColumns * resized.gridRows, 2);
    });

    test('buildButtonResize still enforces the normal 1x1 minimum for '
        '3-zone (no special-casing)', () {
      const selected = ButtonConfig(
        id: 'r4',
        type: ButtonType.bidirectionalSlider3Step,
        plcMapping: PlcOutputVariant.df2,
        gridColumns: 1,
        gridRows: 1,
        slotIndex: 0,
      );
      final result = buildButtonResize(
        buttons: {selected.id: selected},
        selected: selected,
        gridColumns: 1,
        gridRows: 1,
      );
      expect(result.isValid, isTrue);
      final resized = result.buttons![selected.id]!;
      expect(resized.gridColumns, 1);
      expect(resized.gridRows, 1);
    });
  });
}
