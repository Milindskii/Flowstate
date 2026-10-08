import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/calendar_world.dart';

/// The Calendar route is a picture of the user's journey. Every change to a task must reach the painted road by
/// itself (no navigation, no reopening): the painter's geometry is what is asserted, not only the nodes.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();
const _user = AuthUser(id: 'user-route', email: 'route@flowstate.local', name: 'R', onboardingCompleted: true);

void main() {
  late CalendarWorld world;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    FlowClock.debugNowOverride = () => DateTime(_day.year, _day.month, _day.day, 7); // nothing is late yet
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    world = CalendarWorld(_day)
      ..add('A', 9)
      ..add('B', 10)
      ..add('C', 11)
      ..add('D', 12);
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

  DayRouteGeometry route(WidgetTester tester) =>
      (tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter).geometry;

  List<String> order(WidgetTester tester) => [for (final s in route(tester).stops) s.id];
  bool has(WidgetTester tester, RouteSegmentState s) => route(tester).sampleStates.contains(s);
  int amount(WidgetTester tester, RouteSegmentState s) => route(tester).sampleStates.where((x) => x == s).length;

  group('complete (Today, Task Detail and Calendar all call toggleTaskCompletion)', () {
    testWidgets('the travelled road appears, with no navigation', (tester) async {
      final provider = await pump(tester);
      final travelled = amount(tester, RouteSegmentState.traveled); // the road up to NOW is already travelled
      final before = List<RouteSegmentState>.from(route(tester).sampleStates);

      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();

      expect(amount(tester, RouteSegmentState.traveled), greaterThan(travelled), reason: 'more of the road is travelled');
      expect(route(tester).sampleStates, isNot(before), reason: 'the painted road changed');
      expect(route(tester).stopById('sched-B').role, isNot(StopRouteRole.skipped));
    });

    testWidgets('a slow server does not delay the road, and the confirmed day keeps it', (tester) async {
      final provider = await pump(tester);
      final travelled = amount(tester, RouteSegmentState.traveled);
      final gate = world.holdNextComplete = Completer<void>();
      provider.toggleTaskCompletion('B');
      await tester.pump();
      expect(amount(tester, RouteSegmentState.traveled), greaterThan(travelled), reason: 'drawn before the server answers');
      final drawn = amount(tester, RouteSegmentState.traveled);

      gate.complete();
      await tester.pumpAndSettle();
      expect(amount(tester, RouteSegmentState.traveled), drawn, reason: 'the confirmed day draws the same road');
    });

    testWidgets('a completion the server rejects takes the road back', (tester) async {
      final provider = await pump(tester);
      final travelled = amount(tester, RouteSegmentState.traveled);
      world.failNextComplete = true;
      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      expect(amount(tester, RouteSegmentState.traveled), travelled, reason: 'never a road the server does not have');
    });
  });

  group('skip', () {
    testWidgets('the node stays, the skipped stop is on the road, and the task list agrees with the server',
        (tester) async {
      final provider = await pump(tester);
      final stopsBefore = order(tester);

      await provider.skipTask('B');
      await tester.pumpAndSettle();

      expect(order(tester).toSet(), stopsBefore.toSet(), reason: 'no node disappears');
      expect(route(tester).stopById('sched-B').role, StopRouteRole.skipped);
      // the server moved B (+6h); the app's own task list must say so too, or the next projection redraws the old slot
      final serverStart = world.at(world.tasks['B']!.hour);
      final app = provider.tasks.firstWhere((t) => t.id == 'B').scheduledStart;
      expect(app, isNotNull);
      expect(app!.toLocal().hour, serverStart.hour, reason: 'tasks reloaded after the skip');
    });

    testWidgets('skipping while ANOTHER day is on screen marks the skip on the task\'s own day', (tester) async {
      world.add('E', 9, day: 1);
      final provider = await pump(tester);
      await provider.loadCalendarDay(_day.add(const Duration(days: 1)));
      await tester.pumpAndSettle();
      expect(provider.selectedDateSchedule!.timeline.any((i) => i.taskId == 'E'), isTrue);

      await provider.skipTask('E');
      await tester.pumpAndSettle();

      expect(provider.skippedTaskIdsOn(_day.add(const Duration(days: 1))), contains('E'),
          reason: 'the skip belongs to the day the task was on (tomorrow), not to today');
      expect(provider.skippedTaskIdsOn(_day), isNot(contains('E')));
    });
  });

  group('recover', () {
    testWidgets('completing a skipped task turns the road back to it orange', (tester) async {
      final provider = await pump(tester);
      await provider.skipTask('B');
      await tester.pumpAndSettle();
      expect(has(tester, RouteSegmentState.recovered), isFalse);

      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();

      expect(has(tester, RouteSegmentState.recovered), isTrue);
      expect(route(tester).stopById('sched-B').role, StopRouteRole.recovered);
    });

    testWidgets('the recovered road stays after the server answers and after later refreshes', (tester) async {
      final provider = await pump(tester);
      await provider.skipTask('B');
      await tester.pumpAndSettle();
      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
      await provider.refreshAllData();
      await tester.pumpAndSettle();
      expect(has(tester, RouteSegmentState.recovered), isTrue);
    });
  });

  group('reschedule', () {
    testWidgets('moving a task later today re-orders the road', (tester) async {
      final provider = await pump(tester);
      expect(order(tester), ['sched-A', 'sched-B', 'sched-C', 'sched-D']);

      await provider.rescheduleTask('B', targetDate: _day, targetTime: const TimeOfDay(hour: 14, minute: 0));
      await tester.pumpAndSettle();

      expect(order(tester), ['sched-A', 'sched-C', 'sched-D', 'sched-B']);
    });

    testWidgets('moving a task to another day closes the road over it', (tester) async {
      final provider = await pump(tester);
      await provider.rescheduleTask('B', targetDate: _day.add(const Duration(days: 1)));
      await tester.pumpAndSettle();
      expect(order(tester), isNot(contains('sched-B')));
      expect(route(tester).stops.length, 3);
    });
  });

  group('delete', () {
    testWidgets('the node disappears and the road closes over it', (tester) async {
      final provider = await pump(tester);
      final before = route(tester).sampleYs.length;
      provider.removeTask('B');
      await tester.pumpAndSettle();
      expect(order(tester), ['sched-A', 'sched-C', 'sched-D']);
      expect(route(tester).sampleYs.length, lessThan(before), reason: 'a shorter road');
    });
  });
}
