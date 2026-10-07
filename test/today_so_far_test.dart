import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/today_so_far.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_theme.dart';

TaskItem _t(String id, String title, {bool done = false, DateTime? completedAt}) => TaskItem(
      id: id,
      title: title,
      durationMinutes: 45,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isCompleted: done,
      completedAt: completedAt,
      scheduledStart: DateTime(FlowClock().now.year, FlowClock().now.month, FlowClock().now.day, 7),
    );

Widget _host(AppStateProvider state, {ThemeData? theme, double width = 412}) => MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: ChangeNotifierProvider<AppStateProvider>.value(
          value: state,
          child: const Scaffold(body: Padding(padding: EdgeInsets.all(16), child: TodaySoFar())),
        ),
      ),
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows finished moments with a check, time and feeling; tap opens their history', (tester) async {
    final now = FlowClock().now;
    final at = DateTime(now.year, now.month, now.day, 8, 5);
    final state = AppStateProvider()
      ..setTasksForTesting([
        _t('gym', 'Gym', done: true, completedAt: at),
        _t('read', 'Read', done: true, completedAt: DateTime(now.year, now.month, now.day, 9, 10)),
        _t('open', 'Open task'),
      ]);
    await state.reflectionsReady;
    state.recordTaskFeedback(taskId: 'gym', actualMinutes: 40, feeling: 4, energyScore: 5, focusScore: 4, difficultyScore: 3, distractionScore: 1, completedAt: at);

    await tester.pumpWidget(_host(state));
    expect(find.byKey(const Key('today_so_far')), findsOneWidget);
    expect(find.text('Today so far'), findsOneWidget);
    expect(find.byKey(const Key('today_moment_open')), findsNothing);

    final gym = find.byKey(const Key('today_moment_gym'));
    // A quiet check per moment, not a Noya per task.
    expect(find.descendant(of: gym, matching: find.byIcon(Icons.check_rounded)), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsNothing);
    expect(find.descendant(of: gym, matching: find.text('8:05 AM · On fire')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('today_moment_read')), matching: find.text('9:10 AM')), findsOneWidget);

    // Most recent first.
    expect(tester.getTopLeft(find.byKey(const Key('today_moment_read'))).dx,
        lessThan(tester.getTopLeft(gym).dx));

    await tester.tap(gym);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history_moment_sheet')), findsOneWidget);
    expect(find.byKey(const Key('history_signal_energy_5')), findsOneWidget);
  });

  testWidgets('nothing finished yet: no strip', (tester) async {
    final state = AppStateProvider()..setTasksForTesting([_t('open', 'Open task')]);
    await tester.pumpWidget(_host(state));
    expect(find.byKey(const Key('today_so_far')), findsNothing);
  });

  testWidgets('dark mode at 320dp: no overflow', (tester) async {
    final now = FlowClock().now;
    final state = AppStateProvider()
      ..setTasksForTesting([_t('gym', 'A long finished task title that wraps', done: true, completedAt: DateTime(now.year, now.month, now.day, 8))]);
    await tester.pumpWidget(_host(state, theme: FlowTheme.darkTheme(), width: 320));
    expect(tester.takeException(), isNull);
  });
}
