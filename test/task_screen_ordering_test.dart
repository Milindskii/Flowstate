import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/task_inbox_tab.dart';
import 'package:flowstate/services/flow_clock.dart';

// Task screen order = persisted planned_date + slot start; unscheduled after, first entered on top
// unless a priority was explicitly set. Never created/completed/response order for scheduled tasks.
final day = DateTime(2026, 10, 5);
DateTime at(int h, {int d = 5}) => DateTime(2026, 10, d, h);

TaskItem task(String id, {DateTime? start, DateTime? planned, int createdMin = 0, bool done = false,
    TaskPriority? priority}) {
  return TaskItem(
    id: id,
    title: id,
    durationMinutes: 30,
    difficulty: TaskDifficulty.medium,
    deadline: 'Today',
    category: 'General',
    isCompleted: done,
    status: done ? TaskStatus.completed : TaskStatus.todo,
    scheduledStart: start,
    scheduledEnd: start?.add(const Duration(minutes: 30)),
    plannedDate: planned ?? (start == null ? day : null),
    createdAt: DateTime(2026, 10, 1).add(Duration(minutes: createdMin)),
    completedAt: done ? DateTime(2026, 10, 5, 23) : null,
    priority: priority,
    prioritySource: priority == null ? 'unspecified' : 'explicit',
  );
}

List<String> ordered(List<TaskItem> ts) => (ts.toList()..sort(compareTaskOrder)).map((t) => t.id).toList();

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  test('1. out-of-order tasks sort chronologically, not by created order', () {
    final ts = [
      task('evening', start: at(18), createdMin: 1),
      task('morning', start: at(9), createdMin: 3),
      task('noon', start: at(12), createdMin: 2),
      task('tomorrow', start: at(8, d: 6), createdMin: 0),
    ];
    expect(ordered(ts), ['morning', 'noon', 'evening', 'tomorrow']);
  });

  test('2. a rescheduled task moves to its new position', () {
    final a = task('a', start: at(9));
    final b = task('b', start: at(11));
    final c = task('c', start: at(14));
    expect(ordered([a, b, c]), ['a', 'b', 'c']);
    final movedLater = a.copyWith(scheduledStart: at(15));
    expect(ordered([movedLater, b, c]), ['b', 'c', 'a']);
    // replan to tomorrow (planned_date + slot): after every task of today
    final movedTomorrow = b.copyWith(scheduledStart: at(7, d: 6), plannedDate: DateTime(2026, 10, 6));
    expect(ordered([a, movedTomorrow, c]), ['a', 'c', 'b']);
  });

  test('3. completing a task keeps its planned-date position (completion time ignored)', () {
    final ts = [task('a', start: at(9)), task('b', start: at(11), done: true), task('c', start: at(14))];
    expect(ordered(ts), ['a', 'b', 'c']);
  });

  test('4. unscheduled after scheduled; first entered on top unless priority was set', () {
    final ts = [
      task('later-entered', createdMin: 5),
      task('first-entered', createdMin: 1),
      task('scheduled', start: at(20), createdMin: 9),
      task('explicit-urgent', createdMin: 7, priority: TaskPriority.urgent),
      task('explicit-low', createdMin: 0, priority: TaskPriority.low),
    ];
    expect(ordered(ts), ['scheduled', 'explicit-urgent', 'first-entered', 'later-entered', 'explicit-low']);
  });

  test('5. order survives a reload (JSON round trip, any arrival order)', () {
    final ts = [
      task('c', start: at(14)),
      task('u2', createdMin: 2),
      task('a', start: at(9)),
      task('u1', createdMin: 1),
    ];
    final reloaded = ts.reversed.map((t) => TaskItem.fromJson(t.toJson())).toList();
    expect(ordered(reloaded), ordered(ts));
    expect(ordered(reloaded), ['a', 'c', 'u1', 'u2']);
  });

  Future<AppStateProvider> pumpTasks(WidgetTester tester, List<TaskItem> tasks) async {
    final appState = AppStateProvider()..setTasksForTesting(tasks);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ],
      child: const MaterialApp(home: TaskInboxTab()),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    return appState;
  }

  double y(WidgetTester tester, String t) => tester.getTopLeft(find.text(t).first).dy;

  testWidgets('Task screen renders out-of-order tasks chronologically', (tester) async {
    await pumpTasks(tester, [
      task('Evening run', start: at(18), createdMin: 0),
      task('Inbox later', createdMin: 4),
      task('Morning essay', start: at(9), createdMin: 2),
      task('Inbox first', createdMin: 1),
    ]);
    expect(y(tester, 'Morning essay'), lessThan(y(tester, 'Evening run')));
    expect(y(tester, 'Evening run'), lessThan(y(tester, 'Inbox first')));
    expect(y(tester, 'Inbox first'), lessThan(y(tester, 'Inbox later')));
  });

  testWidgets('an explicit urgent task does not jump above an earlier scheduled task', (tester) async {
    await pumpTasks(tester, [
      task('Urgent call', start: at(18), priority: TaskPriority.urgent),
      task('Morning essay', start: at(9)),
    ]);
    expect(y(tester, 'Morning essay'), lessThan(y(tester, 'Urgent call')));
  });

  testWidgets('a rescheduled task re-renders at its new position', (tester) async {
    final a = task('Alpha', start: at(9));
    final b = task('Bravo', start: at(11));
    final state = await pumpTasks(tester, [a, b]);
    expect(y(tester, 'Alpha'), lessThan(y(tester, 'Bravo')));
    state.setTasksForTesting([a.copyWith(scheduledStart: at(15)), b]);
    await tester.pump(const Duration(milliseconds: 500));
    expect(y(tester, 'Bravo'), lessThan(y(tester, 'Alpha')));
  });

  testWidgets('completed tasks keep planned order, not completion order', (tester) async {
    await pumpTasks(tester, [
      task('Late done', start: at(17), done: true).copyWith(completedAt: DateTime(2026, 10, 5, 9)),
      task('Early done', start: at(8), done: true).copyWith(completedAt: DateTime(2026, 10, 5, 22)),
    ]);
    expect(y(tester, 'Early done'), lessThan(y(tester, 'Late done')));
  });
}
