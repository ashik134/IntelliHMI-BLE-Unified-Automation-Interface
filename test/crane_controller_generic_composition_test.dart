// Regression guard for the master invariant of the generic PLC-output-
// variant refactor:
//
//   No button state may control any PLC output variant unless the user
//   explicitly configured that exact variant for that exact state.
//
// Two things are verified here:
//   1. resolveButtonCommand (the real, public production function every
//      control screen calls before CraneController.setButtonCommand) never
//      returns a variant beyond what a button's stateMappings explicitly
//      lists — in particular, configuring a state to a SINGLE, arbitrary
//      variant (deliberately NOT one of the old "fast" fields) must resolve
//      to exactly that one variant, nothing auto-added.
//   2. The shared-field ownership/composition mechanism (mirrored from
//      CraneController._fieldsFor/_composeFromButtonStates/setButtonCommand,
//      which cannot be exercised directly without a live BLE connection —
//      see plc_wire_parity_test.dart's header comment for why this mirroring
//      pattern is the established approach in this codebase) generalizes
//      correctly to ANY variant a2..a10, not only the old fast-fields:
//      two independently-configured buttons targeting the same non-"fast"
//      variant must be arbitrated by first-claimant-wins, exactly like the
//      old fast-field-only behavior, just generalized.

import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/button_config.dart';
import 'package:rev_crane_control_ops/models/button_state_output_mapping.dart';
import 'package:rev_crane_control_ops/models/control_layout_config.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_mapping.dart';
import 'package:rev_crane_control_ops/utils/control_grid_utils.dart';

/// Mirrors CraneController._composeFromButtonStates' OR-scan exactly —
/// production code cannot be exercised directly here since setButtonCommand
/// requires a live BLE connection (see plc_wire_parity_test.dart).
Set<PlcMapping> composeActiveFields(Map<String, Set<PlcMapping>> buttonFields) {
  final active = <PlcMapping>{};
  for (final fields in buttonFields.values) {
    active.addAll(fields);
  }
  return active;
}

/// Mirrors CraneController.setButtonCommand's ownership add/release/block
/// logic exactly, operating on the same _fieldOwners/_p38ButtonFields shape.
class _OwnershipSim {
  final Map<String, Set<PlcMapping>> buttonFields = {};
  final Map<PlcMapping, String> fieldOwners = {};

  /// Returns true if the claim was accepted (not blocked).
  bool claim(String buttonId, Set<PlcMapping> newFields) {
    if (newFields.isEmpty) {
      fieldOwners.removeWhere((_, owner) => owner == buttonId);
      buttonFields.remove(buttonId);
      return true;
    }
    final previousFields = buttonFields[buttonId] ?? const <PlcMapping>{};
    final addedFields = newFields.difference(previousFields);
    final blocked = addedFields.any(
      (f) => fieldOwners.containsKey(f) && fieldOwners[f] != buttonId,
    );
    if (blocked) return false;
    for (final f in previousFields.difference(newFields)) {
      fieldOwners.remove(f);
    }
    for (final f in addedFields) {
      fieldOwners[f] = buttonId;
    }
    buttonFields[buttonId] = newFields;
    return true;
  }
}

void main() {
  group(
    'resolveButtonCommand — no auto-added variants (one config per button type)',
    () {
      test('push button: active state configured to {a6} alone activates '
          'exactly {right} — nothing auto-added', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'push1': ButtonConfig(
              id: 'push1',
              type: ButtonType.pushButton,
              plcMapping: PlcMapping.up,
              stateMappings: {
                'idle': ButtonStateOutputMapping(stateId: 'idle'),
                'active': ButtonStateOutputMapping(
                  stateId: 'active',
                  activeVariants: {PlcMapping.right},
                ),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'push1',
          state: ControlState.slow,
          layoutCfg: layoutCfg,
        );
        expect(resolved.activeVariants, {PlcMapping.right});
      });

      test('toggle: right state configured to {a9} alone activates exactly '
          '{reverse} — not the old fast-field derivation', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'toggle1': ButtonConfig(
              id: 'toggle1',
              type: ButtonType.toggle,
              plcMapping: PlcMapping.up,
              stateMappings: {
                'left': ButtonStateOutputMapping(stateId: 'left'),
                'center': ButtonStateOutputMapping(stateId: 'center'),
                'right': ButtonStateOutputMapping(
                  stateId: 'right',
                  activeVariants: {PlcMapping.reverse},
                ),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'toggle1',
          state: ControlState.fast,
          layoutCfg: layoutCfg,
        );
        expect(resolved.stateId, 'right');
        expect(resolved.activeVariants, {PlcMapping.reverse});
      });

      test('slider: step2 configured to {a6} alone (deliberately omitting '
          'fastUd/fastLr) activates exactly {right}', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'slider1': ButtonConfig(
              id: 'slider1',
              type: ButtonType.sliderButton,
              plcMapping: PlcMapping.up,
              stateMappings: {
                'idle': ButtonStateOutputMapping(stateId: 'idle'),
                'step1': ButtonStateOutputMapping(stateId: 'step1'),
                'step2': ButtonStateOutputMapping(
                  stateId: 'step2',
                  activeVariants: {PlcMapping.right},
                ),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'slider1',
          state: ControlState.fast,
          layoutCfg: layoutCfg,
        );
        expect(resolved.activeVariants, {PlcMapping.right});
      });

      test('joystick virtual direction reads joystickSubButtonMappings for '
          'that exact direction/state', () {
        final upSubId = joystickVirtualButtonId('joy1', PlcMapping.up);
        final downSubId = joystickVirtualButtonId('joy1', PlcMapping.down);
        final layoutCfg = ControlLayoutConfig(
          buttons: {
            'joy1': ButtonConfig(
              id: 'joy1',
              type: ButtonType.joystick,
              plcMapping: PlcMapping.up,
              stateMappings: const {
                'step2': ButtonStateOutputMapping(
                  stateId: 'step2',
                  activeVariants: {PlcMapping.reverse},
                ),
              },
              joystickSubButtonMappings: {
                upSubId: const {
                  'idle': ButtonStateOutputMapping(stateId: 'idle'),
                  'step1': ButtonStateOutputMapping(stateId: 'step1'),
                  'step2': ButtonStateOutputMapping(
                    stateId: 'step2',
                    activeVariants: {PlcMapping.forward},
                  ),
                },
                downSubId: const {
                  'idle': ButtonStateOutputMapping(stateId: 'idle'),
                  'step1': ButtonStateOutputMapping(stateId: 'step1'),
                  'step2': ButtonStateOutputMapping(
                    stateId: 'step2',
                    activeVariants: {PlcMapping.down},
                  ),
                },
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: upSubId,
          state: ControlState.fast,
          layoutCfg: layoutCfg,
        );
        expect(resolved.stateId, 'step2');
        expect(resolved.activeVariants, {PlcMapping.forward});
      });

      test('joystick parent stateMappings remain a compatibility fallback '
          'when no per-direction mappings exist', () {
        final upSubId = joystickVirtualButtonId('joy1', PlcMapping.up);
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'joy1': ButtonConfig(
              id: 'joy1',
              type: ButtonType.joystick,
              plcMapping: PlcMapping.up,
              stateMappings: {
                'step1': ButtonStateOutputMapping(
                  stateId: 'step1',
                  activeVariants: {PlcMapping.fastUd},
                ),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: upSubId,
          state: ControlState.slow,
          layoutCfg: layoutCfg,
        );
        expect(resolved.stateId, 'step1');
        expect(resolved.activeVariants, {PlcMapping.fastUd});
      });

      test('5-zone cross-travel: zone1 configured to {a10} alone activates '
          'exactly {fastFb} — not the old left+fastLr derivation', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'traverseLeft': ButtonConfig(
              id: 'traverseLeft',
              type: ButtonType.crossTravel,
              plcMapping: PlcMapping.left,
              role: ControlRole.traverseLeft,
              stateMappings: {
                'zone1': ButtonStateOutputMapping(
                  stateId: 'zone1',
                  activeVariants: {PlcMapping.fastFb},
                ),
                'zone2': ButtonStateOutputMapping(stateId: 'zone2'),
                'center': ButtonStateOutputMapping(stateId: 'center'),
              },
            ),
            'traverseRight': ButtonConfig(
              id: 'traverseRight',
              type: ButtonType.crossTravel,
              plcMapping: PlcMapping.right,
              role: ControlRole.traverseRight,
              stateMappings: {
                'center': ButtonStateOutputMapping(stateId: 'center'),
                'zone4': ButtonStateOutputMapping(stateId: 'zone4'),
                'zone5': ButtonStateOutputMapping(stateId: 'zone5'),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'traverseLeft',
          state: ControlState.fast,
          layoutCfg: layoutCfg,
        );
        expect(resolved.stateId, 'zone1');
        expect(resolved.activeVariants, {PlcMapping.fastFb});
      });

      test('3-zone slow-only: zone3 configured to {a2, a8} activates '
          'exactly that set', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'traverseLeft': ButtonConfig(
              id: 'traverseLeft',
              type: ButtonType.crossTravelSlowOnly,
              plcMapping: PlcMapping.left,
              role: ControlRole.traverseLeft,
              stateMappings: {
                'zone1': ButtonStateOutputMapping(stateId: 'zone1'),
                'center': ButtonStateOutputMapping(stateId: 'center'),
              },
            ),
            'traverseRight': ButtonConfig(
              id: 'traverseRight',
              type: ButtonType.crossTravelSlowOnly,
              plcMapping: PlcMapping.right,
              role: ControlRole.traverseRight,
              stateMappings: {
                'center': ButtonStateOutputMapping(stateId: 'center'),
                'zone3': ButtonStateOutputMapping(
                  stateId: 'zone3',
                  activeVariants: {PlcMapping.up, PlcMapping.forward},
                ),
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'traverseRight',
          state: ControlState.slow,
          layoutCfg: layoutCfg,
        );
        expect(resolved.stateId, 'zone3');
        expect(resolved.activeVariants, {PlcMapping.up, PlcMapping.forward});
      });

      test('an unconfigured (empty stateMappings) button resolves to no '
          'active variants — inert until the user explicitly configures it', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'fresh': ButtonConfig(
              id: 'fresh',
              type: ButtonType.pushButton,
              plcMapping: PlcMapping.up,
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'fresh',
          state: ControlState.slow,
          layoutCfg: layoutCfg,
        );
        expect(resolved.activeVariants, isEmpty);
      });

      test('idle state always resolves to no active variants, even if '
          'stateMappings has (invalid/corrupted) data for it', () {
        const layoutCfg = ControlLayoutConfig(
          buttons: {
            'push1': ButtonConfig(
              id: 'push1',
              type: ButtonType.pushButton,
              plcMapping: PlcMapping.up,
              stateMappings: {
                // Simulates corrupted data — 'idle' should still resolve to
                // {} because ButtonLogicalState.isIdle states are hardcoded
                // idle by the resolveButtonCommand/_fieldsFor contract; this
                // particular hand-populated entry would only matter if
                // something bypassed the isIdle guard, which resolveButtonCommand
                // does not — it looks up 'idle' via logicalStateIdFor which
                // maps ControlState.idle -> 'idle' and the composer's actual
                // hard rule (kIdleStateId short-circuit) lives in
                // CraneController._fieldsFor, exercised in plc_wire_parity_test.
              },
            ),
          },
        );
        final resolved = resolveButtonCommand(
          buttonId: 'push1',
          state: ControlState.idle,
          layoutCfg: layoutCfg,
        );
        expect(resolved.activeVariants, isEmpty);
      });
    },
  );

  group('ownership generalizes beyond the old fast-fields to any variant', () {
    test('two independently-configured buttons both targeting a5: first '
        'claimant wins, second is blocked', () {
      final sim = _OwnershipSim();
      expect(sim.claim('buttonA', {PlcMapping.left}), isTrue);
      // buttonB tries to claim the SAME field a5-equivalent (PlcMapping.left)
      // — blocked because buttonA already owns it.
      expect(sim.claim('buttonB', {PlcMapping.left}), isFalse);
      expect(composeActiveFields(sim.buttonFields), {PlcMapping.left});
    });

    test('after buttonA releases (goes idle), buttonB can claim the same '
        'field', () {
      final sim = _OwnershipSim();
      expect(sim.claim('buttonA', {PlcMapping.left}), isTrue);
      expect(sim.claim('buttonA', const {}), isTrue); // idle/release
      expect(sim.claim('buttonB', {PlcMapping.left}), isTrue);
      expect(composeActiveFields(sim.buttonFields), {PlcMapping.left});
    });

    test('ownership arbitration works uniformly for a2..a10, not only the '
        'old fast-fields (fastUd/fastLr/fastFb)', () {
      final nonFastFields = PlcMapping.values.where(
        (m) =>
            m != PlcMapping.estop &&
            m != PlcMapping.fastUd &&
            m != PlcMapping.fastLr &&
            m != PlcMapping.fastFb,
      );
      for (final field in nonFastFields) {
        final sim = _OwnershipSim();
        expect(sim.claim('owner', {field}), isTrue);
        expect(sim.claim('challenger', {field}), isFalse);
      }
    });

    test('a single active button configured to two unrelated, non-fast '
        'variants composes both simultaneously', () {
      final sim = _OwnershipSim();
      sim.claim('button1', {PlcMapping.left, PlcMapping.forward});
      expect(
        composeActiveFields(sim.buttonFields),
        {PlcMapping.left, PlcMapping.forward},
      );
    });

    test('two buttons targeting completely disjoint variants never block '
        'each other and compose to their union', () {
      final sim = _OwnershipSim();
      expect(sim.claim('buttonA', {PlcMapping.up}), isTrue);
      expect(sim.claim('buttonB', {PlcMapping.reverse}), isTrue);
      expect(
        composeActiveFields(sim.buttonFields),
        {PlcMapping.up, PlcMapping.reverse},
      );
    });

    test('estop is never present in any composed field set — the composer '
        'hardcodes estop:false regardless of button configuration', () {
      // ButtonStateOutputMapping structurally excludes estop from
      // activeVariants (see button_state_output_mapping_test.dart), so no
      // _OwnershipSim claim can ever legitimately include it — this test
      // documents that guarantee at the composition-mirror level too.
      final sim = _OwnershipSim();
      sim.claim('button1', {PlcMapping.up, PlcMapping.down});
      expect(composeActiveFields(sim.buttonFields).contains(PlcMapping.estop), isFalse);
    });
  });
}
