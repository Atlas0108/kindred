import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kindred/features/auth/setup_screen.dart';

void main() {
  testWidgets('SetupScreen shows Firebase configuration hint', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SetupScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Firebase'), findsWidgets);
  });
}
