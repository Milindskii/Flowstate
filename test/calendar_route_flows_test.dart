import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/components/flow_date_strip.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Calendar route flows: the winding path is a journey through the timeline. Every mutation (from Today, Task
/// Detail or Calendar: they all end in the provider) recomputes the route; skips deviate it, recoveries add the
/// orange way back, reschedules and deletes reshape it.
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
  DateTime Function(_Task)? skipMovesTo;

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
      'timeline': [
        for (final t in today)
          _row(t.status == 'completed' ? 'comp-${t.id}' : 'sched-${t.id}', t.id, t.title, t.start,
              minutes: t.minutes, completed: t.status == 'completed')
      ],
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
    if (r.method == 'POST' && path.startsWith('/api/v1/tasks/') && path.endsWith('/complete')) {
      tasks[path.split('/')[path.split('/').length - 2]]?.status = 'completed';
      return http.Response('{}', 200, headers: json);
    }
    if (path.contains('/api/v1/today/skip/')) {
      final id = path.split('/').last;
      final t = tasks[id];
      if (t != null) {
        deviations.add(_row('dev-$id', id, t.title, t.start, deviation: 'skipped'));
        t.start = skipMovesTo?.call(t) ?? _tomorrow.add(const Duration(hours: 9)); // its next window
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
  DayRouteGeometry route(WidgetTester tester) =>
      (tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter).geometry;

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700)); // the road morphs
    await tester.pumpAndSettle();
  }

  testWidgets('1. COMPLETE from Today / Task Detail (provider): the Calendar road turns green', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    expect(route(tester).stopById('sched-B').walked, isFalse);

    // Today's check-off and the Task Detail button both call exactly this
    provider.toggleTaskCompletion('B');
    await settle(tester);
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget);
    expect(route(tester).stopById('sched-B').walked, isTrue);

    // and the authoritative re-read after the server confirmed keeps it
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget);
    expect(route(tester).sampleStates, contains(RouteSegmentState.traveled));
  });

  testWidgets('3. COMPLETE from Calendar: the same mutation, the same road', (tester) async {
    final server = _fourTasks();
    await pump(tester, server);
    await tester.tap(stop('A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar_action_mark_done')));
    await settle(tester);
    expect(find.byKey(const Key('path_check_sched-A')), findsOneWidget);
    expect(route(tester).sampleStates, contains(RouteSegmentState.traveled));
  });

  testWidgets('4. SKIP: the node stays, the road deviates around it', (tester) async {
    final server = _fourTasks();
    server.skipMovesTo = (t) => _at(13);
    final provider = await pump(tester, server);
    final planned = route(tester);
    final home = y(tester, 'B');

    await provider.skipTask('B');
    await settle(tester);
    final g = route(tester);
    expect((y(tester, 'B') - home).abs(), lessThan(0.5), reason: 'the skipped node keeps its slot');
    expect(find.byKey(const Key('path_skipped_sched-B')), findsOneWidget);
    expect(g.stopById('sched-B').role, StopRouteRole.skipped);
    expect(g.distanceToRoute(g.stopById('sched-B').center), greaterThan(30), reason: 'the road passes beside B');
    expect(g.sameRoute(planned), isFalse);
    expect(g.detours, isEmpty);
  });

  testWidgets('5-6. RECOVER then COMPLETE: the orange way back appears and stays as history', (tester) async {
    final server = _fourTasks();
    server.skipMovesTo = (t) => _at(13);
    final provider = await pump(tester, server);
    await provider.skipTask('B');
    await settle(tester);

    provider.setPreferredActiveTask('B'); // "Do this now" on the skipped stop
    await settle(tester);
    var g = route(tester);
    expect(g.stopById('sched-B').role, StopRouteRole.recovering);
    expect(g.detours.map((d) => d.stopId), ['sched-B'], reason: 'an orange path travels back to B');
    expect(g.sampleStates, contains(RouteSegmentState.recovered));
    expect(find.byKey(const Key('path_recovering_sched-B')), findsOneWidget);

    provider.toggleTaskCompletion('B');
    await settle(tester);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    g = route(tester);
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget);
    expect(g.stopById('sched-B').role, StopRouteRole.recovered);
    expect(g.detours.map((d) => d.stopId), ['sched-B'], reason: 'completing it keeps the deviation history');
    expect(g.stopById('sched-B').deviated, isTrue);
    expect(find.textContaining('Recovered'), findsOneWidget);
  });

  testWidgets('7. REPLAN TIME: moving a task in time changes the road', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    final before = route(tester);

    await provider.rescheduleTask('B', targetDate: _day, targetTime: const TimeOfDay(hour: 14, minute: 0));
    await settle(tester);
    final after = route(tester);
    expect(after.stops.map((s) => s.id), ['sched-A', 'sched-C', 'sched-D', 'sched-B']);
    expect(after.sameRoute(before), isFalse);
    expect(after.height, isNot(before.height), reason: 'a 3h gap lengthens the road');
  });

  testWidgets('8. DELETE: the node leaves and the road closes around it', (tester) async {
    final server = _fourTasks();
    final provider = await pump(tester, server);
    final before = route(tester);
    provider.removeTask('B');
    await settle(tester);
    final after = route(tester);
    expect(stop('B'), findsNothing);
    expect(after.stops.map((s) => s.id), ['sched-A', 'sched-C', 'sched-D']);
    expect(after.height, lessThan(before.height));
    for (final s in after.stops) {
      expect(after.distanceToRoute(s.center), lessThan(0.5));
    }
  });

  testWidgets('9. SWITCH DATES repeatedly: no RenderBox assertion, the route follows the selected day', (tester) async {
    final server = _fourTasks();
    server.tasks['E'] = _Task('E', 'Task E', _tomorrow.add(const Duration(hours: 9)));
    final provider = await pump(tester, server);
    for (var i = 0; i < 12; i++) {
      final target = i.isEven ? _tomorrow : _day;
      unawaited(provider.loadCalendarDay(target));
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(const Duration(milliseconds: 120));
    }
    await provider.loadCalendarDay(_day);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FlowDateStrip), findsOneWidget);
    expect(stop('A'), findsOneWidget);
    expect(route(tester).stops.map((s) => s.id), ['sched-A', 'sched-B', 'sched-C', 'sched-D']);
  });

  testWidgets('10. BACKGROUND / RESUME: state and route stay correct', (tester) async {
    final server = _fourTasks();
    server.skipMovesTo = (t) => _at(13);
    final provider = await pump(tester, server);
    await provider.skipTask('B');
    provider.setPreferredActiveTask('B');
    await settle(tester);
    final before = route(tester);

    provider.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 30));
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await settle(tester);
    final after = route(tester);
    expect(tester.takeException(), isNull);
    expect(after.stops.map((s) => s.id), before.stops.map((s) => s.id));
    expect(after.stopById('sched-B').deviated, isTrue, reason: 'the skip survives a resume');
    expect(after.detours.map((d) => d.stopId), ['sched-B']);
  });
}
