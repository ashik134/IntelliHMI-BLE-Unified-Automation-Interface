import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/buttons/button/multi_step_slider_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vibrationChannel = MethodChannel('vibration');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vibrationChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vibrationChannel, null);
  });

  testWidgets('defers a disabled-slider release until after build', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_SliderHarnessState>();
    await tester.pumpWidget(_SliderHarness(key: harnessKey));

    final gesture = await _dragToStep1(tester);
    expect(harnessKey.currentState!.states.last, MultiStepSliderStateId.step1);

    harnessKey.currentState!.disable();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.states.last, MultiStepSliderStateId.idle);

    await gesture.up();
    await tester.pump();
  });

  testWidgets(
    'E-STOP mid-drag clears the caller bookkeeping instead of leaving it '
    'stuck on the interrupted step, so re-enabling never restores it',
    (tester) async {
      final harnessKey = GlobalKey<_SliderHarnessState>();
      await tester.pumpWidget(_SliderHarness(key: harnessKey));

      final gesture = await _dragToStep1(tester);
      expect(harnessKey.currentState!.states.last, MultiStepSliderStateId.step1);
      expect(harnessKey.currentState!.externalStateId, MultiStepSliderStateId.step1);

      // E-STOP fires mid-drag: controls become disabled.
      harnessKey.currentState!.disable();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // The caller's own bookkeeping (mirrors plc38/plc14 screens'
      // _localActive map) must have been told to release step1, not just
      // the widget's own local visuals.
      expect(harnessKey.currentState!.externalStateId, MultiStepSliderStateId.idle);

      // Finger physically lifts off the (now-disabled) slider.
      await gesture.up();
      await tester.pump();

      // E-STOP resets. No new user gesture has occurred.
      harnessKey.currentState!.enable();
      await tester.pump();

      // The slider must stay neutral, not snap back to the interrupted step.
      expect(harnessKey.currentState!.externalStateId, MultiStepSliderStateId.idle);
      expect(harnessKey.currentState!.states.last, MultiStepSliderStateId.idle);

      final thumb = find.byKey(const ValueKey('multi_step_slider_thumb'));
      final neutralCenter = tester.getCenter(thumb);

      // A fresh gesture must still be required — and must still work — to
      // reach step1 again.
      final freshGesture = await _dragToStep1(tester);
      expect(harnessKey.currentState!.states.last, MultiStepSliderStateId.step1);
      expect(
        tester.getCenter(thumb).dy,
        isNot(closeTo(neutralCenter.dy, 1.0)),
      );
      await freshGesture.up();
      await tester.pump();
    },
  );
}

Future<TestGesture> _dragToStep1(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey('multi_step_slider_thumb'));
  final gesture = await tester.startGesture(tester.getCenter(thumb));
  // IndustrialMultiStepSlider always renders vertically (it wraps its
  // horizontally-authored content in a RotatedBox), so on screen this is a
  // vertical drag; Flutter transforms the gesture back into the widget's
  // local horizontal drag axis "for free" (see the widget's own build()
  // comment on this technique).
  await gesture.moveBy(const Offset(0, -80));
  await tester.pump();
  return gesture;
}

class _SliderHarness extends StatefulWidget {
  const _SliderHarness({super.key});

  @override
  State<_SliderHarness> createState() => _SliderHarnessState();
}

class _SliderHarnessState extends State<_SliderHarness> {
  bool _enabled = true;
  final List<String> states = <String>[];

  /// Mirrors plc38/plc14 control screens' `_localActive` map: written only
  /// by the slider's own onStateChanged callback, read back (masked to idle
  /// while disabled) as the slider's externalStateId — exactly the
  /// production wiring the reported bug traveled through.
  String? _localActive;

  String get externalStateId =>
      _enabled ? (_localActive ?? MultiStepSliderStateId.idle) : MultiStepSliderStateId.idle;

  void disable() => setState(() => _enabled = false);

  void enable() => setState(() => _enabled = true);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 100,
            height: 300,
            child: IndustrialMultiStepSlider(
              label: 'Test',
              icon: Icons.arrow_upward_rounded,
              enabled: _enabled,
              stateId: externalStateId,
              onStateChanged: (stateId) {
                setState(() {
                  if (stateId == MultiStepSliderStateId.idle) {
                    _localActive = null;
                  } else {
                    _localActive = stateId;
                  }
                  states.add(stateId);
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}
