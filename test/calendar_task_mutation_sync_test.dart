import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/calendar_world.dart';

/// A task changed from another screen (Task Detail, Tasks list, a sheet) must show on Calendar at once, and no read
/// that was already in flight when the change was made may bring the old state back.
///
/// Everything runs through the real chain: scripted backend -> ApiService -> AppStateProvider -> CalendarTab.
/// [CalendarWorld] can hold single responses, so a test can make a read finish after a write.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

const _user = AuthUser(id: 'user-sync', email: 'sync@flowstate.local', name: 'S', onboardingCompleted: true);

void main() {
  late CalendarWorld world;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    FlowClock.debugNowOverride = () => DateTime(_day.year, _day.month, _day.day, 7); // nothing is late
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
    await tester.pumpAndSettle();
    return provider;
  }

  Finder stop(String id) => find.byKey(Key('path_stop_sched-$id'));
  Finder done(String id) => find.byKey(Key('path_check_sched-$id'));
  int stopCount() => find.byWidgetPredicate((w) => w.key.toString().contains('path_stop_')).evaluate().length;

  group('complete from Task Detail', () {
    testWidgets('Calendar shows the completion at once, and still does after the server confirms', (tester) async {
      final provider = await pump(tester);
      expect(done('B'), findsNothing);
      final gate = world.holdNextComplete = Completer<void>(); // the server is slow to confirm

      provider.toggleTaskCompletion('B'); // what Task Detail does when the user finishes
      await tester.pump();
      expect(done('B'), findsOneWidget, reason: 'drawn done immediately, before any server answer');
      expect(stopCount(), 4);

      final reads = world.dayGets;
      gate.complete();
      await tester.pumpAndSettle();
      expect(world.dayGets, greaterThan(reads), reason: 'the confirmed write re-reads the day');
      expect(done('B'), findsOneWidget);
      expect(provider.selectedDateSchedule!.timeline.any((i) => i.taskId == 'B' && i.isCompleted), isTrue,
          reason: 'the provider holds the server\'s confirmed day, not a local guess');
    });

    testWidgets('a task-list refresh that started before the completion cannot undo it', (tester) async {
      final provider = await pump(tester);
      world.holdNextTasks = Completer<void>();
      final staleTasks = world.holdNextTasks!;
      final refresh = provider.refreshAllData(); // pull-to-refresh: its task list is read BEFORE the completion
      await tester.pump();

      final gate = world.holdNextComplete = Completer<void>();
      provider.toggleTaskCompletion('B');
      await tester.pump();
      expect(done('B'), findsOneWidget);

      staleTasks.complete(); // the old list (B still open) lands now
      await refresh;
      await tester.pump();
      expect(done('B'), findsOneWidget, reason: 'an older read must not overwrite the newer local completion');
      expect(provider.tasks.firstWhere((t) => t.id == 'B').isCompleted, isTrue);

      gate.complete();
      await tester.pumpAndSettle();
      expect(done('B'), findsOneWidget);
      expect(provider.tasks.firstWhere((t) => t.id == 'B').isCompleted, isTrue);
    });

    testWidgets('a day read from before the completion that lands late cannot bring the old state back', (tester) async {
      final provider = await pump(tester);
      final staleDay = world.holdNextDay = Completer<void>();
      final stale = provider.loadCalendarDay(provider.selectedCalendarDate, silent: true); // e.g. switching tabs
      await tester.pump();

      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle(); // the completion is confirmed and the day re-read (newest read)
      expect(done('B'), findsOneWidget);

      staleDay.complete(); // the pre-completion day finally arrives
      await stale;
      await tester.pumpAndSettle();
      expect(done('B'), findsOneWidget);
      expect(provider.selectedDateSchedule!.timeline.any((i) => i.taskId == 'B' && i.isCompleted), isTrue);
    });

    testWidgets('a completion the server rejects is rolled back and the day re-read', (tester) async {
      final provider = await pump(tester);
      world.failNextComplete = true;
      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      expect(done('B'), findsNothing, reason: 'Calendar must not keep showing a completion that was never stored');
      expect(provider.tasks.firstWhere((t) => t.id == 'B').isCompleted, isFalse);
      expect(provider.lastSyncError, isNotNull);
    });

    testWidgets('repeated refreshes keep the completed state', (tester) async {
      final provider = await pump(tester);
      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
        await provider.refreshAllData();
        await tester.pumpAndSettle();
        expect(done('B'), findsOneWidget);
      }
    });

    testWidgets('a Today response that arrives late cannot overwrite the newer Calendar day', (tester) async {
      final provider = await pump(tester);
      final staleToday = world.holdNextToday = Completer<void>();
      final today = provider.refreshTodayData();
      await tester.pump();

      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      final day = provider.selectedDateSchedule;
      expect(done('B'), findsOneWidget);

      staleToday.complete();
      await today;
      await tester.pumpAndSettle();
      expect(identical(provider.selectedDateSchedule, day), isTrue, reason: 'Today never writes the Calendar day');
      expect(done('B'), findsOneWidget);
    });
  });

  group('skip, delete and move from another screen', () {
    testWidgets('skip: the stop stays, and shows skipped once the server confirms', (tester) async {
      final provider = await pump(tester);
      final before = tester.getCenter(stop('B'));
      await provider.skipTask('B');
      await tester.pumpAndSettle();
      expect(stopCount(), 4);
      expect(find.byKey(const Key('path_skipped_sched-B')), findsOneWidget);
      expect(tester.getCenter(stop('B')), before);
    });

    testWidgets('delete: the node disappears at once and a read from before the delete cannot bring it back',
        (tester) async {
      final provider = await pump(tester);
      expect(stopCount(), 4);
      world.holdNextDelete = Completer<void>();
      final gate = world.holdNextDelete!;

      provider.removeTask('B');
      await tester.pump();
      await tester.pump();
      expect(stop('B'), findsNothing, reason: 'gone immediately');
      expect(stopCount(), 3);

      gate.complete(); // the server deletes it
      await tester.pumpAndSettle();
      expect(stop('B'), findsNothing, reason: 'a day read taken before the delete must not resurrect it');
      expect(stopCount(), 3);
      expect(provider.selectedDateSchedule!.timeline.any((i) => i.taskId == 'B'), isFalse);
    });

    testWidgets('move to another day: it leaves today at once and is on the new day', (tester) async {
      final provider = await pump(tester);
      final gate = world.holdNextPatch = Completer<void>();
      final moved = provider.rescheduleTask('B', targetDate: _day.add(const Duration(days: 1)));
      await tester.pump();
      await tester.pump();
      expect(stop('B'), findsNothing, reason: 'the old day drops it immediately, not after the server answers');
      expect(stopCount(), 3);

      gate.complete();
      expect(await moved, isTrue);
      await tester.pumpAndSettle();
      expect(stop('B'), findsNothing);
      expect(stopCount(), 3);

      await provider.loadCalendarDay(_day.add(const Duration(days: 1)));
      await tester.pumpAndSettle();
      expect(stop('B'), findsOneWidget);
    });

    testWidgets('a move the server rejects brings the node back', (tester) async {
      final provider = await pump(tester);
      world.failNextPatch = true;
      final moved = await provider.rescheduleTask('B', targetDate: _day.add(const Duration(days: 1)));
      await tester.pumpAndSettle();
      expect(moved, isFalse);
      expect(stop('B'), findsOneWidget);
      expect(stopCount(), 4);
    });
  });

  group('Replan moves', () {
    ApplyReplanRequest request(Map<String, double> hours, {required Map<String, String> intents}) =>
        ApplyReplanRequest.fromServerJson({
          'plan_id': 'plan-1',
          'selected_date': world.dateStr(0),
          'task_updates': [
            for (final e in hours.entries)
              {
                'task_id': e.key,
                'scheduled_start': world.at(e.value).toUtc().toIso8601String(),
                'scheduled_end': world.at(e.value + 0.5).toUtc().toIso8601String(),
              },
          ],
          'intents': intents,
        });

    double y(WidgetTester tester, String id) => tester.getCenter(stop(id)).dy;

    testWidgets('an explicit move takes its new place; a collateral move keeps its place on the path', (tester) async {
      final provider = await pump(tester);
      expect([for (final id in ['A', 'B', 'C', 'D']) y(tester, id)], orderedEquals([...[for (final id in ['A', 'B', 'C', 'D']) y(tester, id)]]..sort()));
      final before = {for (final id in ['A', 'B', 'C', 'D']) id: y(tester, id)};

      // "move D to 8:30": D is explicit. B is pushed from 10:00 to 13:00 only to make room (collateral).
      await provider.applyReplan(PlanDiff(
        planId: 'plan-1',
        selectedDate: world.dateStr(0),
        serverApplyRequest: request({'D': 8.5, 'B': 13}, intents: {'D': 'rescheduled'}),
      ));
      await tester.pumpAndSettle();

      expect(stopCount(), 4, reason: 'nothing duplicated or lost');
      final ys = {for (final id in ['A', 'B', 'C', 'D']) id: y(tester, id)};
      expect(ys['D']!, lessThan(ys['A']!), reason: 'the explicit move takes its new place: first');
      expect(ys['A']!, lessThan(ys['B']!));
      expect(ys['B']!, lessThan(ys['C']!), reason: 'the collateral B was not thrown past C by being pushed to 13:00');
      expect(before['B']! < before['C']!, isTrue);
    });

    testWidgets('a Replan that moves a task to another day removes it from this day and keeps the others in place', (tester) async {
      final provider = await pump(tester);
      final before = {for (final id in ['A', 'C', 'D']) id: y(tester, id)};
      world.tasks['B']!.day = 1; // the server moved B to tomorrow
      await provider.applyReplan(PlanDiff(
        planId: 'plan-2',
        selectedDate: world.dateStr(0),
        serverApplyRequest: request({'C': 11}, intents: {'B': 'rescheduled'}),
      ));
      await tester.pumpAndSettle();
      expect(stop('B'), findsNothing);
      expect(stopCount(), 3);
      expect(y(tester, 'A'), lessThan(y(tester, 'C')));
      expect(y(tester, 'C'), lessThan(y(tester, 'D')));
      expect(before.keys, containsAll(['A', 'C', 'D']));
    });
  });
}
