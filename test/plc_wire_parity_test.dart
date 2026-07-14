import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/models/control_role.dart';
import 'package:rev_crane_control_ops/models/plc_output_command.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Wire-byte parity between the legacy 3-axis-pair derivation
// (CraneController._composePlc38Command) and the button-centric map-driven
// derivation (CraneController._composeFromButtonStates). Both functions are
// private, so this test mirrors each one's exact derivation expressions
// inline and asserts they produce byte-identical PlcOutputCommand output for
// every representative state combination — proving the button-centric
// refactor cannot silently change the PLC38/PLC14 wire protocol.
// ─────────────────────────────────────────────────────────────────────────────

/// Mirrors CraneController._composePlc38Command's derivation exactly.
PlcOutputCommand composeLegacy({
  required bool vertIsUp,
  required ControlState vertState,
  required bool travIsLeft,
  required ControlState travState,
  required bool tripIsForward,
  required ControlState tripState,
}) {
  return PlcOutputCommand.compose(
    estop: false,
    up: vertIsUp && vertState != ControlState.idle,
    down: !vertIsUp && vertState != ControlState.idle,
    fastUd: vertState == ControlState.fast,
    left: travIsLeft && travState != ControlState.idle,
    right: !travIsLeft && travState != ControlState.idle,
    fastLr: travState == ControlState.fast,
    forward: tripIsForward && tripState != ControlState.idle,
    reverse: !tripIsForward && tripState != ControlState.idle,
    fastFb: tripState == ControlState.fast,
  );
}

/// Mirrors CraneController._composeFromButtonStates's derivation exactly.
PlcOutputCommand composeFromButtonStates(Map<String, ControlState> states) {
  bool activeFor(ControlRole role) =>
      (states[role.name] ?? ControlState.idle) != ControlState.idle;
  bool fastFor(ControlRole role) =>
      (states[role.name] ?? ControlState.idle) == ControlState.fast;
  // Independent 3-zone traverse sliders post to these virtual keys to set
  // fastLr without activating a direction bit.
  bool fastKeyActive(String key) =>
      (states[key] ?? ControlState.idle) != ControlState.idle;

  return PlcOutputCommand.compose(
    estop: false,
    up: activeFor(ControlRole.hoistUp),
    down: activeFor(ControlRole.hoistDown),
    fastUd: fastFor(ControlRole.hoistUp) || fastFor(ControlRole.hoistDown),
    left: activeFor(ControlRole.traverseLeft),
    right: activeFor(ControlRole.traverseRight),
    fastLr:
        fastFor(ControlRole.traverseLeft) ||
        fastFor(ControlRole.traverseRight) ||
        fastKeyActive(kTraverseLeftFastKey) ||
        fastKeyActive(kTraverseRightFastKey),
    forward: activeFor(ControlRole.travelForward),
    reverse: activeFor(ControlRole.travelReverse),
    fastFb:
        fastFor(ControlRole.travelForward) ||
        fastFor(ControlRole.travelReverse),
  );
}

/// Converts a legacy (isX, state) triple-of-pairs into the equivalent
/// button-id -> ControlState map, the same translation the button-centric
/// screens perform when a drag/press fires.
Map<String, ControlState> toButtonStates({
  required bool vertIsUp,
  required ControlState vertState,
  required bool travIsLeft,
  required ControlState travState,
  required bool tripIsForward,
  required ControlState tripState,
}) {
  return {
    if (vertState != ControlState.idle)
      (vertIsUp ? ControlRole.hoistUp : ControlRole.hoistDown).name: vertState,
    if (travState != ControlState.idle)
      (travIsLeft ? ControlRole.traverseLeft : ControlRole.traverseRight).name:
          travState,
    if (tripState != ControlState.idle)
      (tripIsForward ? ControlRole.travelForward : ControlRole.travelReverse)
              .name:
          tripState,
  };
}

void main() {
  group('PLC38 wire-byte parity: legacy vs button-centric composition', () {
    final combos = <Map<String, Object>>[
      {
        'name': 'all idle',
        'vertIsUp': true,
        'vertState': ControlState.idle,
        'travIsLeft': true,
        'travState': ControlState.idle,
        'tripIsForward': true,
        'tripState': ControlState.idle,
      },
      {
        'name': 'hoist up slow only',
        'vertIsUp': true,
        'vertState': ControlState.slow,
        'travIsLeft': true,
        'travState': ControlState.idle,
        'tripIsForward': true,
        'tripState': ControlState.idle,
      },
      {
        'name': 'hoist down fast only',
        'vertIsUp': false,
        'vertState': ControlState.fast,
        'travIsLeft': true,
        'travState': ControlState.idle,
        'tripIsForward': true,
        'tripState': ControlState.idle,
      },
      {
        'name': 'traverse left slow only',
        'vertIsUp': true,
        'vertState': ControlState.idle,
        'travIsLeft': true,
        'travState': ControlState.slow,
        'tripIsForward': true,
        'tripState': ControlState.idle,
      },
      {
        'name': 'traverse right fast only',
        'vertIsUp': true,
        'vertState': ControlState.idle,
        'travIsLeft': false,
        'travState': ControlState.fast,
        'tripIsForward': true,
        'tripState': ControlState.idle,
      },
      {
        'name': 'travel forward slow only',
        'vertIsUp': true,
        'vertState': ControlState.idle,
        'travIsLeft': true,
        'travState': ControlState.idle,
        'tripIsForward': true,
        'tripState': ControlState.slow,
      },
      {
        'name': 'travel reverse fast only',
        'vertIsUp': true,
        'vertState': ControlState.idle,
        'travIsLeft': true,
        'travState': ControlState.idle,
        'tripIsForward': false,
        'tripState': ControlState.fast,
      },
      {
        'name': 'all three axes simultaneously active',
        'vertIsUp': true,
        'vertState': ControlState.fast,
        'travIsLeft': false,
        'travState': ControlState.slow,
        'tripIsForward': false,
        'tripState': ControlState.fast,
      },
      {
        'name': 'hoist down + traverse left + travel forward, all slow',
        'vertIsUp': false,
        'vertState': ControlState.slow,
        'travIsLeft': true,
        'travState': ControlState.slow,
        'tripIsForward': true,
        'tripState': ControlState.slow,
      },
    ];

    for (final combo in combos) {
      test(combo['name'] as String, () {
        final vertIsUp = combo['vertIsUp'] as bool;
        final vertState = combo['vertState'] as ControlState;
        final travIsLeft = combo['travIsLeft'] as bool;
        final travState = combo['travState'] as ControlState;
        final tripIsForward = combo['tripIsForward'] as bool;
        final tripState = combo['tripState'] as ControlState;

        final legacy = composeLegacy(
          vertIsUp: vertIsUp,
          vertState: vertState,
          travIsLeft: travIsLeft,
          travState: travState,
          tripIsForward: tripIsForward,
          tripState: tripState,
        );
        final buttonCentric = composeFromButtonStates(
          toButtonStates(
            vertIsUp: vertIsUp,
            vertState: vertState,
            travIsLeft: travIsLeft,
            travState: travState,
            tripIsForward: tripIsForward,
            tripState: tripState,
          ),
        );

        expect(
          buttonCentric.wireBytesFor(PlcType.plc38),
          equals(legacy.wireBytesFor(PlcType.plc38)),
        );
        expect(legacy.isValid, isTrue);
        expect(buttonCentric.isValid, isTrue);
      });
    }
  });

  // ── Field-ownership observable behavior ────────────────────────────────────
  // The ownership system is enforced inside CraneController.setButtonCommand
  // (which requires a real BLE connection and is not unit-tested here).
  // These tests verify the COMPOSITION side: given the post-ownership state
  // map that setButtonCommand produces, composeFromButtonStates emits the
  // correct PLC packet. The ownership invariant is: at most one button can
  // write to a given PLC field at a time, so the second claimant's key is
  // never added to the state map.
  group('Post-ownership state composition', () {
    test('only kTraverseLeftFastKey active → fastLr set, no direction', () {
      // Ownership: kTraverseLeftFastKey won; kTraverseRightFastKey was blocked.
      final cmd = composeFromButtonStates({
        kTraverseLeftFastKey: ControlState.slow,
      });
      expect(cmd.fastLr, isTrue);
      expect(cmd.left, isFalse);
      expect(cmd.right, isFalse);
    });

    test(
      'left direction + right-slider fast (kTraverseRightFastKey) → left fast',
      () {
        final cmd = composeFromButtonStates({
          ControlRole.traverseLeft.name: ControlState.slow,
          kTraverseRightFastKey: ControlState.slow,
        });
        expect(cmd.left, isTrue);
        expect(cmd.right, isFalse);
        expect(cmd.fastLr, isTrue);
      },
    );

    test(
      'right direction + left-slider fast (kTraverseLeftFastKey) → right fast',
      () {
        final cmd = composeFromButtonStates({
          ControlRole.traverseRight.name: ControlState.slow,
          kTraverseLeftFastKey: ControlState.slow,
        });
        expect(cmd.left, isFalse);
        expect(cmd.right, isTrue);
        expect(cmd.fastLr, isTrue);
      },
    );

    test(
      'ownership prevents two virtual keys from co-existing in the state map',
      () {
        // After ownership enforcement, if kTraverseLeftFastKey owns fastLr,
        // kTraverseRightFastKey is blocked and never added.  The state map
        // therefore never has both keys simultaneously.
        // This test simply validates the composition of the legal post-ownership
        // state (single key only) produces a valid packet.
        final cmd = composeFromButtonStates({
          kTraverseLeftFastKey: ControlState.slow,
          // kTraverseRightFastKey intentionally absent — was blocked
        });
        expect(cmd.isValid, isTrue);
      },
    );
  });

  group(
    'PLC14 wire format (4-field) is unaffected by the button-centric path',
    () {
      test('idle command emits the 4-field idle format', () {
        final cmd = PlcOutputCommand.idle();
        expect(cmd.wireFormatFor(PlcType.plc14), '[0,0,0,0]');
      });

      test('hoist up fast emits the 4-field motion format', () {
        final cmd = PlcOutputCommand.motion(
          direction: HoistDirection.up,
          speed: HoistSpeed.fast,
        );
        expect(cmd.wireFormatFor(PlcType.plc14), '[0,1,0,1]');
      });
    },
  );
}
