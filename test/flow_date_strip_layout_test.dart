import 'package:flowstate/components/flow_date_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Switching days must never read a render box that jumpTo / a rebuild has just invalidated: the strip reveals the
/// selected chip only against boxes that have been laid out, and waits a frame after it moves itself.
void main() {
  final today = DateTime(2026, 10, 7);
  final days = [for (var i = -14; i <= 30; i++) today.add(Duration(days: i))];

  Widget host(DateTime selected, {double width = 320}) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: width,
            height: 90,
            child: FlowDateStrip(days: days, selected: selected, today: today, onSelect: (_) {}),
          ),
        ),
      );

  testWidgets('first show with a far-away selection does not assert', (tester) async {
    await tester.pumpWidget(host(today.add(const Duration(days: 25))));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching dates repeatedly, mid-animation and across a width change, never asserts', (tester) async {
    await tester.pumpWidget(host(today));
    await tester.pumpAndSettle();
    for (var i = 0; i < 30; i++) {
      final d = today.add(Duration(days: (i * 7) % 40 - 10));
      await tester.pumpWidget(host(d, width: i.isEven ? 320 : 400));
      await tester.pump(Duration(milliseconds: 20 + (i % 5) * 30));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selected chip ends up visible', (tester) async {
    await tester.pumpWidget(host(today));
    await tester.pumpAndSettle();
    final target = today.add(const Duration(days: 20));
    await tester.pumpWidget(host(target));
    await tester.pumpAndSettle();
    final scroll = tester.getRect(find.byType(SingleChildScrollView));
    final selected = tester.getRect(find.byKey(const Key('calendar_day_chip_2026-10-27')));
    expect(scroll.overlaps(selected), isTrue);
    expect(tester.takeException(), isNull);
  });
}
