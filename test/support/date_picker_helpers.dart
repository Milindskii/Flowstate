import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opens the shared date picker through [button] and picks [day] in the Material dialog (the one real date control).
Future<void> pickDateVia(WidgetTester tester, Finder button, DateTime day) async {
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(DatePickerDialog), findsOneWidget);
  final now = DateTime.now();
  var months = (day.year - now.year) * 12 + day.month - now.month;
  while (months-- > 0) {
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('${day.day}').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Done').hitTestable().first);
  await tester.pumpAndSettle();
}
