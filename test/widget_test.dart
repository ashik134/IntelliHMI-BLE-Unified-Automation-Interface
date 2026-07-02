// Smoke test for the actual app (the stock Flutter counter template this
// file used to contain doesn't correspond to anything in this codebase).
// Verifies the app builds its widget tree without throwing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rev_crane_control_ops/main.dart';

void main() {
  testWidgets('IntelliHMIApp builds without throwing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const IntelliHMIApp());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
