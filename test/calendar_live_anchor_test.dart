import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Calendar follows the clock on its own and its stops never move (manual verification 2026-10-06).
///
/// A 8:00-8:30, B 9:00-9:30, C 10:00-10:30, D 11:00-11:30 today. When 8:30 passes without A being done, A is
/// bypassed, B becomes the target, without the user pressing anything and without a skip being written.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

DateTime _at(int h, [int m = 0]) => DateTime(_day.year, _day.month, _day.day, h, m);

Map<String, dynamic> _row(String id, String task, String title, DateTime start,
    {int minutes = 30, bool completed = false, bool suggested = false, DateTime? anchor, String? deviation}) {
  final period = start.hour >= 12 ? 'PM' : 'AM';
  final h12 = start.hour % 12 == 0 ? 12 : start.hour % 12;
  return {
    'id': id,
    'task_id': task,
    'title': title,
    'start_time': start.toUtc().toIso8601String(),
    'end_time': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
    'time': '$h12:${start.minute.toString().padLeft(2, '0')}',
    'period': period,
    'duration_minutes': minutes,
    'type': 'deep_work',
    'tag_text': deviation != null ? deviation.toUpperCase() : (completed ? 'COMPLETED' : 'DEEP WORK'),
    'is_completed': completed,
    'is_suggested': suggested,
    'state': deviation ?? (completed ? 'completed' : 'scheduled'),
    if (anchor != null) 'anchor_start': anchor.toUtc().toIso8601String(),
    if (deviation != null) 'deviation': deviation,
    if (deviation == 'skipped') 'is_skipped': true,
  };
}

String _dayJson(List<Map<String, dynamic>> timeline,
        {List<Map<String, dynamic>> deviations = const [], Map<String, dynamic>? dayComplete}) =>
    jsonEncode({
      'date': '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}',
      'is_today': true,
      'is_past': false,
      'timeline': timeline,
      'fixed_commitments': [],
      'completed_tasks': [for (final t in timeline) if (t['is_completed'] == true) t],
      'remaining_tasks': [],
      'unscheduled_tasks': [],
      'deviations': deviations,
      'conflicts': [],
      if (dayComplete != null) 'day_complete': dayComplete,
    });

class _Server {
  String body;
  int dayGets = 0;
  final List<String> posts = [];
  _Server(this.body);

  Future<http.Response> handle(http.Request r) async {
    final json = {'content-type': 'application/json'};
    if (r.url.path.endsWith('/api/v1/calendar/day')) {
      dayGets++;
      return http.Response(body, 200, headers: json);
    }
    if (r.method == 'POST') {
      posts.add(r.url.path);
      if (r.url.path.endsWith('/api/v1/flow/day-complete/claim')) {
        return http.Response(jsonEncode({'date': 'x', 'claimed': true, 'already_claimed': false, 'xp_awarded': 25,
          'companion_xp': 125, 'level': 2, 'leveled_up': false}), 200, headers: json);
      }
      if (r.url.path.contains('/api/v1/today/skip/')) {
        return http.Response(jsonEncode({'recorded': true, 'next_window': null, 'message': 'Skipped.'}), 200, headers: json);
      }
      return http.Response('{}', 200, headers: json);
    }
    if (r.url.path.endsWith('/api/v1/tasks')) return http.Response('{"items": [], "total": 0}', 200, headers: json);
    return http.Response('{}', 200, headers: json);
  }
}

const _user = AuthUser(id: 'user-cal', email: 'cal@flowstate.local', name: 'C', onboardingCompleted: true);

void main() {
  late DateTime clock;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    clock = _at(8, 20);
    FlowClock.debugNowOverride = () => clock;
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

  Finder stop(String id) => find.byKey(Key('path_stop_$id'));

  // a stop's place ON the path (independent of where the screen is scrolled to show the current target)
  Offset onPath(WidgetTester tester, String id) =>
      tester.getCenter(stop(id)) - tester.getTopLeft(find.byKey(const Key('flow_day_path_line')));

  List<Map<String, dynamic>> plan() => [
        _row('sched-A', 'A', 'Task A', _at(8)),
        _row('sched-B', 'B', 'Task B', _at(9)),
        _row('sched-C', 'C', 'Task C', _at(10)),
        _row('sched-D', 'D', 'Task D', _at(11)),
      ];

  testWidgets('first task at the top, last at the bottom, every task represented once', (tester) async {
    await pump(tester, _Server(_dayJson(plan())));
    final ys = [for (final id in ['A', 'B', 'C', 'D']) tester.getCenter(stop('sched-$id')).dy];
    expect(ys, orderedEquals([...ys]..sort()));
    expect(find.byWidgetPredicate((w) => w.key.toString().contains('path_stop_')).evaluate().length, 4);
  });

  testWidgets('when A\'s slot ends the path moves on by itself: A bypassed in place, B is the target, one reload',
      (tester) async {
    final server = _Server(_dayJson(plan()));
    await pump(tester, server);
    expect(find.byKey(const Key('path_now_sched-A')), findsOneWidget);
    final homeA = onPath(tester, 'sched-A');
    final loads = server.dayGets;

    clock = _at(8, 31);
    FlowClock().debugTick(); // what the minute timer does in the app
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('path_now_sched-A')), findsNothing, reason: 'A is no longer the target');
    expect(find.byKey(const Key('path_now_sched-B')), findsOneWidget, reason: 'B is the next stop');
    expect(onPath(tester, 'sched-A'), homeA, reason: 'A stays exactly where it was');
    expect(server.dayGets, loads + 1, reason: 'the day is re-read once from the server');
    expect(server.posts.where((p) => p.contains('skip')), isEmpty, reason: 'time passing never writes a skip');

    clock = _at(8, 32);
    FlowClock().debugTick();
    await tester.pumpAndSettle();
    expect(server.dayGets, loads + 1, reason: 'no boundary and <5 min: no extra reload');
  });

  testWidgets('coming back to the app re-reads the day once', (tester) async {
    final server = _Server(_dayJson(plan()));
    final provider = await pump(tester, server);
    final loads = server.dayGets;
    clock = _at(9, 40);
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(server.dayGets, loads + 1);
    expect(find.byKey(const Key('path_now_sched-C')), findsOneWidget, reason: 'A and B ended while away');
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(server.dayGets, loads + 1, reason: 'a second resume right after is not another reload');
  });

  testWidgets('one clock subscription per owner; none left behind', (tester) async {
    final base = FlowClock().debugListenerCount;
    final server = _Server(_dayJson(plan()));
    final provider = await pump(tester, server);
    expect(FlowClock().debugListenerCount, base + 2, reason: 'the provider and the Calendar');
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();
    expect(FlowClock().debugListenerCount, base + 2, reason: 'a rebuild does not subscribe twice');
    await tester.pumpWidget(const SizedBox.shrink());
    expect(FlowClock().debugListenerCount, base + 1, reason: 'the Calendar unsubscribes when it goes');
    provider.dispose();
    expect(FlowClock().debugListenerCount, base);
  });

  testWidgets('done (session later), Do this now (moved to now) and a re-suggested slot never move a stop',
      (tester) async {
    final server = _Server(_dayJson([...plan(), _row('sched-E', 'E', 'Task E', _at(12), suggested: true)]));
    final provider = await pump(tester, server);
    final home = {for (final id in ['A', 'B', 'C', 'D', 'E']) id: onPath(tester, 'sched-$id')};

    // B done: the session ran 13:00-13:30 but it was planned at 9:00; C pulled to now; E re-suggested at 14:00
    server.body = _dayJson([
      _row('sched-A', 'A', 'Task A', _at(8)),
      _row('comp-B', 'B', 'Task B', _at(13), completed: true, anchor: _at(9)),
      _row('sched-C', 'C', 'Task C', _at(8, 21)),
      _row('sched-D', 'D', 'Task D', _at(11)),
      _row('sched-E', 'E', 'Task E', _at(14), suggested: true),
    ]);
    await provider.loadCalendarDay(provider.selectedCalendarDate);
    await tester.pumpAndSettle();

    for (final id in home.keys) {
      expect(stop('sched-$id'), findsOneWidget, reason: '$id keeps one stable stop');
      expect(onPath(tester, 'sched-$id'), home[id], reason: '$id stayed in place');
    }
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget, reason: 'B is drawn done');
  });

  testWidgets('a skip from the Calendar is registered on the server and the day re-read', (tester) async {
    final server = _Server(_dayJson(plan()));
    final provider = await pump(tester, server);
    final loads = server.dayGets;
    final message = await provider.skipTask('B');
    await tester.pumpAndSettle();
    expect(server.posts, contains(endsWith('/api/v1/today/skip/B')));
    expect(message, 'Skipped.');
    expect(server.dayGets, greaterThan(loads));
  });

  testWidgets('every task done: a trophy at the end of the road; claiming it gives Noya XP once', (tester) async {
    final done = [
      _row('comp-A', 'A', 'Task A', _at(8), completed: true),
      _row('comp-B', 'B', 'Task B', _at(9), completed: true),
    ];
    final server = _Server(_dayJson(done, dayComplete: {'eligible': true, 'claimed': false, 'xp': 25}));
    await pump(tester, server);
    await tester.scrollUntilVisible(find.byKey(const Key('path_trophy')), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('path_trophy')), findsOneWidget);
    final claim = find.byKey(const Key('path_trophy_claim'));
    expect(tester.getSize(claim).height, greaterThanOrEqualTo(48));
    await tester.tap(claim);
    await tester.pumpAndSettle();
    expect(server.posts.where((p) => p.endsWith('/api/v1/flow/day-complete/claim')).length, 1);
    expect(find.byKey(const Key('path_trophy_claim')), findsNothing);
    expect(find.text('+25 XP earned for Noya'), findsOneWidget);
  });

  testWidgets('no trophy while a task is still open', (tester) async {
    final server = _Server(_dayJson([
      _row('comp-A', 'A', 'Task A', _at(8), completed: true),
      _row('sched-B', 'B', 'Task B', _at(9)),
    ], dayComplete: {'eligible': false, 'claimed': false, 'xp': 25}));
    await pump(tester, server);
    expect(find.byKey(const Key('path_trophy')), findsNothing);
  });
}
