import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/flow_month_picker.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Calendar stability regression (2026-10-07): one day goes through skip, a missed slot (clock), defer and a
/// recovery. Every stop keeps its key and its exact place on the path; only the route changes. Plus the full
/// month picker: any day can be opened, including ones outside the date strip's window.
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
  Offset onPath(WidgetTester tester, String id) =>
      tester.getCenter(stop(id)) - tester.getTopLeft(find.byKey(const Key('flow_day_path_line')));

  const ids = ['A', 'B', 'C', 'D'];

  testWidgets('skip, miss, defer and recover: no stop ever moves or changes key', (tester) async {
    final server = _Server(_dayJson([
      _row('sched-A', 'A', 'Task A', _at(8)),
      _row('sched-B', 'B', 'Task B', _at(9)),
      _row('sched-C', 'C', 'Task C', _at(10)),
      _row('sched-D', 'D', 'Task D', _at(11)),
    ]));
    final provider = await pump(tester, server);
    final home = {for (final id in ids) id: onPath(tester, 'sched-$id')};

    Future<void> check(String step) async {
      await provider.loadCalendarDay(provider.selectedCalendarDate);
      await tester.pumpAndSettle();
      for (final id in ids) {
        expect(stop('sched-$id'), findsOneWidget, reason: '$step: $id keeps exactly one stop with the same key');
        // sub-pixel tolerance only: a moved stop shifts by whole node spacings
        expect((onPath(tester, 'sched-$id') - home[id]!).distance, lessThan(0.5), reason: '$step: $id did not move');
      }
    }

    // 1. B skipped (moved to tomorrow): today keeps B's stop at 9:00 as history
    server.body = _dayJson([
      _row('sched-A', 'A', 'Task A', _at(8)),
      _row('sched-C', 'C', 'Task C', _at(10)),
      _row('sched-D', 'D', 'Task D', _at(11)),
    ], deviations: [_row('dev-B', 'B', 'Task B', _at(9), deviation: 'skipped')]);
    await check('skip');

    // 2. A's slot ends unfinished: bypassed automatically (no skip written), still in place
    clock = _at(8, 45);
    FlowClock().debugTick();
    await tester.pumpAndSettle();
    await check('missed');
    expect(server.posts.where((p) => p.contains('skip')), isEmpty);

    // 3. C deferred
    server.body = _dayJson([
      _row('sched-A', 'A', 'Task A', _at(8)),
      _row('sched-D', 'D', 'Task D', _at(11)),
    ], deviations: [
      _row('dev-B', 'B', 'Task B', _at(9), deviation: 'skipped'),
      _row('dev-C', 'C', 'Task C', _at(10), deviation: 'deferred'),
    ]);
    await check('defer');

    // 4. B recovered: brought back and finished later in the day; its stop is still at 9:00
    server.body = _dayJson([
      _row('sched-A', 'A', 'Task A', _at(8)),
      _row('comp-B', 'B', 'Task B', _at(13), completed: true, anchor: _at(9)),
      _row('sched-D', 'D', 'Task D', _at(11)),
    ], deviations: [
      _row('dev-B', 'B', 'Task B', _at(9), deviation: 'skipped'),
      _row('dev-C', 'C', 'Task C', _at(10), deviation: 'deferred'),
    ]);
    await check('recover');
    expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget, reason: 'B is drawn done');
  });

  testWidgets('month picker opens from the header and goes to a day outside the strip', (tester) async {
    final server = _Server(_dayJson([_row('sched-A', 'A', 'Task A', _at(8))]));
    final provider = await pump(tester, server);

    final button = find.byKey(const Key('calendar_month_picker_button'));
    expect(button, findsOneWidget);
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(FlowMonthPicker), findsOneWidget);

    // two months ahead, the 15th
    await tester.tap(find.byKey(const Key('month_picker_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('month_picker_next')));
    await tester.pumpAndSettle();
    final target = DateTime(_day.year, _day.month + 2, 15);
    final iso = '${target.year.toString().padLeft(4, '0')}-${target.month.toString().padLeft(2, '0')}-15';
    await tester.tap(find.byKey(Key('month_day_$iso')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('month_picker_go')));
    await tester.pumpAndSettle();

    expect(find.byType(FlowMonthPicker), findsNothing);
    expect(provider.selectedCalendarDate, target);
    // the strip re-centred: the picked day has a chip, so the header and the strip agree
    expect(find.byKey(Key('calendar_day_chip_$iso')), findsOneWidget);
  });

  testWidgets('dismissing the month picker changes nothing', (tester) async {
    final server = _Server(_dayJson([_row('sched-A', 'A', 'Task A', _at(8))]));
    final provider = await pump(tester, server);
    final before = provider.selectedCalendarDate;
    await tester.tap(find.byKey(const Key('calendar_month_picker_button')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // the scrim
    await tester.pumpAndSettle();
    expect(provider.selectedCalendarDate, before);
  });
}
