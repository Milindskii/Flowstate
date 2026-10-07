import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Calendar after Replan / moves (2026-10-07 forensic fixes):
/// 1. every task whose persisted schedule a Replan changed (collateral too) takes its new place;
///    skipped/deferred stops keep theirs.
/// 2. a task explicitly moved to another day leaves the selected day at once.
/// 3. an older Today read can never overwrite the schedule a newer Calendar read wrote.
/// 4. one Replan tap, one sheet.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

DateTime _at(int h, [int m = 0]) => DateTime(_day.year, _day.month, _day.day, h, m);
DateTime get _tomorrow => _day.add(const Duration(days: 1));

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _Task {
  final String id;
  final String title;
  DateTime start;
  final int minutes = 30;
  _Task(this.id, this.title, this.start);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'duration_minutes': minutes,
        'estimated_minutes': minutes,
        'difficulty': 'high',
        'task_type': 'deep_work',
        'status': 'todo',
        'scheduled_start': start.toUtc().toIso8601String(),
        'scheduled_end': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
        'planned_date': _ymd(start),
        'time_locked': false,
      };
}

Map<String, dynamic> _row(String id, String task, String title, DateTime start, {String? deviation}) {
  final h12 = start.hour % 12 == 0 ? 12 : start.hour % 12;
  return {
    'id': id,
    'task_id': task,
    'title': title,
    'start_time': start.toUtc().toIso8601String(),
    'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
    'time': '$h12:${start.minute.toString().padLeft(2, '0')}',
    'period': start.hour >= 12 ? 'PM' : 'AM',
    'duration_minutes': 30,
    'type': 'deep_work',
    'tag_text': deviation != null ? deviation.toUpperCase() : 'DEEP WORK',
    'is_completed': false,
    'state': deviation ?? 'scheduled',
    if (deviation != null) 'deviation': deviation,
    if (deviation == 'skipped') 'is_skipped': true,
  };
}

Map<String, dynamic> _todayJson(List<String> ids) => {
      'lifecycle_state': 'calibrated',
      'state': 'calibrated',
      'has_actionable_tasks': true,
      'upcoming_timeline': [
        for (final id in ids)
          {'id': id, 'time': '4:00', 'period': 'PM', 'title': id, 'type': 'admin', 'tag_text': 'LIGHT',
           'duration_minutes': 30},
      ],
    };

class _Server {
  final Map<String, _Task> tasks = {
    for (final t in [
      _Task('A', 'Task A', _at(8)),
      _Task('B', 'Task B', _at(9)),
      _Task('C', 'Task C', _at(10)),
      _Task('D', 'Task D', _at(11)),
    ])
      t.id: t,
  };
  final List<Map<String, dynamic>> deviations = [];
  Map<String, dynamic> today = _todayJson(['sched-A']);
  Completer<void>? patchGate, todayGate;
  List<Map<String, dynamic>> Function()? onApply;

  String dayBody() {
    final shown = tasks.values.where((t) => _ymd(t.start) == _ymd(_day)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return jsonEncode({
      'date': _ymd(_day),
      'is_today': true,
      'is_past': false,
      'timeline': [for (final t in shown) _row('sched-${t.id}', t.id, t.title, t.start)],
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
    if (path.endsWith('/api/v1/calendar/day')) return http.Response(dayBody(), 200, headers: json);
    if (path == '/api/v1/today') {
      final body = jsonEncode(today); // what the server held when the request ARRIVED
      if (todayGate != null) await todayGate!.future;
      return http.Response(body, 200, headers: json);
    }
    if (path.endsWith('/api/v1/calendar/apply-replan')) {
      final rows = onApply?.call() ?? [];
      return http.Response(
          jsonEncode({'success': true, 'updated_count': rows.length, 'persisted_tasks': rows}), 200, headers: json);
    }
    if (r.method == 'PATCH' && path.startsWith('/api/v1/tasks/')) {
      if (patchGate != null) await patchGate!.future;
      final t = tasks[path.split('/').last]!;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      if (body['scheduled_start'] != null) t.start = DateTime.parse(body['scheduled_start'].toString()).toLocal();
      return http.Response(jsonEncode(t.toJson()), 200, headers: json); // an explicit move keeps no history
    }
    if (r.method == 'GET' && path == '/api/v1/tasks') {
      return http.Response(jsonEncode({'items': [for (final t in tasks.values) t.toJson()], 'total': tasks.length}),
          200, headers: json);
    }
    return http.Response('{}', 200, headers: json);
  }
}

const _user = AuthUser(id: 'user-cal', email: 'cal@flowstate.local', name: 'C', onboardingCompleted: true);

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
  // a stop's place ON the path (independent of where the screen is scrolled to show the current target)
  double y(WidgetTester tester, String id) =>
      tester.getCenter(stop(id)).dy - tester.getTopLeft(find.byKey(const Key('flow_day_path_line'))).dy;
  List<String> order(WidgetTester tester, List<String> ids) {
    final present = ids.where((id) => stop(id).evaluate().isNotEmpty).toList();
    present.sort((a, b) => y(tester, a).compareTo(y(tester, b)));
    return present;
  }

  testWidgets('FIX 1: Replan moves B and collaterally C: B takes new place; C keeps anchor; skipped D keeps stop',
      (tester) async {
    final server = _Server();
    final provider = await pump(tester, server);
    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'B', 'C', 'D']);

    server.onApply = () {
      server.tasks['B']!.start = _at(12); // asked for
      server.tasks['C']!.start = _at(12, 30); // collateral: no intent of its own
      server.deviations.add(_row('dev-D', 'D', 'Task D', _at(11), deviation: 'skipped'));
      server.tasks['D']!.start = _tomorrow.add(const Duration(hours: 9));
      return [for (final id in ['B', 'C', 'D']) server.tasks[id]!.toJson()];
    };
    await provider.applyReplan(PlanDiff(
      planId: 'p1',
      selectedDate: _ymd(_day),
      movedTasks: const [
        TaskDiffItem(taskId: 'B', title: 'Task B', changeType: 'moved'),
        TaskDiffItem(taskId: 'C', title: 'Task C', changeType: 'moved'),
        TaskDiffItem(taskId: 'D', title: 'Task D', changeType: 'moved'),
      ],
      serverApplyRequest: const ApplyReplanRequest(
        planId: 'p1',
        selectedDate: '',
        taskUpdates: [],
        newTasks: [],
        cancelledTaskIds: [],
        raw: {'intents': {'B': 'rescheduled', 'D': 'skipped'}},
      ),
    ));
    await tester.pumpAndSettle();

    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'C', 'D', 'B'],
        reason: 'B takes its new 12:00 slot, C keeps its collateral anchor, D stays as its skipped history stop');
    expect(stop('D'), findsOneWidget, reason: 'skipped is not deleted');
    final anchors = provider.dayPathAnchorsFor(_day);
    expect(anchors['B']?.anchor, _at(12));
    expect(anchors['C']?.anchor, _at(10), reason: 'collateral move keeps its original 10:00 anchor');
    expect(anchors['D']?.anchor, _at(11), reason: 'the skip keeps D anchored at its original 11:00 slot');

    // a later re-read (clock tick / resume) keeps the new plan where it is
    final settled = {for (final id in ['A', 'B', 'C', 'D']) id: y(tester, id)};
    await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
    await tester.pumpAndSettle();
    for (final id in settled.keys) {
      expect((y(tester, id) - settled[id]!).abs(), lessThan(0.5), reason: '$id is stable after the new plan');
    }
  });

  testWidgets('FIX 2: a task moved from today to tomorrow leaves today\'s Calendar at once', (tester) async {
    final server = _Server();
    final provider = await pump(tester, server);
    expect(stop('B'), findsOneWidget);

    server.patchGate = Completer<void>(); // the save is still in flight for the whole check
    final done = provider.rescheduleTask('B', targetDate: _tomorrow, targetTime: const TimeOfDay(hour: 9, minute: 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(stop('B'), findsNothing, reason: 'B is tomorrow now; it must not wait for the network to leave today');
    expect(order(tester, ['A', 'C', 'D']), ['A', 'C', 'D']);

    server.patchGate!.complete();
    await done;
    await tester.pumpAndSettle();
    expect(stop('B'), findsNothing);
    expect(order(tester, ['A', 'C', 'D']), ['A', 'C', 'D']);
  });

  testWidgets('FIX 3: an older Today read answering after a newer Calendar read cannot replace its schedule',
      (tester) async {
    final server = _Server();
    final provider = await pump(tester, server);

    server.today = _todayJson(['stale-X']); // a differently-shaped, pre-change Today answer
    server.todayGate = Completer<void>();
    final todayRead = provider.refreshTodayData(); // issued first, answers last
    await tester.pump();

    await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true); // issued later, answers first
    final calendarIds = provider.selectedDateSchedule!.timeline.map((i) => i.id).toList();
    expect(provider.schedule.map((i) => i.id), calendarIds);

    server.todayGate!.complete();
    await todayRead;
    await tester.pumpAndSettle();
    expect(provider.schedule.map((i) => i.id), calendarIds, reason: 'the stale Today answer was dropped');
    expect(provider.selectedDateSchedule!.timeline.map((i) => i.id), calendarIds);
    expect(order(tester, ['A', 'B', 'C', 'D']), ['A', 'B', 'C', 'D'], reason: 'Calendar identity intact');
    expect(find.text('stale-X'), findsNothing);
  });

  testWidgets('FIX 3: of two Today reads, the newer one wins whatever order they answer in', (tester) async {
    final server = _Server();
    final provider = await pump(tester, server);

    server.today = _todayJson(['old']);
    server.todayGate = Completer<void>();
    final first = provider.refreshTodayData();
    await tester.pump();
    server.today = _todayJson(['new']);
    final gate = server.todayGate!;
    server.todayGate = null;
    await provider.refreshTodayData(); // answers first
    expect(provider.schedule.map((i) => i.id), ['new']);
    gate.complete();
    await first;
    expect(provider.schedule.map((i) => i.id), ['new'], reason: 'the older answer is not applied over the newer');
  });

  testWidgets('FIX 4: twenty rapid taps on Replan open exactly one sheet', (tester) async {
    final server = _Server();
    await pump(tester, server);
    final button = find.byKey(const Key('calendar_replan_button'));
    expect(button, findsOneWidget);
    await tester.ensureVisible(button); // the day scrolls to the current stop; the header is above it
    await tester.pumpAndSettle();
    // 20 taps inside one frame (before the sheet's barrier exists): every one reaches the button's handler
    final onPressed = tester.widget<TextButton>(button).onPressed!;
    for (var i = 0; i < 20; i++) {
      onPressed();
    }
    await tester.pumpAndSettle();
    expect(find.byType(ReplanDaySheet), findsOneWidget);
    expect(tester.takeException(), isNull);

    // closing it lets the next tap open it again
    Navigator.of(tester.element(find.byType(ReplanDaySheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(ReplanDaySheet), findsNothing);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.byType(ReplanDaySheet), findsOneWidget);
  });
}
