import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/engines/day_path_order.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// A -> B -> C -> D. When B is skipped or bypassed the stop stays exactly where it was and only the route changes
/// (manual verification 2026-10-06). Everything here goes through the real chain: backend-shaped JSON ->
/// ScheduleItem.fromJson -> buildCanonicalDayStops -> DayRouteGeometry (and the CalendarTab widget).

final DateTime _base = DateTime.now().toUtc();

/// A backend DayScheduleItem, [hours] from now.
Map<String, dynamic> _json(
  String id,
  String task,
  String title,
  double hours, {
  bool completed = false,
  bool missed = false,
  String? deviation,
}) {
  final start = _base.add(Duration(minutes: (hours * 60).round()));
  final local = start.toLocal();
  return {
    'id': id,
    'task_id': task,
    'title': title,
    'start_time': start.toIso8601String(),
    'end_time': start.add(const Duration(minutes: 30)).toIso8601String(),
    'time': '${local.hour % 12 == 0 ? 12 : local.hour % 12}:${local.minute.toString().padLeft(2, '0')}',
    'period': local.hour >= 12 ? 'PM' : 'AM',
    'duration_minutes': 30,
    'type': 'deep_work',
    'tag_text': deviation != null ? deviation.toUpperCase() : (completed ? 'COMPLETED' : 'DEEP WORK'),
    'is_completed': completed,
    'is_missed': missed,
    'state': deviation ?? (completed ? 'completed' : (missed ? 'missed' : 'scheduled')),
    if (deviation != null) 'deviation': deviation,
    if (deviation == 'skipped' || deviation == 'deferred') 'is_skipped': true,
  };
}

List<ScheduleItem> _items(List<Map<String, dynamic>> rows) => rows.map(ScheduleItem.fromJson).toList();

/// The Calendar's stop list for one day, as `_buildDayContent` builds it.
List<ScheduleItem> _stops(List<Map<String, dynamic>> live, [List<Map<String, dynamic>> history = const []]) =>
    buildCanonicalDayStops(live: _items(live), history: _items(history));

DayRouteGeometry _geo(List<ScheduleItem> stops) => DayRouteGeometry.compute(stops, null, 400);

List<Offset> _centers(DayRouteGeometry g) => [for (final s in g.stops) s.center];

// the four day states of one plan (ids and task ids are stable: sched-X / task X)
Map<String, dynamic> _a() => _json('sched-A', 'A', 'Task A', 1);
Map<String, dynamic> _b([double h = 2]) => _json('sched-B', 'B', 'Task B', h);
Map<String, dynamic> _c() => _json('sched-C', 'C', 'Task C', 3);
Map<String, dynamic> _d() => _json('sched-D', 'D', 'Task D', 4);

void main() {
  group('the stop list and route (real chain)', () {
    test('baseline: A B C D are four stops on the route', () {
      final g = _geo(_stops([_a(), _b(), _c(), _d()]));
      expect(g.stops.map((s) => s.id), ['sched-A', 'sched-B', 'sched-C', 'sched-D']);
      expect(g.stops.every((s) => s.role == StopRouteRole.onRoute), isTrue);
    });

    test('manual skip that lands LATER TODAY keeps B at its original place; the route bypasses it', () {
      final planned = _geo(_stops([_a(), _b(), _c(), _d()]));
      // the server moved B to +6h; its history node still sits at the original slot (+2h)
      final skipped = _geo(_stops(
        [_a(), _b(6), _c(), _d()],
        [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')],
      ));

      expect(skipped.stops.map((s) => s.id), ['sched-A', 'sched-B', 'sched-C', 'sched-D'], reason: 'B did not reorder');
      expect(_centers(skipped), _centers(planned), reason: 'every stop keeps its exact position');
      expect(skipped.stops[1].role, StopRouteRole.skipped);
      expect(skipped.distanceToRoute(skipped.stops[1].center), greaterThan(DayRouteGeometry.nodeRadius + 10),
          reason: 'the route bends around B');
      expect(skipped.sampleXs, isNot(planned.sampleXs), reason: 'the route model follows B\'s new state');
      expect(planned.sameRoute(skipped), isFalse, reason: 'B\'s state changed');
      expect(planned.layoutSignature, skipped.layoutSignature, reason: 'same stops: nothing remounts');
    });

    test('manual skip that moved B to ANOTHER DAY: the history node is the stop, same id, same place', () {
      final planned = _geo(_stops([_a(), _b(), _c(), _d()]));
      final skipped = _geo(_stops(
        [_a(), _c(), _d()],
        [_json('sched-B', 'B', 'Task B', 2, deviation: 'skipped')],
      ));
      expect(skipped.stops.map((s) => s.id), planned.stops.map((s) => s.id));
      expect(_centers(skipped), _centers(planned));
      expect(skipped.stops[1].role, StopRouteRole.skipped);
    });

    test('automatic bypass (slot ended, derived missed): node stays, route skips it, nothing is recorded', () {
      final planned = _geo(_stops([_a(), _b(), _c(), _d()]));
      final bypassed = _geo(_stops([_a(), _json('sched-B', 'B', 'Task B', 2, missed: true), _c(), _d()]));
      expect(bypassed.stops.map((s) => s.id), planned.stops.map((s) => s.id));
      expect(_centers(bypassed), _centers(planned));
      expect(bypassed.stops[1].role, StopRouteRole.bypassed);
      expect(bypassed.distanceToRoute(bypassed.stops[1].center), greaterThan(DayRouteGeometry.nodeRadius + 10),
          reason: 'the road bends around B and carries on to C');
      expect(bypassed.distanceToRoute(bypassed.stops[2].center), lessThan(0.5));
      expect(bypassed.sampleXs, isNot(planned.sampleXs));
      expect(planned.sameRoute(bypassed), isFalse);
    });

    test('a missed task that was redone later today keeps one bypassed node at its original slot', () {
      final planned = _geo(_stops([_a(), _b(), _c(), _d()]));
      final redone = _geo(_stops(
        [_a(), _b(5), _c(), _d()],
        [_json('dev-2', 'B', 'Task B', 2, deviation: 'missed')],
      ));
      expect(redone.stops.map((s) => s.id), planned.stops.map((s) => s.id), reason: 'no second B node');
      expect(_centers(redone), _centers(planned));
      expect(redone.stops[1].role, StopRouteRole.bypassed);
    });

    test('recovery: B completed after being skipped stays at its original place; the orange state is on the same road', () {
      final planned = _geo(_stops([_a(), _b(), _c(), _d()]));
      // completed later today (session at +7h); the skipped history node is still at +2h
      final recovered = _geo(_stops(
        [_a(), _json('comp-B', 'B', 'Task B', 7, completed: true), _c(), _d()],
        [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')],
      ));
      // the completed B keeps its stop identity (sched-B), so nothing remounts and the route can morph
      expect(recovered.stops.map((s) => s.id), ['sched-A', 'sched-B', 'sched-C', 'sched-D']);
      expect(recovered.layoutSignature, planned.layoutSignature);
      expect(_centers(recovered), _centers(planned));
      expect(recovered.stops[1].role, StopRouteRole.recovered);
      expect(recovered.sampleXs, planned.sampleXs, reason: 'no separate shortcut: the very same road');
      expect(recovered.distanceToRoute(recovered.stops[1].center), lessThan(0.5));
      expect(recovered.sampleStates, contains(RouteSegmentState.recovered));
    });

    test('positions stay put through the whole life of B: planned -> skipped -> recovered', () {
      final lives = <List<Offset>>[
        _centers(_geo(_stops([_a(), _b(), _c(), _d()]))),
        _centers(_geo(_stops([_a(), _b(6), _c(), _d()], [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')]))),
        _centers(_geo(_stops(
            [_a(), _json('comp-B', 'B', 'Task B', 7, completed: true), _c(), _d()],
            [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')]))),
      ];
      expect(lives[1], lives[0]);
      expect(lives[2], lives[0]);
    });

    test('the number of stops equals the number of tasks, whatever happened to them', () {
      final cases = <List<ScheduleItem>>[
        _stops([_a(), _b(), _c(), _d()]),
        _stops([_a(), _b(6), _c(), _d()], [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')]),
        _stops([_a(), _c(), _d()], [_json('sched-B', 'B', 'Task B', 2, deviation: 'deferred')]),
        _stops([_a(), _json('sched-B', 'B', 'Task B', 2, missed: true), _c(), _d()]),
        // two history records of one task are still one stop
        _stops([_a(), _b(6), _c(), _d()], [
          _json('dev-1', 'B', 'Task B', 2, deviation: 'skipped'),
          _json('dev-2', 'B', 'Task B', 3, deviation: 'missed'),
        ]),
      ];
      for (final stops in cases) {
        expect(stops.length, 4);
        expect(_geo(stops).stops.length, 4);
        expect(stops.map((s) => s.title), ['Task A', 'Task B', 'Task C', 'Task D']);
      }
    });

    test('a live task without history is untouched', () {
      final live = _items([_a(), _b(), _c(), _d()]);
      expect(mergeDayPathHistory(live, const []).map((s) => s.id), live.map((s) => s.id));
    });

    test('a skipped, still-unslotted task keeps its place (not pushed to the end as UNSCHEDULED)', () {
      final unslotted = _json('sched-B', 'B', 'Task B', 6)..['tag_text'] = 'UNSCHEDULED';
      final stops = _stops([_a(), unslotted, _c(), _d()], [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')]);
      expect(stops.map((s) => s.title), ['Task A', 'Task B', 'Task C', 'Task D']);
    });
  });

  group('CalendarTab renders the same stops through the whole life of B', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => FlowClock().stopTimer());

    String dayJson(List<Map<String, dynamic>> timeline, [List<Map<String, dynamic>> deviations = const []]) => jsonEncode({
          'date': '2026-10-05',
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

    testWidgets('planned -> skipped (server moved it) -> recovered: four stops, B never moves', (tester) async {
      var body = dayJson([_a(), _b(), _c(), _d()]);
      final provider = AppStateProvider(
        customApi: ApiService(
          client: MockClient((r) async => http.Response(body, 200, headers: {'content-type': 'application/json'})),
        ),
      );
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();

      Finder stop(String id) => find.byKey(Key('path_stop_$id'));
      int stopCount() => find.byWidgetPredicate((w) => w.key.toString().contains('path_stop_')).evaluate().length;
      Offset center(String id) => tester.getCenter(stop(id));

      // planned
      expect(stopCount(), 4);
      final home = {for (final id in ['sched-A', 'sched-B', 'sched-C', 'sched-D']) id: center(id)};
      expect(home['sched-B']!.dy, greaterThan(home['sched-A']!.dy));
      expect(home['sched-B']!.dy, lessThan(home['sched-C']!.dy));

      // B skipped: the server moved it to +6h and kept its original slot as history
      body = dayJson([_a(), _b(6), _c(), _d()], [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')]);
      await provider.loadCalendarDay(provider.selectedCalendarDate);
      await tester.pumpAndSettle();
      expect(stopCount(), 4, reason: 'B was not removed');
      expect(stop('sched-B'), findsOneWidget);
      for (final id in home.keys) {
        expect(center(id), home[id], reason: '$id stayed exactly where it was');
      }
      expect(find.byKey(const Key('path_skipped_sched-B')), findsOneWidget, reason: 'B keeps its skipped state');

      // restart: a fresh reload shows the same thing (the state lives on the server, not in memory)
      await provider.loadCalendarDay(provider.selectedCalendarDate);
      await tester.pumpAndSettle();
      expect(stopCount(), 4);
      expect(center('sched-B'), home['sched-B']);

      // B recovered: completed later, still at its original place
      body = dayJson(
        [_a(), _json('comp-B', 'B', 'Task B', 7, completed: true), _c(), _d()],
        [_json('dev-1', 'B', 'Task B', 2, deviation: 'skipped')],
      );
      await provider.loadCalendarDay(provider.selectedCalendarDate);
      await tester.pumpAndSettle();
      expect(stopCount(), 4);
      expect(stop('sched-B'), findsOneWidget);
      expect(find.byKey(const Key('path_check_sched-B')), findsOneWidget, reason: 'B is shown as done');
      expect(center('sched-B'), home['sched-B']);
      expect(center('sched-C'), home['sched-C']);
      expect(center('sched-D'), home['sched-D']);
    });
  });
}
