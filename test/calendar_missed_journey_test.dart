import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/screens/insights_history_screen.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/calendar_world.dart';

/// The Calendar road is the user's actual journey through the planned day. A slot that passes unfinished becomes
/// MISSED on its own (no Skip needed), its node stays in its timeline slot, and the road swings around it to the next
/// task. Every state change reaches the route MODEL (the geometry the painter draws), not only the node.
///
/// Planned: 9 ML, 11 DSA, 3 Gym, 5 Flowstate. The user does ML, ignores DSA, does Gym and Flowstate.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();
const _user = AuthUser(id: 'user-journey', email: 'journey@flowstate.local', name: 'J', onboardingCompleted: true);

DateTime _at(double hour, {int day = 0}) =>
    _day.add(Duration(days: day, minutes: (hour * 60).round()));

void main() {
  late CalendarWorld world;
  late DateTime clock;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    clock = _at(9, day: 0).add(const Duration(minutes: 10)); // 9:10, ML is under way
    FlowClock.debugNowOverride = () => clock;
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    world = CalendarWorld(_day)
      ..add('ML', 9, title: 'ML')
      ..add('DSA', 11, title: 'DSA')
      ..add('Gym', 15, title: 'Gym')
      ..add('Flow', 17, title: 'Flowstate');
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  Future<AppStateProvider> pump(WidgetTester tester) async {
    final provider = AppStateProvider(customApi: ApiService(client: MockClient(world.handle)), initialUser: _user);
    provider.setOnboardingCompleteForTesting(true);
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();
    await provider.loadCalendarDay(provider.selectedCalendarDate);
    await provider.loadUserTasks();
    await tester.pumpAndSettle();
    return provider;
  }

  /// Time passes: the minute tick every Calendar listens to.
  Future<void> advanceTo(WidgetTester tester, double hour, {int minute = 0}) async {
    clock = _at(hour).add(Duration(minutes: minute));
    FlowClock().debugTick();
    await tester.pumpAndSettle();
  }

  DayRouteGeometry route(WidgetTester tester) =>
      (tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter).geometry;
  StopGeometry stop(WidgetTester tester, String id) => route(tester).stopById('sched-$id');
  StopRouteRole role(WidgetTester tester, String id) => stop(tester, id).role;
  List<String> order(WidgetTester tester) => [for (final s in route(tester).stops) s.id];

  /// How far the painted road is from the stop's node centre, measured on the road at the node's height.
  double roadOffset(WidgetTester tester, String id) {
    final s = stop(tester, id);
    return (route(tester).routeXAt(s.center.dy) - s.center.dx).abs();
  }

  Future<void> doMl(WidgetTester tester, AppStateProvider provider) async {
    provider.toggleTaskCompletion('ML');
    await tester.pumpAndSettle();
  }

  group('a slot that passes unfinished', () {
    testWidgets('becomes MISSED by itself: no skip, no server write', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      expect(role(tester, 'DSA'), StopRouteRole.onRoute, reason: 'its slot has not come yet');

      await advanceTo(tester, 11, minute: 45); // DSA 11:00-11:30 is over, unfinished

      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(role(tester, 'Gym'), StopRouteRole.onRoute, reason: 'later slots are untouched');
      expect(provider.skippedTaskIdsOn(_day), isEmpty, reason: 'ordinary failure to follow the plan is not a skip');
      expect(world.calls.where((c) => c.contains('/skip/')), isEmpty);
      expect(find.byKey(const Key('path_tags_sched-DSA')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Missed'));
    });

    testWidgets('keeps its node in the timeline slot: nothing moves, nothing goes to the end', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      final before = {for (final s in route(tester).stops) s.id: s.center};
      final orderBefore = order(tester);

      await advanceTo(tester, 11, minute: 45);

      expect(order(tester), orderBefore, reason: 'ML, DSA, Gym, Flowstate: chronological, DSA still second');
      expect(order(tester), ['sched-ML', 'sched-DSA', 'sched-Gym', 'sched-Flow']);
      for (final s in route(tester).stops) {
        expect(s.center, before[s.id], reason: '${s.id} stays exactly where it was planned');
      }
    });

    testWidgets('the road bends around the missed node and carries on to the next task', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      expect(roadOffset(tester, 'DSA'), lessThan(0.5), reason: 'planned: the road runs through DSA');
      final plannedXs = List<double>.from(route(tester).sampleXs);

      await advanceTo(tester, 11, minute: 45);

      final geo = route(tester);
      final dsa = stop(tester, 'DSA');
      expect(roadOffset(tester, 'DSA'), closeTo(DayRouteGeometry.detourDistance, 0.5), reason: 'it swings past DSA');
      expect(geo.distanceToRoute(dsa.center), greaterThan(DayRouteGeometry.nodeRadius + 10),
          reason: 'the road never runs under the node');
      expect(roadOffset(tester, 'ML'), lessThan(0.5), reason: 'it still comes from ML...');
      expect(roadOffset(tester, 'Gym'), lessThan(0.5), reason: '...and arrives at Gym');
      expect(roadOffset(tester, 'Flow'), lessThan(0.5));
      expect(geo.sampleXs, isNot(plannedXs), reason: 'the route MODEL was regenerated, not just repainted');
      // the road into the bypassed stop was walked: the journey went on to Gym
      expect(geo.sampleStates.contains(RouteSegmentState.traveled), isTrue);
    });

    testWidgets('finishing it later takes it off the missed state and back onto the road, as a recovery', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 11, minute: 45);
      expect(role(tester, 'DSA'), StopRouteRole.bypassed);

      provider.toggleTaskCompletion('DSA');
      await tester.pumpAndSettle();

      expect(role(tester, 'DSA'), StopRouteRole.recovered, reason: 'done after its slot passed: not "on plan"');
      expect(roadOffset(tester, 'DSA'), lessThan(0.5), reason: 'the road runs through the finished stop again');
      expect(route(tester).sampleStates.contains(RouteSegmentState.recovered), isTrue);
      expect(find.byKey(const Key('path_check_sched-DSA')), findsOneWidget);
      expect(find.byKey(const Key('path_tags_sched-DSA')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Recovered'));
      expect(order(tester), ['sched-ML', 'sched-DSA', 'sched-Gym', 'sched-Flow'], reason: 'still in its own slot');
    });

    testWidgets('finishing a task INSIDE its slot is on plan, not a recovery', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      expect(role(tester, 'ML'), StopRouteRole.onRoute);
    });
  });

  group('skip is not missed', () {
    testWidgets('an explicit skip is its own state with its own label, next to a missed stop', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 11, minute: 45);

      await provider.skipTask('Gym');
      await tester.pumpAndSettle();

      expect(role(tester, 'Gym'), StopRouteRole.skipped);
      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(role(tester, 'Gym'), isNot(role(tester, 'DSA')));
      expect(provider.skippedTaskIdsOn(_day), {'Gym'}, reason: 'only the explicit skip is a skip');
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-Gym'))).textSpan!.toPlainText(), contains('Skipped'));
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Missed'));
      expect(roadOffset(tester, 'Gym'), closeTo(DayRouteGeometry.detourDistance, 0.5), reason: 'the road goes round a skip too');
    });
  });

  group('the day ends', () {
    testWidgets('an unfinished task is a red, unfinished stop at its own slot', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 11, minute: 45);
      expect(find.byKey(const Key('path_failed_sched-DSA')), findsNothing, reason: 'still recoverable during the day');

      await advanceTo(tester, 23, minute: 59); // past bedtime: the day is over

      expect(role(tester, 'DSA'), StopRouteRole.failed);
      expect(find.byKey(const Key('path_failed_sched-DSA')), findsOneWidget, reason: 'the red node');
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Unfinished'));
      expect(order(tester), ['sched-ML', 'sched-DSA', 'sched-Gym', 'sched-Flow']);
      expect(roadOffset(tester, 'DSA'), closeTo(DayRouteGeometry.detourDistance, 0.5));
    });
  });

  group('the route model follows every change at once', () {
    testWidgets('completion: a held server answer does not delay the road', (tester) async {
      final provider = await pump(tester);
      await advanceTo(tester, 11, minute: 45);
      final gate = world.holdNextComplete = Completer<void>();
      expect(role(tester, 'ML'), StopRouteRole.bypassed, reason: 'ML was never done: missed too');

      provider.toggleTaskCompletion('ML');
      await tester.pump();

      expect(role(tester, 'ML'), StopRouteRole.recovered, reason: 'drawn before the server answers');
      expect(roadOffset(tester, 'ML'), lessThan(0.5));
      gate.complete();
      await tester.pumpAndSettle();
      expect(role(tester, 'ML'), StopRouteRole.recovered);
    });

    testWidgets('skip: the node and the road change before the server answers', (tester) async {
      final provider = await pump(tester);
      final gate = world.holdNextSkip = Completer<void>();
      expect(roadOffset(tester, 'Gym'), lessThan(0.5));

      final done = provider.skipTask('Gym');
      await tester.pump();

      expect(role(tester, 'Gym'), StopRouteRole.skipped);
      expect(roadOffset(tester, 'Gym'), closeTo(DayRouteGeometry.detourDistance, 0.5));
      gate.complete();
      await done;
      await tester.pumpAndSettle();
      expect(role(tester, 'Gym'), StopRouteRole.skipped, reason: 'the confirmed day agrees');
    });

    testWidgets('replan: the new plan is the new road', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 11, minute: 45);
      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(roadOffset(tester, 'DSA'), greaterThan(DayRouteGeometry.nodeRadius));

      // Replan puts the missed DSA back into the evening, after Gym
      await provider.applyReplan(PlanDiff(
        planId: 'p1',
        selectedDate: world.dateStr(0),
        movedTasks: const [TaskDiffItem(taskId: 'DSA', title: 'DSA', changeType: 'moved')],
        serverApplyRequest: ApplyReplanRequest(planId: 'p1', selectedDate: world.dateStr(0), raw: {
          'plan_id': 'p1',
          'selected_date': world.dateStr(0),
          'task_updates': [
            {'task_id': 'DSA', 'scheduled_start': world.at(16).toUtc().toIso8601String()},
          ],
          'new_tasks': <dynamic>[],
          'cancelled_task_ids': <dynamic>[],
          'intents': {'DSA': 'rescheduled'},
        }),
      ));
      await tester.pumpAndSettle();

      expect(order(tester), ['sched-ML', 'sched-Gym', 'sched-DSA', 'sched-Flow']);
      expect(role(tester, 'DSA'), StopRouteRole.onRoute, reason: 'a future slot again: no longer missed');
      expect(roadOffset(tester, 'DSA'), lessThan(0.5), reason: 'the road runs through it in its new place');
    });

    testWidgets('delete: removing the missed stop closes the detour', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 11, minute: 45);
      final before = route(tester).sampleYs.length;

      provider.removeTask('DSA');
      await tester.pumpAndSettle();

      expect(order(tester), ['sched-ML', 'sched-Gym', 'sched-Flow']);
      expect(route(tester).sampleYs.length, lessThan(before));
      for (final s in route(tester).stops) {
        expect((route(tester).routeXAt(s.center.dy) - s.center.dx).abs(), lessThan(0.5), reason: '${s.id}: a straight run again');
      }
    });

    testWidgets('app resume: coming back after the slot passed recalculates the state', (tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      expect(role(tester, 'DSA'), StopRouteRole.onRoute);

      // The app was in the background: no minute tick was delivered while the clock moved on.
      clock = _at(11, day: 0).add(const Duration(minutes: 45));
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(roadOffset(tester, 'DSA'), closeTo(DayRouteGeometry.detourDistance, 0.5));
    });
  });

  group('recovery starts from where the traveller really was', () {
    // ML 9, DSA 11, Gym 15, Flowstate 17. The user does ML, never touches DSA (no "Do this later"), then Gym and
    // Flowstate, and only afterwards finishes DSA.
    Future<AppStateProvider> doEverythingButDsa(WidgetTester tester) async {
      final provider = await pump(tester);
      await doMl(tester, provider);
      await advanceTo(tester, 15, minute: 10);
      provider.toggleTaskCompletion('Gym');
      await tester.pumpAndSettle();
      await advanceTo(tester, 17, minute: 10);
      provider.toggleTaskCompletion('Flow');
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('B is bypassed without "Do this later" while the others are completed, and the route continues', (tester) async {
      await doEverythingButDsa(tester);
      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(world.calls.where((c) => c.contains('/skip/')), isEmpty, reason: 'nothing was skipped by hand');
      expect(roadOffset(tester, 'DSA'), closeTo(DayRouteGeometry.detourDistance, 0.5), reason: 'the road bends around B');
      expect(roadOffset(tester, 'Gym'), lessThan(0.5), reason: 'and carries on through the later tasks');
      expect(roadOffset(tester, 'Flow'), lessThan(0.5));
      expect(order(tester), ['sched-ML', 'sched-DSA', 'sched-Gym', 'sched-Flow'], reason: 'B keeps its place');
      expect(route(tester).branches, isEmpty);
    });

    testWidgets('finishing B last draws the orange way back from Flowstate (the latest position), never from ML', (tester) async {
      final provider = await doEverythingButDsa(tester);
      await advanceTo(tester, 18);
      final slotBefore = stop(tester, 'DSA').center;

      provider.toggleTaskCompletion('DSA');
      await tester.pumpAndSettle();

      final g = route(tester);
      expect(role(tester, 'DSA'), StopRouteRole.recovered);
      expect(g.stopById('sched-DSA').detached, isTrue);
      expect(g.stopById('sched-DSA').center, slotBefore, reason: 'B stays at its original timeline position');
      expect(g.branches, hasLength(1));
      expect((g.branches.single.fromId, g.branches.single.toId), ('sched-Flow', 'sched-DSA'));
      expect(g.sampleStates, isNot(contains(RouteSegmentState.recovered)), reason: 'ML -> DSA never happened');
      expect(roadOffset(tester, 'DSA'), closeTo(DayRouteGeometry.detourDistance, 0.5), reason: 'the main road still bends around B');
      expect(find.byKey(const Key('path_check_sched-DSA')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Recovered'));
    });

    testWidgets('undoing the recovery recomputes the route: B is missed again and the orange branch is gone', (tester) async {
      final provider = await doEverythingButDsa(tester);
      await advanceTo(tester, 18);
      provider.toggleTaskCompletion('DSA');
      await tester.pumpAndSettle();
      expect(route(tester).branches, hasLength(1));

      provider.toggleTaskCompletion('DSA'); // undo
      await tester.pumpAndSettle();

      expect(route(tester).branches, isEmpty);
      expect(role(tester, 'DSA'), StopRouteRole.bypassed);
      expect(find.byKey(const Key('path_tags_sched-DSA')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('path_tags_sched-DSA'))).textSpan!.toPlainText(), contains('Missed'));
    });
  });

  group('History tells done, skipped and missed apart', () {
    TaskItem task(String id, double hour, {bool done = false, int day = 0}) => TaskItem(
          id: id,
          title: id,
          durationMinutes: 30,
          difficulty: TaskDifficulty.medium,
          deadline: 'Today',
          category: 'Work',
          isCompleted: done,
          scheduledStart: _at(hour, day: day),
          scheduledEnd: _at(hour + 0.5, day: day),
          plannedDate: _day.add(Duration(days: day)),
          completedAt: done ? _at(hour + 0.2, day: day) : null,
        );

    final yesterdayPlan = [
      task('ML', 9, done: true, day: -1),
      task('DSA', 11, day: -1),
      task('Gym', 15, done: true, day: -1),
      task('Flowstate', 17, done: true, day: -1),
    ];

    test('after the day: ML, Gym and Flowstate are done, DSA is NOT DONE', () {
      final days = HistoryDay.from(tasks: yesterdayPlan, reflections: const [], now: _at(8));
      expect(days, hasLength(1));
      final day = days.single;
      expect(day.entries.map((e) => e.title), ['ML', 'Gym', 'Flowstate']);
      expect(day.unfinished.map((m) => m.title), ['DSA']);
      final dsa = day.unfinished.single;
      expect(dsa.outcome, HistoryOutcome.missed);
      expect(dsa.dayOver, isTrue);
      expect(dsa.label, 'Not done');
      expect(dsa.plannedStart, _at(11, day: -1), reason: 'planned vs actual: it keeps its planned slot');
      expect(day.missedCount, 1);
      expect(day.skippedCount, 0);
    });

    test('a missed task is never counted as finished', () {
      final days = HistoryDay.from(tasks: yesterdayPlan, reflections: const [], now: _at(8));
      expect(days.single.entries.map((e) => e.taskId), isNot(contains('DSA')));
      expect(days.single.totalMinutes, 90);
    });

    test('an explicit skip is a different outcome from a miss', () {
      final skipped = task('DSA', 17, day: 1); // the server moved it to tomorrow evening
      final days = HistoryDay.from(
        tasks: [yesterdayPlan[0], skipped, yesterdayPlan[2]],
        reflections: const [],
        now: _at(8),
        skippedOn: {'DSA': _day.subtract(const Duration(days: 1))},
      );
      final day = days.firstWhere((d) => d.date == _day.subtract(const Duration(days: 1)));
      expect(day.unfinished.single.outcome, HistoryOutcome.skipped);
      expect(day.unfinished.single.label, 'Skipped');
      expect(day.skippedCount, 1);
      expect(day.missedCount, 0);
    });

    test('while the day is still open it reads Missed (recoverable); once over, Not done', () {
      final open = HistoryDay.from(
        tasks: [task('DSA', 11)],
        reflections: const [],
        now: _at(11, day: 0).add(const Duration(minutes: 45)),
      );
      expect(open.single.unfinished.single.label, 'Missed');
      expect(open.single.unfinished.single.dayOver, isFalse);

      final before = HistoryDay.from(tasks: [task('DSA', 11)], reflections: const [], now: _at(10));
      expect(before, isEmpty, reason: 'the slot has not come: nothing to report');
    });

    test('completing a missed task moves it out of the not-done list', () {
      final days = HistoryDay.from(
        tasks: [for (final t in yesterdayPlan) t.id == 'DSA' ? t.copyWith(isCompleted: true, completedAt: _at(20, day: -1)) : t],
        reflections: const [],
        now: _at(8),
      );
      expect(days.single.unfinished, isEmpty);
      expect(days.single.entries, hasLength(4));
    });

    testWidgets('the History screen lists ML done and DSA as Not done', (tester) async {
      tester.view.physicalSize = const Size(412, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      clock = _at(8);
      final state = AppStateProvider()..setTasksForTesting(yesterdayPlan);
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsHistoryScreen()),
      ));
      await tester.pumpAndSettle();

      expect(find.text('3 finished · 1 not done · 1h 30m'), findsOneWidget);
      await tester.tap(find.text('Yesterday'));
      await tester.pumpAndSettle();

      final dsa = find.byKey(const Key('history_unfinished_DSA_missed'));
      expect(dsa, findsOneWidget);
      expect(find.descendant(of: dsa, matching: find.textContaining('Not done')), findsOneWidget);
      expect(find.text('ML'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
      expect(find.text('Flowstate'), findsOneWidget);
    });
  });
}
