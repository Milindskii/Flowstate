import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

final DateTime _base = DateTime.now().toUtc();

Map<String, dynamic> _row(
  String id,
  String task,
  String title,
  double hours, {
  bool completed = false,
  bool missed = false,
  String? deviation,
  int minutes = 30,
}) {
  final start = _base.add(Duration(minutes: (hours * 60).round()));
  final local = start.toLocal();
  return {
    'id': id,
    'task_id': task,
    'title': title,
    'start_time': start.toIso8601String(),
    'end_time': start.add(Duration(minutes: minutes)).toIso8601String(),
    'time': '${local.hour % 12 == 0 ? 12 : local.hour % 12}:${local.minute.toString().padLeft(2, '0')}',
    'period': local.hour >= 12 ? 'PM' : 'AM',
    'duration_minutes': minutes,
    'type': 'deep_work',
    'tag_text': deviation != null ? deviation.toUpperCase() : (completed ? 'COMPLETED' : 'DEEP WORK'),
    'is_completed': completed,
    'is_missed': missed,
    'state': deviation ?? (completed ? 'completed' : (missed ? 'missed' : 'scheduled')),
    if (deviation != null) 'deviation': deviation,
    if (deviation == 'skipped' || deviation == 'deferred') 'is_skipped': true,
  };
}

String _dayJson(List<Map<String, dynamic>> timeline, [List<Map<String, dynamic>> deviations = const []]) => jsonEncode({
      'date': '2026-10-09',
      'is_today': true,
      'is_past': false,
      'timeline': timeline,
      'fixed_commitments': [],
      'completed_tasks': [for (final t in timeline) if (t['is_completed'] == true) t],
      'remaining_tasks': [],
      'unscheduled_tasks': [],
      'deviations': deviations,
      'conflicts': [],
    });

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  group('Calendar Skipped Node Interaction', () {
    testWidgets('skipped nodes on both sides of winding path and at different vertical positions are interactive', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.resetPhysicalSize);

      // 5 tasks: DSA revision (skipped, left/right), test (skipped), Gym session (skipped), plus active & completed
      final timeline = [
        _row('sched-wake', 'wake', 'Morning routine', 1, completed: true),
        _row('sched-work', 'work', 'Deep coding', 5),
      ];
      final deviations = [
        _row('dev-dsa', 'dsa', 'DSA revision', 2, deviation: 'skipped', minutes: 45),
        _row('dev-test', 'test', 'Physics test', 3, deviation: 'skipped', minutes: 60),
        _row('dev-gym', 'gym', 'Gym session', 4, deviation: 'skipped', minutes: 50),
      ];

      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(_dayJson(timeline, deviations), 200, headers: {'content-type': 'application/json'})),
        ),
      );

      // Add corresponding tasks in provider so taskBehind and actions are available
      provider.setTasksForTesting(const [
        TaskItem(id: 'dsa', title: 'DSA revision', durationMinutes: 45, difficulty: TaskDifficulty.high),
        TaskItem(id: 'test', title: 'Physics test', durationMinutes: 60, difficulty: TaskDifficulty.medium),
        TaskItem(id: 'gym', title: 'Gym session', durationMinutes: 50, difficulty: TaskDifficulty.light),
        TaskItem(id: 'wake', title: 'Morning routine', durationMinutes: 30, difficulty: TaskDifficulty.light),
        TaskItem(id: 'work', title: 'Deep coding', durationMinutes: 60, difficulty: TaskDifficulty.high),
      ]);

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      // Verify all skipped nodes are present with their skipped styling
      expect(find.byKey(const Key('path_skipped_sched-dsa')), findsOneWidget);
      expect(find.byKey(const Key('path_skipped_sched-test')), findsOneWidget);
      expect(find.byKey(const Key('path_skipped_sched-gym')), findsOneWidget);

      // 1. Tap DSA revision node -> opens task details with correct task, time, duration, and Skipped status
      final dsaNode = find.byKey(const Key('path_node_sched-dsa'));
      expect(dsaNode, findsOneWidget);
      await tester.tap(dsaNode);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.text('DSA revision')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('45 min')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('Skipped')), findsOneWidget);

      // Verify existing recovery and editing actions are preserved in popup
      expect(find.byKey(const Key('calendar_action_do_now')), findsOneWidget);
      expect(find.byKey(const Key('calendar_action_mark_done')), findsOneWidget);
      expect(find.byKey(const Key('calendar_action_edit')), findsOneWidget);
      // Skip for now is not present because already skipped
      expect(find.byKey(const Key('calendar_action_skip')), findsNothing);

      // Dismiss popup
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);

      // 2. Tap Physics test node (different vertical position & side of winding path)
      final testNode = find.byKey(const Key('path_node_sched-test'));
      expect(testNode, findsOneWidget);
      await tester.tap(testNode);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.text('Physics test')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('60 min')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('Skipped')), findsOneWidget);

      // Dismiss popup
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);

      // 3. Tap Gym session node (different vertical position)
      final gymNode = find.byKey(const Key('path_node_sched-gym'));
      expect(gymNode, findsOneWidget);
      await tester.tap(gymNode);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.text('Gym session')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('50 min')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('Skipped')), findsOneWidget);

      // Verify recovery action exists for Gym session
      expect(find.byKey(const Key('calendar_action_mark_done')), findsOneWidget);

      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);
    });

    testWidgets('entire visible node icon/ring is tappable (not just central icon)', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.resetPhysicalSize);

      final timeline = [_row('sched-work', 'work', 'Deep coding', 3)];
      final deviations = [_row('dev-dsa', 'dsa', 'DSA revision', 1, deviation: 'skipped')];

      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(_dayJson(timeline, deviations), 200, headers: {'content-type': 'application/json'})),
        ),
      );

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      final nodeFinder = find.byKey(const Key('path_node_sched-dsa'));
      final nodeCenter = tester.getCenter(nodeFinder);
      final nodeSize = tester.getSize(nodeFinder);

      // Tap near outer edge of node ring (e.g. 16dp to the right of center)
      final ringOffset = nodeCenter + const Offset(16, 0);
      await tester.tapAt(ringOffset);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);

      // Tap near badge corner of node (bottom-right)
      final badgeOffset = nodeCenter + Offset(nodeSize.width * 0.3, nodeSize.height * 0.3);
      await tester.tapAt(badgeOffset);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
    });

    testWidgets('text labels are tappable and do not block node interaction', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.resetPhysicalSize);

      final timeline = [_row('sched-work', 'work', 'Deep coding', 3)];
      final deviations = [_row('dev-dsa', 'dsa', 'DSA revision', 1, deviation: 'skipped')];

      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(_dayJson(timeline, deviations), 200, headers: {'content-type': 'application/json'})),
        ),
      );

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      // Tap the label text directly
      final labelFinder = find.text('DSA revision');
      expect(labelFinder, findsOneWidget);
      await tester.tap(labelFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping decorative road segments does not open the wrong task', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.resetPhysicalSize);

      final timeline = [
        _row('sched-A', 'A', 'Task Alpha', 1),
        _row('sched-C', 'C', 'Task Charlie', 5),
      ];
      final deviations = [
        _row('dev-B', 'B', 'Task Bravo', 3, deviation: 'skipped'),
      ];

      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(_dayJson(timeline, deviations), 200, headers: {'content-type': 'application/json'})),
        ),
      );

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      final stopA = tester.getCenter(find.byKey(const Key('path_stop_sched-A')));
      final stopB = tester.getCenter(find.byKey(const Key('path_stop_sched-B')));
      final stopC = tester.getCenter(find.byKey(const Key('path_stop_sched-C')));

      // 1. Tap road segment in the vertical gap between Stop A and Stop B
      final midRoadPointAB = Offset(stopA.dx, (stopA.dy + stopB.dy) / 2);
      await tester.tapAt(midRoadPointAB);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);

      // 2. Tap road segment in the vertical gap between Stop B and Stop C
      final midRoadPointBC = Offset(stopB.dx, (stopB.dy + stopC.dy) / 2);
      await tester.tapAt(midRoadPointBC);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);
    });

    testWidgets('completed, missed, deferred and open nodes remain interactive', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
      addTearDown(tester.view.resetPhysicalSize);

      final timeline = [
        _row('sched-done', 'done', 'Done task', 1, completed: true),
        _row('sched-open', 'open', 'Open task', 2),
        _row('sched-missed', 'missed', 'Missed task', 3, missed: true),
      ];
      final deviations = [
        _row('dev-def', 'def', 'Later review', 4, deviation: 'deferred'),
      ];

      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(_dayJson(timeline, deviations), 200, headers: {'content-type': 'application/json'})),
        ),
      );

      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      // Open node is interactive
      await tester.tap(find.byKey(const Key('path_node_sched-open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();

      // Missed node is interactive
      await tester.tap(find.byKey(const Key('path_node_sched-missed')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();

      // Deferred node is interactive and has Deferred badge
      await tester.tap(find.byKey(const Key('path_node_sched-def')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.text('Later review')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('calendar_stop_sheet')), matching: find.textContaining('Deferred')), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();

      // Completed node is interactive (opens history moment sheet)
      await tester.tap(find.byKey(const Key('path_node_sched-done')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_moment_sheet')), findsOneWidget);
    });
  });
}
