import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/task_reflection.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/insights_history_screen.dart';
import 'package:flowstate/services/flow_clock.dart';

/// History files a finished task under the day it BELONGED TO (its planned day: the same rule as Calendar, Today and the
/// server), not the moment it was ticked off. The completion time stays on the row; when it falls on another day the
/// row says "done early" or "done late".
DateTime d(int day, [int hour = 0, int minute = 0]) => DateTime(2026, 10, day, hour, minute);

TaskItem done(
  String id, {
  DateTime? planned,
  DateTime? start,
  DateTime? completed,
  String title = 'Gym',
}) =>
    TaskItem.fromJson({
      'id': id,
      'title': title,
      'status': 'completed',
      'is_completed': true,
      'estimated_minutes': 30,
      if (planned != null) 'planned_date': '2026-10-${planned.day.toString().padLeft(2, '0')}',
      if (start != null) 'scheduled_start': start.toUtc().toIso8601String(),
      if (start != null) 'scheduled_end': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
      if (completed != null) 'completed_at': completed.toUtc().toIso8601String(),
    });

List<HistoryDay> history(List<TaskItem> tasks, [List<TaskReflection> reflections = const []]) =>
    HistoryDay.from(tasks: tasks, reflections: reflections);

void main() {
  test('planned tomorrow, completed today: it belongs to tomorrow, marked "done early"', () {
    final days = history([done('a', planned: d(6), start: d(6, 17), completed: d(5, 11))]);
    expect(days.map((x) => x.date), [d(6)], reason: 'filed under the planned day, never under today');
    expect(days.single.entries.single.timing, HistoryTiming.early);
    expect(days.single.entries.single.completedAt, d(5, 11), reason: 'the real completion time is kept');
  });

  test('planned today, completed tomorrow: it stays on today, marked "done late"', () {
    final days = history([done('a', planned: d(5), start: d(5, 17), completed: d(6, 9))]);
    expect(days.map((x) => x.date), [d(5)]);
    expect(days.single.entries.single.timing, HistoryTiming.late);
  });

  test('moved from today to tomorrow (planned date updated), then done: it belongs to tomorrow, on time', () {
    final days = history([done('a', planned: d(6), start: d(6, 17), completed: d(6, 17, 30))]);
    expect(days.map((x) => x.date), [d(6)]);
    expect(days.single.entries.single.timing, HistoryTiming.onTime);
  });

  test('completed after midnight: a 23:30 task done at 00:10 belongs to the day it was planned for', () {
    final days = history([done('a', planned: d(5), start: d(5, 23, 30), completed: d(6, 0, 10))]);
    expect(days.map((x) => x.date), [d(5)]);
    expect(days.single.entries.single.timing, HistoryTiming.late);
  });

  test('a task with no planned date uses the day of its slot', () {
    final days = history([done('a', start: d(7, 9), completed: d(5, 8))]);
    expect(days.map((x) => x.date), [d(7)]);
  });

  test('a task with neither is filed by when it was completed (nothing else is known)', () {
    final days = history([done('a', completed: d(5, 8))]);
    expect(days.map((x) => x.date), [d(5)]);
    expect(days.single.entries.single.timing, HistoryTiming.onTime);
  });

  test('days are newest first; entries within a day are in completion order', () {
    final days = history([
      done('a', planned: d(5), completed: d(5, 15), title: 'Later'),
      done('b', planned: d(5), completed: d(5, 9), title: 'Earlier'),
      done('c', planned: d(6), completed: d(5, 12), title: 'Tomorrow task'),
    ]);
    expect(days.map((x) => x.date), [d(6), d(5)]);
    expect(days.last.entries.map((e) => e.title), ['Earlier', 'Later']);
  });

  test('a reflection\'s completion time wins for the time shown, never for the day', () {
    final reflection = TaskReflection(
      taskId: 'a',
      title: 'Gym',
      feeling: 3,
      energy: 3,
      focus: 3,
      difficulty: 3,
      distraction: 1,
      plannedMinutes: 30,
      actualMinutes: 35,
      completedAt: d(5, 18),
    );
    final days = history([done('a', planned: d(6), completed: d(5, 11))], [reflection]);
    expect(days.map((x) => x.date), [d(6)]);
    expect(days.single.entries.single.completedAt, d(5, 18));
  });

  test('after an app restart (tasks re-read from the server) the grouping is the same', () {
    final json = {
      'id': 'a',
      'title': 'Gym',
      'status': 'completed',
      'planned_date': '2026-10-06',
      'scheduled_start': d(6, 17).toUtc().toIso8601String(),
      'completed_at': d(5, 11).toUtc().toIso8601String(),
    };
    final first = history([TaskItem.fromJson(json)]);
    final again = history([TaskItem.fromJson(Map<String, dynamic>.from(json))]);
    expect(again.map((x) => x.date), first.map((x) => x.date));
    expect(again.single.date, d(6));
  });

  test('one rule for every surface: owningDate is the planned day, else the slot\'s day', () {
    expect(done('a', planned: d(6), start: d(5, 9)).owningDate, d(6), reason: 'planned wins, like the server');
    expect(done('a', start: d(7, 9)).owningDate, d(7));
    expect(done('a', completed: d(5, 9)).owningDate, isNull, reason: 'completion time is never an owner');
  });

  group('the History screen', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => FlowClock().stopTimer());

    Future<AppStateProvider> open(WidgetTester tester, List<TaskItem> tasks) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final state = AppStateProvider()..setTasksForTesting(tasks);
      await state.reflectionsReady;
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsHistoryScreen()),
      ));
      await tester.pumpAndSettle();
      return state;
    }

    DateTime today(int plusDays, [int hour = 9]) {
      final n = FlowClock().now;
      return DateTime(n.year, n.month, n.day + plusDays, hour);
    }

    String planned(DateTime t) => '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

    TaskItem finished(String id, {required DateTime plannedDay, required DateTime completed}) => TaskItem.fromJson({
          'id': id,
          'title': 'Gym',
          'status': 'completed',
          'estimated_minutes': 30,
          'planned_date': planned(plannedDay),
          'scheduled_start': DateTime(plannedDay.year, plannedDay.month, plannedDay.day, 17).toUtc().toIso8601String(),
          'completed_at': completed.toUtc().toIso8601String(),
        });

    testWidgets('work planned for tomorrow and done today belongs to tomorrow, marked done early', (tester) async {
      await open(tester, [finished('a', plannedDay: today(1), completed: today(0))]);
      expect(find.text('Tomorrow'), findsOneWidget);
      expect(find.text('Today'), findsNothing, reason: 'it did not belong to today');
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      expect(find.textContaining('done early'), findsOneWidget);
    });

    testWidgets('work planned for today and done tomorrow stays on today, marked done late', (tester) async {
      await open(tester, [finished('a', plannedDay: today(0), completed: today(1))]);
      expect(find.text('Today'), findsOneWidget);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.textContaining('done late'), findsOneWidget);
    });

    testWidgets('work done on its own day carries no early/late marker', (tester) async {
      await open(tester, [finished('a', plannedDay: today(0), completed: today(0, 18))]);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.textContaining('done early'), findsNothing);
      expect(find.textContaining('done late'), findsNothing);
    });
  });
}
