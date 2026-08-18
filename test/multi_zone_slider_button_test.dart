import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/widgets/buttons/button/multi_zone_slider_button.dart';

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

  testWidgets('defers a blocked-zone release until after build', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_SliderHarnessState>();
    await tester.pumpWidget(_SliderHarness(key: harnessKey));

    final gesture = await _dragIntoEndZone(tester);
    expect(
      harnessKey.currentState!.states.last,
      isNot(MultiZoneSliderStateId.center),
    );

    harnessKey.currentState!.blockEndZone();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.states.last, MultiZoneSliderStateId.center);

    await gesture.up();
    await tester.pump();
  });

  testWidgets('defers a disabled-slider release until after build', (
    tester,
  ) async {
    final harnessKey = GlobalKey<_SliderHarnessState>();
    await tester.pumpWidget(_SliderHarness(key: harnessKey));

    final gesture = await _dragIntoEndZone(tester);
    expect(
      harnessKey.currentState!.states.last,
      isNot(MultiZoneSliderStateId.center),
    );

    harnessKey.currentState!.disable();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(harnessKey.currentState!.states.last, MultiZoneSliderStateId.center);

    await gesture.up();
    await tester.pump();
  });
}

Future<TestGesture> _dragIntoEndZone(WidgetTester tester) async {
  final thumb = find.byKey(const ValueKey('multi_zone_slider_thumb'));
  final gesture = await tester.startGesture(tester.getCenter(thumb));
  await gesture.moveBy(const Offset(80, 0));
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
  bool _isEndZoneBlocked = false;
  final List<String> states = <String>[];

  void blockEndZone() => setState(() => _isEndZoneBlocked = true);

  void disable() => setState(() => _enabled = false);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 100,
            child: IndustrialMultiZoneSlider(
              startLabel: 'Start',
              endLabel: 'End',
              startIcon: Icons.arrow_back_rounded,
              endIcon: Icons.arrow_forward_rounded,
              enabled: _enabled,
              isEndZoneBlocked: _isEndZoneBlocked,
              onStateChanged: (stateId) {
                setState(() => states.add(stateId));
              },
            ),
          ),
        ),
      ),
    );
  }
}
