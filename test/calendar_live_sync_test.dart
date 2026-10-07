import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Calendar live-sync regression: the Calendar always shows the live task state.
///
/// The fake server is stateful (tasks, day render, history nodes) and every write can be HELD, so each test
/// asserts what the user sees while the request is still in flight: a deleted/added/moved task must change on
/// screen at once, not after the network (and not only after navigating away and back).
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

DateTime _at(int h, [int m = 0]) => DateTime(_day.year, _day.month, _day.day, h, m);
DateTime get _tomorrow => _day.add(const Duration(days: 1));

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Task {
  String id;
  String title;
  DateTime start;
  final int minutes = 30;
  String status = 'todo';
  _Task(this.id, this.title, this.start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'duration_minutes': minutes,
        'estimated_minutes': minutes,
        'difficulty': 'high',
        'task_type': 'deep_work',
        'status': status,
        'scheduled_start': start.toUtc().toIso8601String(),
        'scheduled_end': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
        'planned_date': _ymd(start),
        'time_locked': false,
      };
}

Map<String, dynamic> _row(String id, String task, String title, DateTime start,
    {int minutes = 30, bool completed = false, DateTime? anchor, String? deviation}) {
  final h12 = start.hour % 12 == 0 ? 12 : start.hour % 12;
  return {
    'id': id,
    'task_id': task,
    'title': title,
    'start_time': start.toUtc().toIso8601String(),
    'end_time': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
    'time': '$h12:${start.minute.toString().padLeft(2, '0')}',
    'period': start.hour >= 12 ? 'PM' : 'AM',
    'duration_minutes': minutes,
    'type': 'deep_work',
    'tag_text': deviation != null ? deviation.toUpperCase() : (completed ? 'COMPLETED' : 'DEEP WORK'),
    'is_completed': completed,
    'state': deviation ?? (completed ? 'completed' : 'scheduled'),
    if (anchor != null) 'anchor_start': anchor.toUtc().toIso8601String(),
    if (deviation != null) 'deviation': deviation,
    if (deviation == 'skipped') 'is_skipped': true,
  };
}

class _Server {
  final Map<String, _Task> tasks = {};
  final List<Map<String, dynamic>> deviations = [];
  String? dayOverride;
  int dayGets = 0;
  int nextId = 1;

  /// A completer here holds that request until the test releases it.
  Completer<void>? deleteGate, createGate, patchGate, dayGate;
  /// What POST /calendar/apply-replan does to the stored tasks (and which rows it reports).
  List<Map<String, dynamic>> Function()? onApply;

  _Server(List<_Task> initial) {
    for (final t in initial) {
      tasks[t.id] = t;
    }
  }

  String dayBody() {
    if (dayOverride != null) return dayOverride!;
    final today = tasks.values
        .where((t) => t.status != 'cancelled' && _ymd(t.start) == _ymd(_day))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return jsonEncode({
      'date': _ymd(_day),
      'is_today': true,
      'is_past': false,
      'timeline': [for (final t in today) _row('sched-${t.id}', t.id, t.title, t.start, minutes: t.minutes)],
      'fixed_commitments': [],
      'completed_tasks': [],
      'remaining_tasks': [],
      'unscheduled_tasks': [],
      'deviations': deviations,
      'conflicts': [],
    });
  }

  Future<http.Response> handle(http.Request r) async {
    final json = {'content-type': 'application/json'};
    final path = r.url.path;
    if (path.endsWith('/api/v1/calendar/day')) {
      dayGets++;
      final body = dayBody(); // what the server holds when the request ARRIVES
      if (dayGate != null) await dayGate!.future;
      return http.Response(body, 200, headers: json);
    }
    if (path.endsWith('/api/v1/calendar/apply-replan')) {
      final rows = onApply?.call() ?? [];
      return http.Response(
          jsonEncode({'success': true, 'updated_count': rows.length, 'persisted_tasks': rows}), 200, headers: json);
    }
    if (path.contains('/api/v1/today/skip/')) {
      final id = path.split('/').last;
      final t = tasks[id];
      if (t != null) {
        deviations.add(_row('dev-$id', id, t.title, t.start, deviation: 'skipped'));
        t.start = _tomorrow.add(const Duration(hours: 9)); // moved to its next window, on a later day
      }
      return http.Response(jsonEncode({'recorded': true, 'next_window': null, 'message': 'Skipped.'}), 200,
          headers: json);
    }
    if (r.method == 'DELETE' && path.startsWith('/api/v1/tasks/')) {
      if (deleteGate != null) await deleteGate!.future;
      tasks.remove(path.split('/').last);
      return http.Response('{}', 200, headers: json);
    }
    if (r.method == 'POST' && path == '/api/v1/tasks') {
      if (createGate != null) await createGate!.future;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final start = DateTime.parse(body['scheduled_start'].toString()).toLocal();
      final t = _Task('srv-${nextId++}', body['title'] as String, start);
      tasks[t.id] = t;
      return http.Response(jsonEncode(t.toJson()), 200, headers: json);
    }
    if (r.method == 'PATCH' && path.startsWith('/api/v1/tasks/')) {
      if (patchGate != null) await patchGate!.future;
      final t = tasks[path.split('/').last]!;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final before = t.start;
      if (body['scheduled_start'] != null) t.start = DateTime.parse(body['scheduled_start'].toString()).toLocal();
      if (_ymd(before) == _ymd(_day) && _ymd(t.start) != _ymd(_day)) {
        // moved off today: the server keeps the old slot as history
        deviations.add(_row('dev-${t.id}', t.id, t.title, before, deviation: 'deferred'));
      }
      return http.Response(jsonEncode(t.toJson()), 200, headers: json);
    }
    if (r.method == 'GET' && path == '/api/v1/tasks') {
      return http.Response(jsonEncode({'items': [for (final t in tasks.values) t.toJson()], 'total': tasks.length}),
          200, headers: json);
    }
    return http.Response('{}', 200, headers: json);
  }
}

const _user = AuthUser(id: 'user-cal', email: 'cal@flowstate.local', name: 'C', onboardingCompleted: true);

_Server _fourTasks() => _Server([
      _Task('A', 'Task A', _at(8)),
      _Task('B', 'Task B', _at(9)),
      _Task('C', 'Task C', _at(10)),
      _Task('D', 'Task D', _at(11)),
    ]);

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    FlowClock.debugNowOverride = () => _at(7, 30);
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  Future<AppStateProvider> pump(WidgetTester tester, _Server server) async {
    final provider = AppStateProvider(customApi: ApiService(client: MockClient(server.handle)), initialUser: _user);
    provider.setOnboardingCompleteForTesting(true);
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();
    return provider;
  }

  Finder stop(String id) => find.byKey(Key('path_stop_sched-$id'));
  double y(WidgetTester tester, String id) => tester.getCenter(stop(id)).dy;
  List<String> order(WidgetTester tester, List<String> ids) {
    final present = ids.where((id) => stop(id).evaluate().isNotEmpty).toList();
    present.sort((a, b) => y(tester, a).compareTo(y(tester, b)));
    return present;
  }

  testWidgets('1. DELETE through the real UI: the node leaves the running Calendar at once', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'B', 'C', 'D']);

    server.deleteGate = Completer<void>(); // the DELETE request is still in flight for the whole check
    await tester.tap(stop('C'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_action_edit')));
    await tester.pumpAndSettle();
    final deleteButton = find.text('Delete Task').last;
    await tester.ensureVisible(deleteButton);
    await tester.tap(deleteButton);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(stop('C'), findsNothing, reason: 'deleted node is gone while the server has not answered yet');
    expect(find.descendant(of: find.byKey(const Key('flow_day_path_line')), matching: find.text('Task C')), findsNothing);
    expect(order(tester, ['A', 'B', 'D']), ['A', 'B', 'D']);
    expect(provider.tasks.any((t) => t.id == 'C'), isFalse);

    // a background re-read (clock tick / resume) while the DELETE is pending still has C on the server: it must
    // not bring the node back
    await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
    await tester.pump();
    expect(stop('C'), findsNothing, reason: 'a read that raced the delete cannot resurrect it');
    expect(server.tasks.containsKey('C'), isTrue, reason: 'precondition: the server really still had it');

    server.deleteGate!.complete();
    await tester.pumpAndSettle();
    expect(stop('C'), findsNothing);
    expect(server.tasks.containsKey('C'), isFalse);
    expect(order(tester, ['A', 'B', 'D']), ['A', 'B', 'D']);
  });

  testWidgets('1b. a failed DELETE puts the node back and says so', (tester) async {
    final server = _fourTasks();
    final reject = Completer<void>();
    final failing = AppStateProvider(
      customApi: ApiService(client: MockClient((r) async {
        if (r.method == 'DELETE') {
          await reject.future;
          return http.Response('{"detail":"boom"}', 500);
        }
        return server.handle(r);
      })),
      initialUser: _user,
    );
    failing.setOnboardingCompleteForTesting(true);
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: failing)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();

    failing.removeTask('C');
    await tester.pump();
    expect(stop('C'), findsNothing, reason: 'gone at once, before the server has answered');
    reject.complete();
    await tester.pumpAndSettle();
    expect(stop('C'), findsOneWidget, reason: 'the server kept it, so Calendar shows it again');
    expect(failing.lastSyncError, isNotNull);
  });

  testWidgets('2. ADD: the new node is on Calendar before the server answers, once afterwards', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);

    server.createGate = Completer<void>();
    final created = provider.addTask(
      title: 'Brand New',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      scheduledStart: _at(9, 30),
      scheduledEnd: _at(10),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Brand New'), findsOneWidget, reason: 'visible while the create request is in flight');
    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'B', 'C', 'D']);

    server.createGate!.complete();
    await created;
    await tester.pumpAndSettle();
    expect(find.text('Brand New'), findsOneWidget, reason: 'no duplicate node once the saved task arrives');
    expect(provider.tasks.where((t) => t.title == 'Brand New'), hasLength(1));
  });

  testWidgets('3. RESCHEDULE: the node takes its new place at once', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'B', 'C', 'D']);

    server.patchGate = Completer<void>();
    final done = provider.rescheduleTask('A', targetDate: _day, targetTime: const TimeOfDay(hour: 12, minute: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(order(tester, ['A', 'B', 'C', 'D']), ['B', 'C', 'D', 'A'], reason: 'A is last the moment it moves to 12:00');
    expect(find.text('Task A'), findsOneWidget);

    server.patchGate!.complete();
    await done;
    await tester.pumpAndSettle();
    expect(order(tester, ['A', 'B', 'C', 'D']), ['B', 'C', 'D', 'A']);
    expect(find.text('Task A'), findsOneWidget);
  });

  testWidgets('4. REPLAN: the applied plan is on Calendar before the day is re-read; nothing stale or doubled',
      (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);

    // Replan: B moves to 12:00, C is cancelled, an urgent task N appears at 9:30
    server.onApply = () {
      server.tasks['B']!.start = _at(12);
      server.tasks['C']!.status = 'cancelled';
      final n = _Task('N', 'Urgent N', _at(9, 30));
      server.tasks['N'] = n;
      return [server.tasks['B']!.toJson(), server.tasks['C']!.toJson(), n.toJson()];
    };
    server.dayGate = Completer<void>(); // the post-apply day read is still pending
    final diff = PlanDiff(
      planId: 'p1',
      selectedDate: _ymd(_day),
      movedTasks: const [TaskDiffItem(taskId: 'B', title: 'Task B', changeType: 'moved')],
      cancelledTasks: const [TaskDiffItem(taskId: 'C', title: 'Task C', changeType: 'cancelled')],
      // the server's apply payload says B was explicitly moved (a skip/defer would keep its stop in place)
      serverApplyRequest: const ApplyReplanRequest(
        planId: 'p1',
        selectedDate: '',
        taskUpdates: [],
        newTasks: [],
        cancelledTaskIds: ['C'],
        raw: {'intents': {'B': 'rescheduled'}},
      ),
    );
    final applied = provider.applyReplan(diff);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(stop('C'), findsNothing, reason: 'the cancelled task is gone');
    expect(find.text('Task B'), findsOneWidget);
    expect(find.text('Urgent N'), findsOneWidget);
    expect(order(tester, ['A', 'B', 'C', 'D', 'N']), ['A', 'N', 'D', 'B'], reason: 'new plan order, drawn pre-reload');

    server.dayGate!.complete();
    await applied;
    await tester.pumpAndSettle();
    expect(order(tester, ['A', 'B', 'C', 'D', 'N']), ['A', 'N', 'D', 'B']);
    expect(find.text('Task B'), findsOneWidget);
    expect(find.text('Urgent N'), findsOneWidget);
    expect(find.text('Task C'), findsNothing);
  });

  testWidgets('5. SKIP: the skipped node keeps its place while another task is deleted', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    final home = {for (final id in ['A', 'B', 'C']) id: y(tester, id)};

    await provider.skipTask('B'); // B moves to tomorrow on the server; today keeps its stop as history
    await tester.pumpAndSettle();
    expect(stop('B'), findsOneWidget, reason: 'skipped is not deleted');
    for (final id in ['A', 'B', 'C']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5), reason: '$id did not move');
    }

    server.deleteGate = Completer<void>();
    provider.removeTask('D'); // another task changes: the skipped node must not move
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(stop('D'), findsNothing);
    for (final id in ['A', 'B', 'C']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5), reason: '$id still did not move');
    }
    server.deleteGate!.complete();
    await tester.pumpAndSettle();
    for (final id in ['A', 'B', 'C']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5));
    }
  });

  testWidgets('6. DEFER: the deferred node keeps its place immediately and after the server answers', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    final home = {for (final id in ['A', 'B', 'C', 'D']) id: y(tester, id)};

    server.patchGate = Completer<void>();
    final done = provider.deferTaskToLater('C', nextWindow: _tomorrow.add(const Duration(hours: 10)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(stop('C'), findsOneWidget, reason: 'a defer is not a delete: the stop stays until the server speaks');
    expect((y(tester, 'C') - home['C']!).abs(), lessThan(0.5));

    server.patchGate!.complete();
    await done;
    await tester.pumpAndSettle();
    expect(stop('C'), findsOneWidget, reason: 'now it is the deferred history node, same key, same place');
    for (final id in ['A', 'B', 'C', 'D']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5), reason: '$id did not move');
    }
  });

  testWidgets('7. RECOVER: the recovered task returns to its original node, even with another task deleted',
      (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    final home = {for (final id in ['A', 'B', 'C']) id: y(tester, id)};

    server.deviations.add(_row('dev-B', 'B', 'Task B', _at(9), deviation: 'skipped'));
    server.dayOverride = jsonEncode({
      'date': _ymd(_day),
      'is_today': true,
      'is_past': false,
      'timeline': [
        _row('sched-A', 'A', 'Task A', _at(8)),
        _row('sched-C', 'C', 'Task C', _at(10)),
        _row('sched-D', 'D', 'Task D', _at(11)),
      ],
      'deviations': server.deviations,
    });
    await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
    await tester.pumpAndSettle();
    expect((y(tester, 'B') - home['B']!).abs(), lessThan(0.5), reason: 'skipped');

    // B is brought back and finished later in the day
    server.dayOverride = jsonEncode({
      'date': _ymd(_day),
      'is_today': true,
      'is_past': false,
      'timeline': [
        _row('sched-A', 'A', 'Task A', _at(8)),
        _row('comp-B', 'B', 'Task B', _at(13), completed: true, anchor: _at(9)),
        _row('sched-C', 'C', 'Task C', _at(10)),
        _row('sched-D', 'D', 'Task D', _at(11)),
      ],
      'deviations': server.deviations,
    });
    await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget, reason: 'drawn done');
    for (final id in ['A', 'B', 'C']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5), reason: '$id: B recovered on its original node');
    }

    provider.removeTask('D');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (final id in ['A', 'B', 'C']) {
      expect((y(tester, id) - home[id]!).abs(), lessThan(0.5), reason: '$id unchanged after another delete');
    }
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget);
  });

  testWidgets('8. APP RESUME: the latest persisted day is loaded, once', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);

    // changed elsewhere (another device): B removed, E added
    server.tasks.remove('B');
    server.tasks['E'] = _Task('E', 'Task E', _at(14));
    final before = server.dayGets;
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(stop('B'), findsNothing);
    expect(stop('E'), findsOneWidget);
    expect(server.dayGets - before, 1, reason: 'one day request, no rebuild loop');

    provider.didChangeAppLifecycleState(AppLifecycleState.resumed); // flapping resume inside 20 s: ignored
    await tester.pumpAndSettle();
    expect(server.dayGets - before, 1);
  });
}
