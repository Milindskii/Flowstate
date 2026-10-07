import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/insights_tab.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_theme.dart';

Widget _host(AppStateProvider state, {ThemeData? theme, double width = 412}) => MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 2400)),
        child: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsTab()),
      ),
    );

TaskItem _done(String id, DateTime at) => TaskItem(
      id: id,
      title: id,
      durationMinutes: 40,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isCompleted: true,
      completedAt: at,
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('no history: a thinking Noya, honest "still learning" copy, and no invented numbers', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppStateProvider()..setTasksForTesting(const []);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    expect(tester.widget<NoyaMotionView>(find.byKey(const Key('insights_noya'))).pose, NoyaState.thinking);
    expect(find.text("We're still learning your rhythm."), findsOneWidget);
    expect(find.text('Start a focus session'), findsOneWidget);
    for (final fake in ['Personal Best', 'Completion Rate', '10 AM (Peak)', 'Empirical Bayes', 'Stage A']) {
      expect(find.textContaining(fake), findsNothing);
    }
    expect(find.byKey(const Key('insights_week')), findsNothing);
    expect(find.byKey(const Key('insights_data_note')), findsOneWidget);
  });

  testWidgets('with real history: week, windows, feelings and planned-vs-actual come from the data', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    final morning = today.add(const Duration(hours: 9));
    final state = AppStateProvider()
      ..setTasksForTesting([
        _done('a', morning),
        _done('b', morning.add(const Duration(minutes: 30))),
        _done('c', morning.add(const Duration(hours: 1))),
      ]);
    await state.reflectionsReady;
    for (final id in ['a', 'b', 'c']) {
      state.recordTaskFeedback(
        taskId: id, actualMinutes: 50, feeling: id == 'a' ? 4 : 3,
        energyScore: 4, focusScore: 4, difficultyScore: 2, distractionScore: 1, completedAt: morning,
      );
    }
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();

    expect(find.text('3 tasks finished across 1 day this week'), findsOneWidget);
    // One Noya on the page, in "What Flowstate learned", with a pattern to share.
    expect(find.byType(NoyaMotionView), findsOneWidget);
    expect(tester.widget<NoyaMotionView>(find.byKey(const Key('insights_noya'))).pose, NoyaState.idea);
    expect(find.byKey(Key('insights_day_${now.weekday - 1}_3')), findsOneWidget);
    expect(find.text('You finish the most in the morning (5 AM – 12 PM).'), findsOneWidget);
    expect(find.byKey(const Key('insights_feeling_4_1')), findsOneWidget);
    expect(find.byKey(const Key('insights_feeling_3_2')), findsOneWidget);
    // Interpretations carry the evidence behind them.
    expect(find.text('You get the most done in the morning.'), findsOneWidget);
    expect(find.text('3 of 3 finished tasks landed between 5 AM – 12 PM.'), findsOneWidget);
    expect(find.text('Tasks tend to run about 25% over what you plan.'), findsOneWidget);
    // Only one part of the day has reflections, so no "sharpest focus" comparison is claimed.
    expect(find.byKey(const Key('insights_learned_focus_window')), findsNothing);
    expect(find.byKey(const Key('insights_windows')), findsOneWidget);
    expect(find.byKey(const Key('insights_feelings')), findsOneWidget);
    // 50 actual vs 40 planned on every reflection → +25%.
    expect(find.text('Tasks usually take about 25% longer than planned'), findsOneWidget);
    expect(find.text('From 3 reflections on this device'), findsOneWidget);
    expect(find.text('3 reflections recorded on this device.'), findsOneWidget);
  });

  testWidgets('too little data: charts are hidden and what is missing is listed once', (tester) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = FlowClock().now;
    final state = AppStateProvider()..setTasksForTesting([_done('a', now)]);
    await tester.pumpWidget(_host(state));
    await tester.pumpAndSettle();
    expect(find.text('Finish 2 more tasks to see when you tend to get things done.'), findsOneWidget);
    expect(find.textContaining('Reflect on 3 more tasks'), findsOneWidget);
    expect(find.text('Reflect on a few finished tasks to compare planned and actual time.'), findsOneWidget);
    for (final hidden in ['insights_windows', 'insights_planned', 'insights_feelings', 'insights_follow']) {
      expect(find.byKey(Key(hidden)), findsNothing, reason: '$hidden needs more data');
    }
    expect(find.byKey(const Key('insights_week')), findsOneWidget);
    expect(tester.widget<NoyaMotionView>(find.byKey(const Key('insights_noya'))).pose, NoyaState.thinking);
  });

  testWidgets('dark mode at 320dp: no overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = FlowClock().now;
    final state = AppStateProvider()..setTasksForTesting([_done('a', now), _done('b', now), _done('c', now)]);
    await tester.pumpWidget(_host(state, theme: FlowTheme.darkTheme(), width: 320));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
