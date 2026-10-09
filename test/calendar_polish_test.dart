import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/components/day_path/stop_emoji.dart';
import 'package:flowstate/engines/day_path_order.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Final polish pass: the Calendar journey is automatic, follows actual travel, keeps one road language, and its text
/// never sits on the road.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

DateTime _at(int h, [int m = 0]) => DateTime(_day.year, _day.month, _day.day, h, m);

ScheduleItem _stop(String id, DateTime start,
        {bool done = false, bool missed = false, bool skipped = false, bool recovered = false, bool active = false,
        bool commitment = false, String? title}) =>
    ScheduleItem(
      id: 'sched-$id',
      taskId: id,
      time: '${start.hour % 12 == 0 ? 12 : start.hour % 12}:${start.minute.toString().padLeft(2, '0')}',
      period: start.hour >= 12 ? 'PM' : 'AM',
      title: title ?? 'Task $id',
      type: 'Task',
      tagText: 'TASK',
      durationMinutes: 60,
      startTime: start,
      endTime: start.add(const Duration(minutes: 60)),
      isCompleted: done,
      isMissed: missed,
      isSkipped: skipped,
      isCompletedAfterDeviation: recovered,
      isActive: active,
      isCommitment: commitment,
    );

/// Records every path the painter strokes, with its paint, so the road language can be compared.
class _RecordingCanvas implements Canvas {
  final List<(Path, Paint)> paths = [];
  final List<Paint> lines = [];

  @override
  void drawPath(Path path, Paint paint) => paths.add((path, Paint()
    ..color = paint.color
    ..style = paint.style
    ..strokeWidth = paint.strokeWidth
    ..strokeCap = paint.strokeCap));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add(Paint()
    ..color = paint.color
    ..strokeWidth = paint.strokeWidth
    ..strokeCap = paint.strokeCap);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('the journey moves on by itself (no "Do this later")', () {
    final now = _at(10, 30);

    test('B whose time came is passed once a LATER stop is done: drawn missed, the road bends around it', () {
      final stops = markPassedStops([
        _stop('A', _at(8), done: true),
        _stop('B', _at(10)), // its slot (10-11) is still running: the clock alone has not missed it
        _stop('C', _at(11), done: true), // the user did C early
        _stop('D', _at(12)),
      ], now: now);
      final b = stops[1];
      expect(b.isMissed, isTrue);
      expect(b.state, 'passed');
      expect(b.isSkipped, isFalse, reason: 'nothing is recorded as a skip');
      final g = DayRouteGeometry.compute(stops, null, 360);
      expect(DayRouteGeometry.isBypassed(g.stopById('sched-B')), isTrue);
      expect(g.distanceToRoute(g.stopById('sched-B').center), greaterThan(DayRouteGeometry.nodeRadius + 10));
      expect(pickDayPathNowId(stops, now: now), 'sched-D', reason: 'the traveller is past B: D is next');
    });

    test('a stop whose time has not come is never passed, and nothing before the furthest stop is touched otherwise', () {
      final stops = markPassedStops([
        _stop('A', _at(8), done: true),
        _stop('B', _at(14)), // later today
        _stop('C', _at(9), done: true),
      ], now: now);
      expect(stops[1].isMissed, isFalse);
    });

    test('a running later stop also moves the traveller past B', () {
      final stops = markPassedStops([_stop('A', _at(9)), _stop('B', _at(10), active: true)], now: now);
      expect(stops[0].state, 'passed');
    });

    test('commitments and the Do-this-now pick are never passed; the pick shows open even if it was missed', () {
      final stops = markPassedStops([
        _stop('A', _at(8), commitment: true),
        _stop('B', _at(9), missed: true),
        _stop('C', _at(11), done: true),
      ], now: now, keepOpenTaskId: 'B');
      expect(stops[0].isMissed, isFalse);
      expect(stops[1].isMissed, isFalse);
      expect(pickDayPathNowId(stops, now: now, preferredTaskId: 'B'), 'sched-B');
    });

    test('undoing the later completion recomputes: B is no longer passed', () {
      final before = markPassedStops([_stop('A', _at(8), done: true), _stop('B', _at(10)), _stop('C', _at(11), done: true)], now: now);
      final after = markPassedStops([_stop('A', _at(8), done: true), _stop('B', _at(10)), _stop('C', _at(11))], now: now);
      expect(before[1].isMissed, isTrue);
      expect(after[1].isMissed, isFalse);
    });
  });

  group('actual travel', () {
    test('B done AFTER C (came back from a later stop) is a change of course: branch C -> B, never A -> B', () {
      final items = [
        _stop('A', _at(8), done: true),
        _stop('B', _at(9), done: true),
        _stop('C', _at(10), done: true),
      ];
      final g = DayRouteGeometry.compute(items, null, 360,
          completedAt: {'sched-A': _at(8, 50), 'sched-C': _at(9, 40), 'sched-B': _at(10, 30)});
      expect(g.branches, hasLength(1));
      expect(g.branches.single.fromId, 'sched-C');
      expect(g.branches.single.toId, 'sched-B');
      expect(g.branches.single.points.first, g.stopById('sched-C').center, reason: 'continuous: leaves the node');
      expect(g.branches.single.points.last, g.stopById('sched-B').center, reason: 'continuous: reaches the node');
    });

    test('recovery after D starts at D (the latest real position), not at the chronological predecessor', () {
      final items = [
        _stop('A', _at(8), done: true),
        _stop('B', _at(9), done: true, recovered: true),
        _stop('C', _at(10), done: true),
        _stop('D', _at(11), done: true),
      ];
      final g = DayRouteGeometry.compute(items, null, 360, completedAt: {
        'sched-A': _at(8, 50), 'sched-C': _at(10, 50), 'sched-D': _at(11, 50), 'sched-B': _at(12, 10)});
      expect(g.branches.single.fromId, 'sched-D');
      expect(g.branches.single.fromId, isNot('sched-A'));
      expect(g.stopById('sched-B').center, DayRouteGeometry.compute(items, null, 360).stopById('sched-B').center,
          reason: 'B keeps its timeline position');
    });

    test('in-order completions draw no branch at all', () {
      final items = [_stop('A', _at(8), done: true), _stop('B', _at(9), done: true)];
      final g = DayRouteGeometry.compute(items, null, 360, completedAt: {'sched-A': _at(8, 50), 'sched-B': _at(9, 50)});
      expect(g.branches, isEmpty);
    });
  });

  group('one road language', () {
    test('a recovery branch is painted like the road: a bed with shadow and edges, and the same line width', () {
      final items = [
        _stop('A', _at(8), done: true),
        _stop('B', _at(9), done: true, recovered: true),
        _stop('C', _at(10), done: true),
        _stop('D', _at(11), done: true),
      ];
      final g = DayRouteGeometry.compute(items, null, 360, completedAt: {
        'sched-A': _at(8, 50), 'sched-C': _at(10, 50), 'sched-D': _at(11, 50), 'sched-B': _at(12, 10)});
      const palette = DayRoutePalette(
        traveled: Colors.green, ahead: Colors.blue, skipped: Colors.yellow, recovery: Colors.orange,
        failed: Colors.red, bed: Color(0x22000000), bedEdge: Color(0x33000000), fadeTo: Colors.white);
      final canvas = _RecordingCanvas();
      DayRoutePainter(geometry: g, palette: palette).paint(canvas, Size(360, g.height));
      final beds = canvas.paths.where((p) => p.$2.color.toARGB32() == palette.bed.toARGB32()).length;
      expect(beds, 2, reason: 'one bed for the road, one for the branch');
      final branchLine = canvas.paths.where((p) => p.$2.color.toARGB32() == Colors.orange.toARGB32() && p.$2.style == PaintingStyle.stroke).single.$2;
      expect(canvas.lines, isNotEmpty);
      for (final l in canvas.lines) {
        expect(l.strokeWidth, branchLine.strokeWidth, reason: 'same width everywhere');
        expect(l.strokeCap, branchLine.strokeCap, reason: 'same softness');
      }
    });
  });

  group('labels never sit on the road', () {
    /// True when the label rect of [s] (its slot, the label's height) stays clear of every road polyline.
    void expectClear(DayRouteGeometry g, StopGeometry s) {
      final slot = s.label!;
      final rect = Rect.fromLTRB(slot.left, s.center.dy - DayRouteGeometry.labelHalfHeight, slot.right,
          s.center.dy + DayRouteGeometry.labelHalfHeight);
      final lines = <List<Offset>>[
        [for (var i = 0; i < g.sampleYs.length; i++) Offset(g.sampleXs[i], g.sampleYs[i])],
        for (final b in g.branches) b.points,
      ];
      for (final line in lines) {
        for (final p in line) {
          if (p.dy < rect.top || p.dy > rect.bottom) continue;
          final dx = p.dx < rect.left ? rect.left - p.dx : (p.dx > rect.right ? p.dx - rect.right : 0.0);
          expect(dx, greaterThanOrEqualTo(DayRouteGeometry.nearHalfWidth),
              reason: '${s.id}: label $slot is clear of the road at y=${p.dy.toStringAsFixed(1)}');
        }
      }
      expect(slot.right, lessThanOrEqualTo(g.width - DayRouteGeometry.labelMargin + 0.01));
      expect(slot.left, greaterThanOrEqualTo(DayRouteGeometry.labelMargin - 0.01));
    }

    for (final width in [320.0, 360.0, 412.0]) {
      test('every state at once, with detours and a recovery branch, at ${width.round()} dp', () {
        final items = [
          _stop('A', _at(8), done: true),
          _stop('B', _at(9), done: true, recovered: true),
          _stop('C', _at(10), skipped: true),
          _stop('D', _at(11), done: true),
          _stop('E', _at(12), missed: true),
          _stop('F', _at(13), done: true),
          _stop('G', _at(14)),
          _stop('H', _at(15)),
        ];
        final g = DayRouteGeometry.compute(items, 'sched-G', width, finish: false, completedAt: {
          'sched-A': _at(8, 50), 'sched-D': _at(11, 50), 'sched-F': _at(13, 50), 'sched-B': _at(14, 10)});
        expect(g.branches, isNotEmpty);
        for (final s in g.stops) {
          expectClear(g, s);
          // every state at once is the tightest case: on a phone under 400 dp a stop that two branches leave has its
          // label squeezed between them and the road (the text ellipsizes; it never overlaps)
          expect(s.label!.width, greaterThan(width < 400 ? 48 : 60), reason: '${s.id} keeps readable room');
        }
      });
    }

    test('deterministic: the same day always gives the same slots', () {
      final items = [for (var i = 0; i < 6; i++) _stop('t$i', _at(8 + i), missed: i == 2)];
      final a = DayRouteGeometry.compute(items, null, 340);
      final b = DayRouteGeometry.compute(items, null, 340);
      for (var i = 0; i < a.stops.length; i++) {
        expect(a.stops[i].label!.left, b.stops[i].label!.left);
        expect(a.stops[i].label!.right, b.stops[i].label!.right);
        expect(a.stops[i].label!.onLeft, b.stops[i].label!.onLeft);
      }
    });
  });

  group('stop identity', () {
    test('deterministic task pictures', () {
      expect(stopEmojiFor(title: 'ML assignment'), '🧠');
      expect(stopEmojiFor(title: 'Class'), '🏫');
      expect(stopEmojiFor(title: 'Gym'), '🏋️');
      expect(stopEmojiFor(title: 'Something', category: 'Fitness'), '🏋️');
      expect(stopEmojiFor(title: 'Something vague'), '📌');
      expect(stopEmojiFor(title: 'ML assignment'), stopEmojiFor(title: 'ML assignment'));
    });
  });

  group('Calendar screen', () {
    late DateTime clock;
    final posts = <String>[];
    late String dayBody;

    Map<String, dynamic> row(String id, DateTime start, {bool completed = false}) => {
          'id': 'sched-$id',
          'task_id': id,
          'title': 'Task $id',
          'start_time': start.toUtc().toIso8601String(),
          'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
          'time': '${start.hour % 12 == 0 ? 12 : start.hour % 12}:${start.minute.toString().padLeft(2, '0')}',
          'period': start.hour >= 12 ? 'PM' : 'AM',
          'duration_minutes': 30,
          'type': 'deep_work',
          'tag_text': 'DEEP WORK',
          'is_completed': completed,
          'state': completed ? 'completed' : 'scheduled',
        };

    String day(List<Map<String, dynamic>> timeline) => jsonEncode({
          'date': '${_day.year.toString().padLeft(4, '0')}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}',
          'is_today': true,
          'is_past': false,
          'timeline': timeline,
          'fixed_commitments': [],
          'completed_tasks': [],
          'remaining_tasks': [],
          'unscheduled_tasks': [],
          'deviations': [],
          'conflicts': [],
        });

    TaskItem task(String id, DateTime start) => TaskItem(
          id: id,
          title: 'Task $id',
          durationMinutes: 30,
          difficulty: TaskDifficulty.medium,
          deadline: 'Today',
          category: 'Work',
          scheduledStart: start,
          scheduledEnd: start.add(const Duration(minutes: 30)),
          plannedDate: _day,
        );

    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      clock = _at(10, 0);
      FlowClock.debugNowOverride = () => clock;
      SharedPreferences.setMockInitialValues({});
      TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
      posts.clear();
    });
    tearDown(() {
      FlowClock.debugNowOverride = null;
      FlowClock().stopTimer();
    });

    Future<AppStateProvider> pump(WidgetTester tester, {bool doNowMoves = true, bool doNowFails = false}) async {
      dayBody = day([row('A', _at(8)), row('B', _at(9)), row('C', _at(11))]);
      Future<http.Response> handle(http.Request r) async {
        final json = {'content-type': 'application/json'};
        if (r.url.path.endsWith('/api/v1/calendar/day')) return http.Response(dayBody, 200, headers: json);
        if (r.method == 'POST') {
          posts.add(r.url.path);
          if (r.url.path.contains('/api/v1/today/do-now/')) {
            if (doNowFails) return http.Response('{"detail": "boom"}', 500, headers: json);
            if (!doNowMoves) {
              return http.Response(jsonEncode({'moved': false, 'message': 'There\'s no free time for it right now, so nothing was changed.'}), 200, headers: json);
            }
            final start = clock.add(const Duration(minutes: 1));
            dayBody = day([row('A', _at(8)), row('B', start), row('C', _at(11))]);
            return http.Response(jsonEncode({
              'moved': true,
              'start_time': start.toUtc().toIso8601String(),
              'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
              'message': 'Moved to now.',
            }), 200, headers: json);
          }
          return http.Response('{}', 200, headers: json);
        }
        if (r.url.path.endsWith('/api/v1/tasks')) {
          final timeline = (jsonDecode(dayBody)['timeline'] as List).cast<Map<String, dynamic>>();
          return http.Response(jsonEncode({
            'items': [
              for (final t in timeline)
                {
                  'id': t['task_id'],
                  'title': t['title'],
                  'estimated_minutes': 30,
                  'status': 'todo',
                  'category': 'Work',
                  'scheduled_start': t['start_time'],
                  'scheduled_end': t['end_time'],
                },
            ],
            'total': timeline.length,
          }), 200, headers: json);
        }
        return http.Response('{}', 200, headers: json);
      }

      final provider = AppStateProvider(
        customApi: ApiService(client: MockClient(handle)),
        initialUser: const AuthUser(id: 'user-polish', email: 'p@flowstate.local', name: 'P', onboardingCompleted: true),
      );
      provider.setOnboardingCompleteForTesting(true);
      provider.setTasksForTesting([task('A', _at(8)), task('B', _at(9)), task('C', _at(11))]);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
        child: const MaterialApp(home: CalendarTab()),
      ));
      await tester.pumpAndSettle();
      return provider;
    }

    Future<void> openStop(WidgetTester tester, String id) async {
      final f = find.byKey(Key('path_stop_sched-$id'));
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
    }

    testWidgets('"Redo now" on a missed stop really moves it: server move, NOW on the path, sheet closes', (tester) async {
      final provider = await pump(tester);
      expect(find.byKey(const Key('path_missed_sched-B')), findsOneWidget, reason: 'B (9:00-9:30) is missed at 10:00');
      await openStop(tester, 'B');
      await tester.tap(find.byKey(const Key('calendar_action_do_now')));
      await tester.pumpAndSettle();
      expect(posts, contains(endsWith('/api/v1/today/do-now/B')));
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing, reason: 'the sheet closes once it is done');
      expect(provider.preferredActiveTaskId, 'B');
      expect(find.byKey(const Key('path_now_sched-B')), findsOneWidget, reason: 'B is the NOW stop');
      final b = provider.tasks.firstWhere((t) => t.id == 'B');
      expect(b.scheduledStart!.isAfter(_at(9, 59)), isTrue, reason: 'the task itself moved to now');
      expect(provider.skippedTaskIds, isEmpty, reason: 'choosing B never records the others as skipped');
    });

    testWidgets('no free time: nothing changes and the pick is not faked', (tester) async {
      final provider = await pump(tester, doNowMoves: false);
      await openStop(tester, 'A');
      await tester.tap(find.byKey(const Key('calendar_action_do_now')));
      await tester.pumpAndSettle();
      expect(provider.preferredActiveTaskId, isNull);
      expect(provider.tasks.firstWhere((t) => t.id == 'A').scheduledStart, _at(8));
    });

    testWidgets('a failed request keeps the sheet open, actionable, and changes nothing', (tester) async {
      final provider = await pump(tester, doNowFails: true);
      await openStop(tester, 'A');
      await tester.tap(find.byKey(const Key('calendar_action_do_now')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsOneWidget);
      expect(provider.preferredActiveTaskId, isNull);
      expect(tester.widget<ListTile>(find.byKey(const Key('calendar_action_do_now'))).enabled, isTrue);
    });

    testWidgets('the stop sheet closes with a swipe down', (tester) async {
      await pump(tester);
      await openStop(tester, 'C');
      await tester.drag(find.byKey(const Key('calendar_stop_sheet_handle')), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);
    });

    testWidgets('the stop sheet closes with the close button and with system back', (tester) async {
      await pump(tester);
      await openStop(tester, 'C');
      await tester.tap(find.byKey(const Key('calendar_stop_sheet_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);

      await openStop(tester, 'C');
      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      await nav.maybePop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_stop_sheet')), findsNothing);
    });

    testWidgets('tapping the Calendar title explains the road in plain words', (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.byKey(const Key('calendar_title_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('calendar_title_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_legend_sheet')), findsOneWidget);
      expect(find.text('Your day is a journey'), findsOneWidget);
      expect(find.textContaining('updates the road as your real day changes'), findsOneWidget);
      await tester.tap(find.byKey(const Key('calendar_legend_close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_legend_sheet')), findsNothing);
    });

    testWidgets('at 320 dp every label is laid out inside its road-free slot', (tester) async {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      await pump(tester);
      for (final id in ['A', 'B', 'C']) {
        final label = find.byKey(Key('path_label_sched-$id'));
        expect(label, findsOneWidget);
        expect(tester.getSize(label).width, greaterThan(60));
      }
      expect(tester.takeException(), isNull);
    });
  });
}
