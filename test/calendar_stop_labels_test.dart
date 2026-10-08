import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/theme/flow_theme.dart';

ScheduleItem _stop(String id, String time, String period, int minutes,
        {bool done = false, bool recovered = false, bool missed = false, bool skipped = false}) =>
    ScheduleItem(
      id: id,
      taskId: id,
      time: time,
      period: period,
      title: 'Task $id',
      type: 'Task',
      tagText: 'TASK',
      durationMinutes: minutes,
      isCompleted: done,
      isCompletedAfterDeviation: recovered,
      isMissed: missed,
      isSkipped: skipped,
    );

/// Every Calendar stop reads as "a stop on my day": a small outcome glyph, the title, the planned time and length, and
/// a state word only where it helps (Skipped / Missed / Recovered).
void main() {
  Future<void> pump(WidgetTester tester, List<ScheduleItem> items) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(
      theme: FlowTheme.lightTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: FlowDayPath(
            items: items,
            nowItemId: null,
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  String tags(WidgetTester tester, String id) =>
      tester.widget<Text>(find.byKey(Key('path_tags_$id'))).textSpan!.toPlainText();

  testWidgets('completed, skipped, missed and recovered stops each carry their glyph, time, length and state word', (tester) async {
    await pump(tester, [
      _stop('done', '8:00', 'AM', 90, done: true),
      _stop('skip', '10:30', 'AM', 60, skipped: true),
      _stop('miss', '2:00', 'PM', 30, missed: true),
      _stop('rec', '3:30', 'PM', 45, done: true, recovered: true),
      _stop('next', '5:00', 'PM', 20),
    ]);

    IconData glyph(String id) => tester.widget<Icon>(find.byKey(Key('path_glyph_$id'))).icon!;
    expect(glyph('done'), Icons.check_rounded);
    expect(glyph('skip'), Icons.redo_rounded);
    expect(glyph('miss'), Icons.priority_high_rounded);
    expect(glyph('rec'), Icons.check_rounded);
    expect(find.byKey(const Key('path_glyph_next')), findsNothing, reason: 'a plain upcoming stop needs no glyph');

    expect(find.text('Task done'), findsOneWidget);
    expect(find.text('10:30 AM · 60 min'), findsOneWidget);
    expect(find.text('2:00 PM · 30 min'), findsOneWidget);
    expect(find.text('5:00 PM · 20 min'), findsOneWidget);

    expect(tags(tester, 'skip'), contains('Skipped'));
    expect(tags(tester, 'miss'), contains('Missed'));
    expect(tags(tester, 'rec'), contains('Recovered'));
    expect(find.byKey(const Key('path_tags_done')), findsNothing, reason: 'nothing to flag on an on-plan completion');
  });

  testWidgets('skipped and missed read differently: a skip is the user\'s, a miss is the clock\'s', (tester) async {
    await pump(tester, [_stop('s', '9:00', 'AM', 30, skipped: true), _stop('m', '11:00', 'AM', 30, missed: true)]);
    expect(tags(tester, 's'), isNot(contains('Missed')));
    expect(tags(tester, 'm'), isNot(contains('Skipped')));
  });
}
