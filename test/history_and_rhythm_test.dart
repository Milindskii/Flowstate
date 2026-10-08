import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/companion/noya_moments.dart';
import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/task_reflection.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/insights_history_screen.dart';
import 'package:flowstate/screens/insights_tab.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_theme.dart';

TaskItem _done(String id, DateTime at, {String category = 'Work', int minutes = 40}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: minutes,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: category,
      isCompleted: true,
      completedAt: at,
    );

TaskReflection _felt(String id, int feeling, DateTime at, {int difficulty = 3, int actual = 50, int planned = 40}) => TaskReflection(
      taskId: id,
      title: id,
      feeling: feeling,
      energy: 4,
      focus: 4,
      difficulty: difficulty,
      distraction: 1,
      completedAt: at,
      actualMinutes: actual,
      plannedMinutes: planned,
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  group('Noya by kind of work', () {
    test('work kind is read from category, type and title at word starts', () {
      expect(workKindOf(category: 'Fitness'), WorkKind.physical);
      expect(workKindOf(title: 'Morning run'), WorkKind.physical);
      expect(workKindOf(title: 'Sunday brunch'), WorkKind.other);
      expect(workKindOf(category: 'Study'), WorkKind.study);
      expect(workKindOf(title: 'Plan the week'), WorkKind.planning);
      expect(workKindOf(type: 'High Focus'), WorkKind.deepWork);
    });

    test('planned work shows the pose of the work ahead', () {
      expect(noyaStateForTask(kind: WorkKind.physical, done: false), NoyaState.cheering);
      expect(noyaStateForTask(kind: WorkKind.study, done: false), NoyaState.focusing);
      expect(noyaStateForTask(kind: WorkKind.planning, done: false), NoyaState.planning);
      expect(noyaStateForTask(kind: WorkKind.other, done: false), NoyaState.encouraging);
    });

    test('finished work reacts to how it went', () {
      final at = DateTime(2026, 10, 3, 9);
      expect(noyaStateForTask(kind: WorkKind.study, done: true), NoyaState.goodJob);
      expect(noyaStateForTask(kind: WorkKind.study, done: true, reflection: _felt('x', 1, at)), NoyaState.sleepy);
      expect(noyaStateForTask(kind: WorkKind.study, done: true, reflection: _felt('x', 2, at, difficulty: 5)), NoyaState.sleepy);
      expect(noyaStateForTask(kind: WorkKind.study, done: true, reflection: _felt('x', 4, at)), NoyaState.celebrating);
      expect(noyaStateForTask(kind: WorkKind.physical, done: true, reflection: _felt('x', 4, at)), NoyaState.cheering);
      expect(noyaStateForTask(kind: WorkKind.study, done: true, reflection: _felt('x', 3, at)), NoyaState.proud);
    });
  });

  group('History moment panel', () {
    testWidgets('slides in from the side with a planned-vs-actual ribbon and closes', (tester) async {
      final item = ScheduleItem(
        id: 'comp-s',
        taskId: 's',
        time: '9:00',
        period: 'AM',
        title: 'Study arrays',
        type: 'Task',
        tagText: 'COMPLETED',
        isCompleted: true,
        durationMinutes: 60,
        startTime: DateTime(2026, 10, 3, 9),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showHistoryMomentSheet(
                context,
                item: item,
                category: 'Study',
                completedAt: DateTime(2026, 10, 3, 9, 50),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final panel = find.byKey(const Key('history_moment_sheet'));
      // Mid-transition it is still travelling in from the right edge.
      expect(tester.getTopLeft(panel).dx, greaterThan(800 - 800 * 0.88));
      await tester.pumpAndSettle();
      expect(tester.getTopRight(panel).dx, 800);
      expect(find.text('Finished 10 min early'), findsOneWidget);
      expect(find.text('Saturday, October 3 · Study'), findsOneWidget);
      // No reflection yet: a plain good-job, not an invented feeling.
      expect(tester.widget<NoyaMotionView>(find.descendant(of: panel, matching: find.byType(NoyaMotionView))).pose, NoyaState.goodJob);

      await tester.tap(find.byKey(const Key('history_moment_close')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
    });
  });

  group('History days', () {
    test('groups finished work by day, newest first, reflections winning the time', () {
      final d1 = DateTime(2026, 10, 1, 9);
      final d2 = DateTime(2026, 10, 2, 18);
      final days = HistoryDay.from(
        tasks: [_done('a', d1), _done('b', d2), _done('c', d1.add(const Duration(hours: 3))), const TaskItem(
          id: 'untimed', title: 'u', durationMinutes: 10, difficulty: TaskDifficulty.light, deadline: '', category: '',
          isCompleted: true,
        )],
        reflections: [_felt('a', 4, d1.add(const Duration(minutes: 20)))],
      );
      expect(days.map((d) => d.date.day), [2, 1]);
      expect(days[1].entries.map((e) => e.taskId), ['a', 'c']);
      expect(days[1].entries.first.completedAt, d1.add(const Duration(minutes: 20)));
      expect(days[1].entries.first.minutes, 50);
      expect(days[1].totalMinutes, 90);
      expect(days[1].averageFeeling, 4);
      expect(days[1].minutesVersusPlan, 10);
      expect(days[0].averageFeeling, isNull);
    });

    testWidgets('Insights links to History; a day opens into what was done and how it felt', (tester) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = FlowClock().now;
      final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1)).add(const Duration(hours: 10));
      final state = AppStateProvider()..setTasksForTesting([_done('Gym', yesterday, category: 'Fitness')]);
      await state.reflectionsReady;
      state.recordTaskFeedback(
        taskId: 'Gym', actualMinutes: 45, feeling: 3, energyScore: 4, focusScore: 3, difficultyScore: 3,
        distractionScore: 1, completedAt: yesterday, durationMeasured: true,
      );
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsTab()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('insights_history_button')));
      await tester.pumpAndSettle();
      expect(find.byType(InsightsHistoryScreen), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('1 finished · 45 min · felt good'), findsOneWidget);

      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();
      expect(find.text('45 min · Fitness · felt good'), findsOneWidget);
      expect(find.text('See this day in Calendar'), findsOneWidget);
    });

    testWidgets('no finished days: an honest empty state', (tester) async {
      final state = AppStateProvider()..setTasksForTesting(const []);
      await tester.pumpWidget(MaterialApp(
        theme: FlowTheme.darkTheme(),
        home: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsHistoryScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('insights_history_empty')), findsOneWidget);
      expect(find.text('No finished days yet.'), findsOneWidget);
    });
  });

  testWidgets('rhythm curve renders in dark mode at 360dp without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    final state = AppStateProvider()
      ..setTasksForTesting([
        for (var i = 0; i < 4; i++) _done('t$i', today.add(Duration(hours: 9 + i))),
      ]);
    await tester.pumpWidget(MaterialApp(
      theme: FlowTheme.darkTheme(),
      home: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsTab()),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights_rhythm_curve')), findsOneWidget);
    expect(find.text('Your rhythm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
