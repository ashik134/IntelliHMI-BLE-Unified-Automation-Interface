// Widget-level regression guard for the generic MultiZoneSliderButton:
//   - it emits ONLY generic zone ids (never left/right/slow/fast wording)
//   - the top zone-label row is gone; bottom labels/icons come from the
//     caller's configuration, not hardcoded crane wording
//   - safety behavior is preserved: center/idle on release, reset to
//     center when disabled, no stale active state after release
//   - per-side zone blocking clamps the drag before it reaches the blocked
//     zone, exactly like the legacy CrossTravelSlider did

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';

void main() {
  const vibrationChannel = MethodChannel('vibration');
  late List<MethodCall> vibrationCalls;

  setUp(() {
    vibrationCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vibrationChannel, (call) async {
          vibrationCalls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vibrationChannel, null);
  });

  // Geometry for a 300x120 box (horizontal orientation — see _Harness):
  // thumbH = 120.clamp(60,200)*0.42 = 50.4; thumbW = (50.4*0.68).clamp(22,36)
  // ≈ 34.27; halfTrack = (300 - 34.27) / 2 ≈ 132.86.
  const halfTrack = 132.86;
  double dxFor(double fraction) => fraction * halfTrack;

  testWidgets('track taps and track-origin drags are ignored', (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(_Harness(onZone: emitted.add));

    final thumbCenter = tester.getCenter(_thumbFinder);
    final trackPoint = thumbCenter + Offset(dxFor(0.75), 0);

    await tester.tapAt(trackPoint);
    await tester.pump();
    expect(emitted, isEmpty);
    expect(vibrationCalls, isEmpty);

    final trackGesture = await tester.startGesture(trackPoint);
    await trackGesture.moveBy(Offset(-dxFor(0.5), 0));
    await tester.pump();
    await trackGesture.up();
    await tester.pumpAndSettle();

    expect(emitted, isEmpty);
    expect(vibrationCalls, isEmpty);
  });

  testWidgets('five-zone: drag reports zone1/zone2/zone4/zone5 by position, '
      'never left/right/slow/fast', (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(_Harness(onZone: emitted.add));

    final center = tester.getCenter(find.byType(MultiZoneSliderButton));

    final near = await tester.startGesture(center);
    await near.moveBy(Offset(-dxFor(0.35), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone2);
    await near.up();
    await tester.pumpAndSettle();
    expect(emitted.last, MultiZoneSliderStateId.center);

    emitted.clear();
    final far = await tester.startGesture(center);
    await far.moveBy(Offset(-dxFor(0.9), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone1);
    await far.up();
    await tester.pumpAndSettle();
    expect(emitted.last, MultiZoneSliderStateId.center);

    emitted.clear();
    final nearPos = await tester.startGesture(center);
    await nearPos.moveBy(Offset(dxFor(0.35), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone4);
    await nearPos.up();
    await tester.pumpAndSettle();

    emitted.clear();
    final farPos = await tester.startGesture(center);
    await farPos.moveBy(Offset(dxFor(0.9), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone5);
    await farPos.up();
    await tester.pumpAndSettle();

    expect(emitted.every(MultiZoneSliderStateId.fiveZoneValues.contains), isTrue);
  });

  testWidgets('three-zone: any negative drag reports zone1, any positive '
      'drag reports zone3 — no near/far split', (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(
      _Harness(onZone: emitted.add, variant: MultiZoneSliderVariant.threeZone),
    );

    final center = tester.getCenter(find.byType(MultiZoneSliderButton));

    final left = await tester.startGesture(center);
    await left.moveBy(Offset(-dxFor(0.5), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone1);
    await left.up();
    await tester.pumpAndSettle();

    emitted.clear();
    final right = await tester.startGesture(center);
    await right.moveBy(Offset(dxFor(0.5), 0));
    await tester.pump();
    expect(emitted.last, MultiZoneSliderStateId.zone3);
    await right.up();
    await tester.pumpAndSettle();

    expect(
      emitted.every(MultiZoneSliderStateId.threeZoneValues.contains),
      isTrue,
    );
  });

  testWidgets(
    'releasing always emits center as the final zone (never stale active)',
    (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(_Harness(onZone: emitted.add));

      final center = tester.getCenter(find.byType(MultiZoneSliderButton));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(Offset(-dxFor(0.9), 0));
      await tester.pump();
      expect(emitted.last, isNot(MultiZoneSliderStateId.center));

      await gesture.up();
      await tester.pump();
      expect(emitted.last, MultiZoneSliderStateId.center);
    },
  );

  testWidgets(
    'becoming disabled mid-drag resets to center immediately',
    (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(_Harness(onZone: emitted.add));

      final center = tester.getCenter(find.byType(MultiZoneSliderButton));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(Offset(-dxFor(0.9), 0));
      await tester.pump();
      expect(emitted.last, MultiZoneSliderStateId.zone1);

      await tester.pumpWidget(_Harness(onZone: emitted.add, isDisabled: true));
      expect(emitted.last, MultiZoneSliderStateId.center);
      expect(tester.takeException(), isNull);

      await gesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a blocked start zone clamps the drag before reaching zone1/zone2',
    (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        _Harness(onZone: emitted.add, isStartZoneBlocked: true),
      );

      final center = tester.getCenter(find.byType(MultiZoneSliderButton));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(Offset(-dxFor(0.9), 0));
      await tester.pump();
      expect(emitted, isEmpty, reason: 'blocked side must never emit a zone');

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'a blocked end zone clamps the drag before reaching zone4/zone5',
    (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(
        _Harness(onZone: emitted.add, isEndZoneBlocked: true),
      );

      final center = tester.getCenter(find.byType(MultiZoneSliderButton));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(Offset(dxFor(0.9), 0));
      await tester.pump();
      expect(emitted, isEmpty, reason: 'blocked side must never emit a zone');

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'the top zone-label row is gone; bottom labels come from configuration',
    (tester) async {
      await tester.pumpWidget(_Harness(onZone: (_) {}));

      // Legacy top-row wording must never appear.
      expect(find.text('ZONE 2'), findsNothing);
      expect(find.text('ZONE 4'), findsNothing);
      expect(find.text('SLOW'), findsNothing);
      expect(find.text('FAST'), findsNothing);
      expect(find.text('ACTIVE'), findsNothing);

      // Caller-supplied bottom labels are shown as configured.
      expect(find.text('NEG'), findsOneWidget);
      expect(find.text('POS'), findsOneWidget);
    },
  );
}

final _thumbFinder = find.byKey(const ValueKey('multi_zone_slider_thumb'));

class _Harness extends StatelessWidget {
  const _Harness({
    required this.onZone,
    this.isDisabled = false,
    this.variant = MultiZoneSliderVariant.fiveZone,
    this.isStartZoneBlocked = false,
    this.isEndZoneBlocked = false,
  });

  final ValueChanged<String> onZone;
  final bool isDisabled;
  final MultiZoneSliderVariant variant;
  final bool isStartZoneBlocked;
  final bool isEndZoneBlocked;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 120,
            child: MultiZoneSliderButton(
              startLabel: 'NEG',
              endLabel: 'POS',
              startIcon: Icons.remove,
              endIcon: Icons.add,
              isDisabled: isDisabled,
              variant: variant,
              isStartZoneBlocked: isStartZoneBlocked,
              isEndZoneBlocked: isEndZoneBlocked,
              onStateChanged: onZone,
            ),
          ),
        ),
      ),
    );
  }
}
