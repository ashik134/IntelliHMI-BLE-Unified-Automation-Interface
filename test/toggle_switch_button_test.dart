import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/models/app_enums.dart';
import 'package:rev_crane_control_ops/widgets/buttons/button/toggle_switch_button.dart';

const _knobKey = ValueKey('toggle_lever_knob');
const _interactionKey = ValueKey('toggle_lever_interaction_area');

Widget _harness({
  double? width,
  double? height,
  ToggleSwitchMode mode = ToggleSwitchMode.latchingBoth,
  ToggleSwitchPosition position = ToggleSwitchPosition.center,
  Key? controlKey,
  required ValueChanged<ToggleSwitchPosition> onPositionChanged,
  required ValueChanged<ControlState> onCommandChanged,
  VoidCallback? onReleased,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width ?? ToggleSwitchButton.minimumOperationalSize.width,
          height: height ?? ToggleSwitchButton.minimumOperationalSize.height,
          child: ToggleSwitchButton(
            key: controlKey,
            label: 'Direction',
            icon: Icons.swap_vert,
            activeColor: Colors.blue,
            activeColorLight: Colors.lightBlueAccent,
            isActive: position != ToggleSwitchPosition.center,
            isDisabled: false,
            isSpringReturn: false,
            mode: mode,
            position: position,
            onPositionChanged: onPositionChanged,
            onCommandChanged: onCommandChanged,
            onReleased: onReleased,
          ),
        ),
      ),
    ),
  );
}

Future<TestGesture> _startOnKnob(WidgetTester tester) async {
  await tester.pumpAndSettle();
  return tester.startGesture(tester.getCenter(find.byKey(_knobKey)));
}

Future<void> _dragFromKnob(WidgetTester tester, Offset delta) async {
  final gesture = await _startOnKnob(tester);
  await gesture.moveBy(delta);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  late List<MethodCall> platformCalls;

  setUp(() {
    platformCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          platformCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
    'minimum operational size separates adjacent detents by at least 48px',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];

      await tester.pumpWidget(
        _harness(
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      expect(ToggleSwitchButton.minimumOperationalSize, const Size(112, 220));
      expect(find.byIcon(Icons.swap_vert), findsOneWidget);
      expect(find.text('Direction'), findsOneWidget);

      final interactionSize = tester.getSize(find.byKey(_interactionKey));
      expect(interactionSize, const Size(112, 190));
      final centerDetent = tester.getCenter(find.byKey(_knobKey));

      await _dragFromKnob(tester, const Offset(0, 60));
      final endDetent = tester.getCenter(find.byKey(_knobKey));

      expect(endDetent.dy - centerDetent.dy, greaterThanOrEqualTo(48));
      expect(positions, const [ToggleSwitchPosition.right]);
      expect(commands, const [ControlState.level2]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a dead-zone tap and a short on-knob drag cannot change state', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);

    // Dead-zone tap (middle third) — never a valid end zone.
    await tester.tapAt(topLeft + Offset(size.width / 2, size.height / 2));
    await tester.pumpAndSettle();
    // A tap on the knob itself while it rests at centre — no movement, no
    // zone crossed.
    await tester.tapAt(tester.getCenter(find.byKey(_knobKey)));
    await tester.pumpAndSettle();

    final shortDrag = await _startOnKnob(tester);
    await shortDrag.moveBy(const Offset(0, 12));
    await tester.pump();
    await shortDrag.up();
    await tester.pumpAndSettle();

    expect(positions, isEmpty);
    expect(commands, isEmpty);
    expect(
      platformCalls.where((call) => call.method == 'HapticFeedback.vibrate'),
      isEmpty,
    );
  });

  testWidgets('a direct tap on a valid end zone moves the knob and activates '
      'it without touching the knob first', (tester) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);

    await tester.tapAt(topLeft + Offset(size.width / 2, 8));
    await tester.pumpAndSettle();

    expect(positions, const [ToggleSwitchPosition.left]);
    expect(commands, const [ControlState.level1]);
    expect(
      platformCalls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .length,
      1,
    );

    // A fresh widget (still resting at centre) proves the bottom zone works
    // the same way — the top-zone tap above already left the lever at
    // `left`, and tapping the opposite end from there must step through
    // centre rather than jump straight across (covered separately below).
    await tester.pumpWidget(
      _harness(
        controlKey: UniqueKey(),
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );
    final freshTopLeft = tester.getTopLeft(interaction);
    final freshSize = tester.getSize(interaction);
    await tester.tapAt(
      freshTopLeft + Offset(freshSize.width / 2, freshSize.height - 8),
    );
    await tester.pumpAndSettle();

    expect(positions, const [
      ToggleSwitchPosition.left,
      ToggleSwitchPosition.right,
    ]);
    expect(commands, const [ControlState.level1, ControlState.level2]);
  });

  testWidgets('tapping an already-latched end zone again releases it', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        position: ToggleSwitchPosition.right,
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);

    await tester.tapAt(topLeft + Offset(size.width / 2, size.height - 8));
    await tester.pumpAndSettle();

    expect(positions, const [ToggleSwitchPosition.center]);
    expect(commands, const [ControlState.idle]);
  });

  testWidgets(
    'tapping the opposite end zone steps to centre instead of jumping '
    'directly across',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          position: ToggleSwitchPosition.left,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final interaction = find.byKey(_interactionKey);
      final topLeft = tester.getTopLeft(interaction);
      final size = tester.getSize(interaction);

      await tester.tapAt(topLeft + Offset(size.width / 2, size.height - 8));
      await tester.pumpAndSettle();

      expect(positions, const [ToggleSwitchPosition.center]);
      expect(commands, const [ControlState.idle]);
    },
  );

  testWidgets('a drag starting on the track cannot move the selector', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    await tester.pumpWidget(
      _harness(onPositionChanged: positions.add, onCommandChanged: (_) {}),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);
    final gesture = await tester.startGesture(
      topLeft + Offset(size.width / 2, 8),
    );
    await gesture.moveBy(Offset(0, size.height - 16));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, isEmpty);
  });

  testWidgets(
    'an off-knob press that turns into a drag never commits a latch, even '
    'if it ends back inside a valid zone',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      await tester.pumpWidget(
        _harness(onPositionChanged: positions.add, onCommandChanged: (_) {}),
      );

      final interaction = find.byKey(_interactionKey);
      final topLeft = tester.getTopLeft(interaction);
      final size = tester.getSize(interaction);

      final gesture = await tester.startGesture(
        topLeft + Offset(size.width / 2, size.height - 8),
      );
      // Swings far enough to disqualify the tap...
      await gesture.moveBy(Offset(0, -(size.height - 20)));
      await tester.pump();
      // ...then drifts back into the same end zone before release.
      await gesture.moveBy(Offset(0, size.height - 30));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(positions, isEmpty);
    },
  );

  testWidgets(
    'a momentary spring end activates immediately on an off-knob press and '
    'releases when lifted',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      var releases = 0;
      await tester.pumpWidget(
        _harness(
          mode: ToggleSwitchMode.springReturnBoth,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
          onReleased: () => releases += 1,
        ),
      );

      final interaction = find.byKey(_interactionKey);
      final topLeft = tester.getTopLeft(interaction);
      final size = tester.getSize(interaction);

      final gesture = await tester.startGesture(
        topLeft + Offset(size.width / 2, size.height - 8),
      );
      await tester.pump();

      // Active the instant the press lands — no need to wait for release.
      expect(positions, const [ToggleSwitchPosition.right]);
      expect(commands, const [ControlState.level2]);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(positions, const [
        ToggleSwitchPosition.right,
        ToggleSwitchPosition.center,
      ]);
      expect(commands, const [ControlState.level2, ControlState.idle]);
      expect(releases, 1);
    },
  );

  testWidgets(
    'a momentary spring end held off-knob cancels early if the pointer '
    'leaves its zone',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      var releases = 0;
      await tester.pumpWidget(
        _harness(
          mode: ToggleSwitchMode.springReturnBoth,
          onPositionChanged: positions.add,
          onCommandChanged: (_) {},
          onReleased: () => releases += 1,
        ),
      );

      final interaction = find.byKey(_interactionKey);
      final topLeft = tester.getTopLeft(interaction);
      final size = tester.getSize(interaction);

      final gesture = await tester.startGesture(
        topLeft + Offset(size.width / 2, size.height - 8),
      );
      await tester.pump();
      expect(positions, const [ToggleSwitchPosition.right]);

      await gesture.moveBy(Offset(0, -(size.height / 2)));
      await tester.pump();

      expect(positions, const [
        ToggleSwitchPosition.right,
        ToggleSwitchPosition.center,
      ]);
      expect(releases, 1);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(positions, const [
        ToggleSwitchPosition.right,
        ToggleSwitchPosition.center,
      ]);
    },
  );

  testWidgets(
    'pressing a spring end off-knob while the opposite side is latched only '
    'releases the latch, then a fresh press activates the spring end',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          mode: ToggleSwitchMode.mixed,
          position: ToggleSwitchPosition.left,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final interaction = find.byKey(_interactionKey);
      final topLeft = tester.getTopLeft(interaction);
      final size = tester.getSize(interaction);
      final bottomZone = topLeft + Offset(size.width / 2, size.height - 8);

      final firstPress = await tester.startGesture(bottomZone);
      await tester.pump();
      expect(positions, const [ToggleSwitchPosition.center]);
      expect(commands, const [ControlState.idle]);
      await firstPress.up();
      await tester.pumpAndSettle();

      final secondPress = await tester.startGesture(bottomZone);
      await tester.pump();
      expect(positions, const [
        ToggleSwitchPosition.center,
        ToggleSwitchPosition.right,
      ]);
      expect(commands, const [ControlState.idle, ControlState.level2]);
      await secondPress.up();
      await tester.pumpAndSettle();
    },
  );

  for (final mode in [
    ToggleSwitchMode.springReturnBoth,
    ToggleSwitchMode.latchingBoth,
    ToggleSwitchMode.mixed,
  ]) {
    testWidgets('${mode.name} blocks a direct state 1 to state 2 move', (
      tester,
    ) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          mode: mode,
          position: ToggleSwitchPosition.left,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final gesture = await _startOnKnob(tester);
      await gesture.moveBy(const Offset(0, 130));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(positions, const [ToggleSwitchPosition.center]);
      expect(commands, const [ControlState.idle]);
    });

    testWidgets('${mode.name} blocks a direct state 2 to state 1 move', (
      tester,
    ) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          mode: mode,
          position: ToggleSwitchPosition.right,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final gesture = await _startOnKnob(tester);
      await gesture.moveBy(const Offset(0, -130));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -2));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(positions, const [ToggleSwitchPosition.center]);
      expect(commands, const [ControlState.idle]);
    });
  }

  testWidgets('opposite latch requires an observed neutral dwell', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        position: ToggleSwitchPosition.left,
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final gesture = await _startOnKnob(tester);
    await gesture.moveBy(const Offset(0, 50), timeStamp: Duration.zero);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(
      const Offset(0, 1),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, 45),
      timeStamp: const Duration(milliseconds: 110),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, const [
      ToggleSwitchPosition.center,
      ToggleSwitchPosition.right,
    ]);
    expect(commands, const [ControlState.idle, ControlState.level2]);
  });

  testWidgets('reverse latch also requires an observed neutral dwell', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        position: ToggleSwitchPosition.right,
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final gesture = await _startOnKnob(tester);
    await gesture.moveBy(const Offset(0, -50), timeStamp: Duration.zero);
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(
      const Offset(0, -1),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    await gesture.moveBy(
      const Offset(0, -45),
      timeStamp: const Duration(milliseconds: 110),
    );
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, const [
      ToggleSwitchPosition.center,
      ToggleSwitchPosition.left,
    ]);
    expect(commands, const [ControlState.idle, ControlState.level1]);
  });

  testWidgets('hysteresis holds an end detent until its exit boundary', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final gesture = await _startOnKnob(tester);
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -15));
    await tester.pump();
    expect(positions, const [ToggleSwitchPosition.right]);

    await gesture.moveBy(const Offset(0, -10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, const [
      ToggleSwitchPosition.right,
      ToggleSwitchPosition.center,
    ]);
    expect(commands, const [ControlState.level2, ControlState.idle]);
    expect(
      platformCalls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .length,
      2,
    );
  });

  testWidgets('R-O-R returns either spring detent to neutral on release', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    var releases = 0;
    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.springReturnBoth,
        controlKey: UniqueKey(),
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
        onReleased: () => releases += 1,
      ),
    );

    await _dragFromKnob(tester, const Offset(0, -60));

    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.springReturnBoth,
        controlKey: UniqueKey(),
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
        onReleased: () => releases += 1,
      ),
    );
    await _dragFromKnob(tester, const Offset(0, 60));

    expect(positions, const [
      ToggleSwitchPosition.left,
      ToggleSwitchPosition.center,
      ToggleSwitchPosition.right,
      ToggleSwitchPosition.center,
    ]);
    expect(commands, const [
      ControlState.level1,
      ControlState.idle,
      ControlState.level2,
      ControlState.idle,
    ]);
    expect(releases, 2);
  });

  testWidgets('T-O-R latches the top and spring-returns the bottom', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];

    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.mixed,
        controlKey: UniqueKey(),
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );
    await _dragFromKnob(tester, const Offset(0, -60));
    expect(positions, const [ToggleSwitchPosition.left]);
    expect(commands, const [ControlState.level1]);

    positions.clear();
    commands.clear();
    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.mixed,
        controlKey: UniqueKey(),
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );
    await _dragFromKnob(tester, const Offset(0, 60));
    expect(positions, const [
      ToggleSwitchPosition.right,
      ToggleSwitchPosition.center,
    ]);
    expect(commands, const [ControlState.level2, ControlState.idle]);
  });

  testWidgets('smaller grid cell uses compact lever layout without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        width: 72,
        height: 72,
        onPositionChanged: (_) {},
        onCommandChanged: (_) {},
      ),
    );

    expect(tester.getSize(find.byKey(_interactionKey)), const Size(72, 72));
    expect(find.text('Direction'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'O-T: an on-knob drag short of full travel does not activate the spring '
    'end, but reaching it does — and release springs back to idle',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          mode: ToggleSwitchMode.springReturnOneSide,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final gesture = await _startOnKnob(tester);
      // Comfortably past the old fixed 18px drag threshold, but nowhere near
      // the end detent — must not activate on its own.
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(positions, isEmpty);
      expect(commands, isEmpty);

      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();
      expect(positions, const [ToggleSwitchPosition.right]);
      expect(commands, const [ControlState.level1]);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(positions, const [
        ToggleSwitchPosition.right,
        ToggleSwitchPosition.center,
      ]);
      expect(commands, const [ControlState.level1, ControlState.idle]);
    },
  );

  testWidgets(
    'O-R: an on-knob drag that reaches the end latches and stays latched '
    'after release',
    (tester) async {
      final positions = <ToggleSwitchPosition>[];
      final commands = <ControlState>[];
      await tester.pumpWidget(
        _harness(
          mode: ToggleSwitchMode.latchingOneSide,
          onPositionChanged: positions.add,
          onCommandChanged: commands.add,
        ),
      );

      final gesture = await _startOnKnob(tester);
      await gesture.moveBy(const Offset(0, 90));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(positions, const [ToggleSwitchPosition.right]);
      expect(commands, const [ControlState.level1]);
    },
  );

  testWidgets('O-R: dragging must start on the knob, not the track', (
    tester,
  ) async {
    final positions = <ToggleSwitchPosition>[];
    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.latchingOneSide,
        onPositionChanged: positions.add,
        onCommandChanged: (_) {},
      ),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);

    // The idle knob sits at the top; pressing the dead-centre track (well
    // away from it) and dragging all the way down must have no effect.
    final gesture = await tester.startGesture(
      topLeft + Offset(size.width / 2, size.height / 2),
    );
    await gesture.moveBy(Offset(0, size.height / 2 - 10));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(positions, isEmpty);
  });

  testWidgets('O-R: a direct tap on the R zone latches it, tapping again '
      'releases it', (tester) async {
    final positions = <ToggleSwitchPosition>[];
    final commands = <ControlState>[];
    await tester.pumpWidget(
      _harness(
        mode: ToggleSwitchMode.latchingOneSide,
        onPositionChanged: positions.add,
        onCommandChanged: commands.add,
      ),
    );

    final interaction = find.byKey(_interactionKey);
    final topLeft = tester.getTopLeft(interaction);
    final size = tester.getSize(interaction);
    final bottomZone = topLeft + Offset(size.width / 2, size.height - 8);

    await tester.tapAt(bottomZone);
    await tester.pumpAndSettle();
    expect(positions, const [ToggleSwitchPosition.right]);
    expect(commands, const [ControlState.level1]);
    expect(
      platformCalls
          .where((call) => call.method == 'HapticFeedback.vibrate')
          .length,
      1,
    );

    await tester.tapAt(bottomZone);
    await tester.pumpAndSettle();
    expect(positions, const [
      ToggleSwitchPosition.right,
      ToggleSwitchPosition.center,
    ]);
    expect(commands, const [ControlState.level1, ControlState.idle]);
  });
}
