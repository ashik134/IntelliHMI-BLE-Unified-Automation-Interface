import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/buttons/button/multi_step_slider_button.dart';

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

  testWidgets('track taps and track-origin drags are ignored', (tester) async {
    final emitted = <String>[];
    await tester.pumpWidget(_Harness(onState: emitted.add));

    final trackPoint = _trackPointAwayFromThumb(tester);

    await tester.tapAt(trackPoint);
    await tester.pump();
    expect(emitted, isEmpty);
    expect(vibrationCalls, isEmpty);

    final trackGesture = await tester.startGesture(trackPoint);
    await trackGesture.moveBy(Offset(0, _towardStep2Y(tester) * 60));
    await tester.pump();
    await trackGesture.up();
    await tester.pumpAndSettle();

    expect(emitted, isEmpty);
    expect(vibrationCalls, isEmpty);
  });

  testWidgets(
    'thumb drag moves smoothly while emitting once per state transition',
    (tester) async {
      final emitted = <String>[];
      await tester.pumpWidget(_Harness(onState: emitted.add));

      final directionY = _towardStep2Y(tester);
      final thumbCenter = tester.getCenter(_thumbFinder);
      final gesture = await tester.startGesture(thumbCenter);

      await gesture.moveBy(Offset(0, directionY * 24));
      await tester.pump();
      expect(emitted, [MultiStepSliderStateId.step1]);
      expect(vibrationCalls, hasLength(1));

      await gesture.moveBy(Offset(0, directionY * 10));
      await tester.pump();
      expect(emitted, [MultiStepSliderStateId.step1]);
      expect(vibrationCalls, hasLength(1));

      await gesture.moveBy(Offset(0, directionY * 50));
      await tester.pump();
      expect(emitted.last, MultiStepSliderStateId.step2);
      expect(vibrationCalls, hasLength(2));

      await gesture.moveBy(Offset(0, -directionY * 35));
      await tester.pump();
      expect(emitted.last, MultiStepSliderStateId.step1);
      expect(vibrationCalls, hasLength(3));

      await gesture.moveBy(Offset(0, -directionY * 60));
      await tester.pump();
      expect(emitted.last, MultiStepSliderStateId.idle);
      expect(vibrationCalls, hasLength(4));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(emitted, [
        MultiStepSliderStateId.step1,
        MultiStepSliderStateId.step2,
        MultiStepSliderStateId.step1,
        MultiStepSliderStateId.idle,
      ]);
      expect(emitted.every(MultiStepSliderStateId.values.contains), isTrue);
    },
  );
}

final _thumbFinder = find.byKey(const ValueKey('multi_step_slider_thumb'));

double _towardStep2Y(WidgetTester tester) {
  final sliderCenter = tester.getCenter(find.byType(MultiStepSliderButton));
  final thumbCenter = tester.getCenter(_thumbFinder);
  return thumbCenter.dy < sliderCenter.dy ? 1.0 : -1.0;
}

Offset _trackPointAwayFromThumb(WidgetTester tester) {
  final thumbCenter = tester.getCenter(_thumbFinder);
  return thumbCenter + Offset(0, _towardStep2Y(tester) * 72);
}

class _Harness extends StatelessWidget {
  const _Harness({required this.onState});

  final ValueChanged<String> onState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 140,
            height: 180,
            child: MultiStepSliderButton(
              label: 'STEP',
              icon: Icons.tune,
              onStateChanged: onState,
            ),
          ),
        ),
      ),
    );
  }
}
