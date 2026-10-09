import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/engines/today_completion.dart';
import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/add_task_sheet.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/services/flow_clock.dart';

/// Today and task completion: finished work folds away behind "Completed today · N"; a fully finished day shows
/// sleeping Noya, "All done for today!" and "Add more tasks"; an empty day is a different screen; a new day starts
/// clean and History keeps everything.
late DateTime _now;

DateTime _at(int dayOffset, int hour) => DateTime(_now.year, _now.month, _now.day + dayOffset, hour);

TaskItem _task(String id, {int day = 0, int hour = 9, bool done = false, DateTime? completedAt}) => TaskItem(
      id: id,
      title: 'Task $id',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: '',
      category: 'Work',
      isCompleted: done,
      completedAt: done ? (completedAt ?? _at(day, hour)) : null,
      scheduledStart: _at(day, hour),
      plannedDate: DateTime(_now.year, _now.month, _now.day + day),
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    final real = DateTime.now(); // completing a task stamps the real clock, so the test day is the real date
    _now = DateTime(real.year, real.month, real.day, 15);
    FlowClock.debugNowOverride = () => _now;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  group('engine', () {
    test('open, completed today, yesterday and cancelled are told apart', () {
      final c = TodayCompletion.of([
        _task('a', done: true, hour: 8),
        _task('b', done: true, hour: 11),
        _task('c'),
        _task('old', day: -1, done: true),
        _task('x').copyWith(status: TaskStatus.cancelled),
      ], _now);
      expect(c.completedToday.map((t) => t.id), ['b', 'a'], reason: 'most recent first; yesterday excluded');
      expect(c.openToday.map((t) => t.id), ['c']);
      expect(c.allDone, isFalse);
      expect(c.isEmptyDay, isFalse);
    });

    test('all done vs empty day', () {
      expect(TodayCompletion.of([_task('a', done: true)], _now).allDone, isTrue);
      final empty = TodayCompletion.of([_task('old', day: -1, done: true)], _now);
      expect(empty.isEmptyDay, isTrue);
      expect(empty.allDone, isFalse);
    });
  });

  group('Today screen', () {
    AppStateProvider provider(List<TaskItem> tasks) {
      // signed out: completing a task stays local (no backend in these tests)
      final p = AppStateProvider()..setTasksForTesting(tasks);
      p.updatePersonalData(p.personalData.copyWith(bedtime: '23:59'));
      return p;
    }

    Future<void> pump(WidgetTester tester, AppStateProvider state) async {
      final flow = FlowProvider()..setOverviewForTesting(FlowOverview.defaultInitial(userId: 'u-today'));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: state),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<FlowProvider>.value(value: flow),
        ],
        child: const MaterialApp(home: TodayDashboardTab()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('completing the last task: sleeping Noya, All done, completed list collapsed then expandable',
        (tester) async {
      final state = provider([_task('a', done: true, hour: 8), _task('b', hour: 16)]);
      await pump(tester, state);
      expect(find.text('All done for today!'), findsNothing);

      state.toggleTaskCompletion('b');
      await tester.pumpAndSettle();

      expect(find.text('All done for today!'), findsOneWidget);
      expect(tester.widget<NoyaCompanionView>(find.byKey(const Key('all_done_noya'))).state, NoyaState.sleepy);
      expect(find.text('Completed today · 2'), findsOneWidget);
      expect(find.byKey(const Key('today_moment_a')), findsNothing, reason: 'collapsed by default');

      await tester.tap(find.byKey(const Key('completed_today_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_moment_a')), findsOneWidget);
      expect(find.byKey(const Key('today_moment_b')), findsOneWidget);

      await tester.tap(find.byKey(const Key('completed_today_toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('today_moment_a')), findsNothing);
    });

    testWidgets('Add more tasks opens the add sheet, and a new task brings the active day back', (tester) async {
      final state = provider([_task('a', done: true)]);
      await pump(tester, state);
      await tester.tap(find.text('Add more tasks'));
      await tester.pumpAndSettle();
      expect(find.byType(AddTaskSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(AddTaskSheet))).pop();
      await tester.pumpAndSettle();

      state.setTasksForTesting([...state.tasks, _task('new', hour: 18)]);
      await tester.pumpAndSettle();
      expect(find.text('All done for today!'), findsNothing);
      expect(state.isDayCompleted, isFalse);
      expect(find.text('Completed today · 1'), findsOneWidget, reason: 'finished work stays folded in the active view');
      expect(find.byKey(const Key('today_moment_a')), findsNothing);
    });

    testWidgets('active day: finished tasks are hidden from UP NEXT and behind the Completed today button',
        (tester) async {
      final state = provider([_task('a', done: true, hour: 8), _task('b', hour: 16), _task('c', hour: 17)]);
      await pump(tester, state);
      expect(find.text('All done for today!'), findsNothing);
      expect(find.text('Task a'), findsNothing, reason: 'a finished task is not in the active list');
    });

    testWidgets('an empty day is not a completed day', (tester) async {
      final state = provider([]);
      await pump(tester, state);
      expect(find.byKey(const Key('hero_build_my_day_button')), findsOneWidget);
      expect(find.text('All done for today!'), findsNothing);
    });

    testWidgets('a new day starts clean and History keeps yesterday', (tester) async {
      final state = provider([_task('a', done: true, hour: 8)]);
      await pump(tester, state);
      expect(find.text('All done for today!'), findsOneWidget);

      _now = _now.add(const Duration(days: 1)); // midnight passed
      state.setTasksForTesting(List.of(state.tasks));
      await tester.pumpAndSettle();

      expect(find.text('All done for today!'), findsNothing);
      expect(find.byKey(const Key('hero_build_my_day_button')), findsOneWidget, reason: 'empty day, not completed');
      expect(state.tasks.single.isCompleted, isTrue, reason: 'nothing was deleted');
      final history = HistoryDay.from(tasks: state.tasks, reflections: const [], now: _now);
      expect(history.expand((d) => d.entries).map((e) => e.taskId), contains('a'));
    });
  });
}
