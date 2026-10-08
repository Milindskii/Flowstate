import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/screens/insights_history_screen.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// "Focus Time" is time spent in real Focus sessions (the Flow overview's server-timed total). It is NOT the length of
/// the tasks that were finished, and nothing is invented when there is no data.
TaskItem finished(String id, {int? minutes, String? plannedDay}) {
  final n = FlowClock().now;
  final day = plannedDay ?? '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  return TaskItem.fromJson({
    'id': id,
    'title': 'Task $id',
    'status': 'completed',
    if (minutes != null) 'estimated_minutes': minutes,
    'planned_date': day,
    'completed_at': DateTime(n.year, n.month, n.day, 11).toUtc().toIso8601String(),
  });
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  Future<void> open(WidgetTester tester, List<TaskItem> tasks, {int focusMinutes = 0}) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = AppStateProvider()..setTasksForTesting(tasks);
    await state.reflectionsReady;
    final flow = FlowProvider(api: ApiService())
      ..setOverviewForTesting(FlowOverview.fromJson({
        'personal_progress': {'total_focus_minutes': focusMinutes},
      }));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: state),
        ChangeNotifierProvider<FlowProvider>.value(value: flow),
      ],
      child: const MaterialApp(home: InsightsHistoryScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder tile(String label) => find.ancestor(of: find.text(label), matching: find.byType(Column)).first;

  testWidgets('tasks finished but Focus never used: Focus Time is unavailable, not the sum of task lengths', (tester) async {
    await open(tester, [finished('a', minutes: 60), finished('b', minutes: 90)]); // 2h30 of planned work
    expect(find.text('Focus Time'), findsOneWidget);
    expect(find.descendant(of: tile('Focus Time'), matching: find.text('2h 30m')), findsNothing);
    expect(find.descendant(of: tile('Focus Time'), matching: find.text('—')), findsOneWidget);
    expect(find.byKey(const Key('history_focus_empty_note')), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'the finished count is still shown');
  });

  testWidgets('real Focus sessions are what Focus Time shows', (tester) async {
    await open(tester, [finished('a', minutes: 60)], focusMinutes: 75);
    expect(find.descendant(of: tile('Focus Time'), matching: find.text('1h 15m')), findsOneWidget);
    expect(find.byKey(const Key('history_focus_empty_note')), findsNothing);
  });

  testWidgets('a task with no recorded length is not given an invented 25 minutes', (tester) async {
    await open(tester, [finished('a').copyWith(durationMinutes: 0)]);
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.textContaining('25 min'), findsNothing);
  });

  test('History entries carry 0 minutes (unknown), not 25, when nothing was recorded', () {
    final days = HistoryDay.from(tasks: [finished('a').copyWith(durationMinutes: 0)], reflections: const []);
    expect(days.single.entries.single.minutes, 0);
    expect(days.single.totalMinutes, 0);
  });
}
