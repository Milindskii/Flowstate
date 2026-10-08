import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/calendar_world.dart';

/// Midnight: a task planned for tomorrow becomes TODAY's, and nothing keeps the old relative day.
///
/// One source of truth: the device's local date (FlowClock). When it changes, the provider moves the selected
/// Calendar day, drops yesterday's cached days and Today payload, and re-reads both from the server.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();
DateTime _at(int dayOffset, int hour, [int minute = 0, int second = 0]) =>
    DateTime(_day.year, _day.month, _day.day + dayOffset, hour, minute, second);

const _user = AuthUser(id: 'user-roll', email: 'roll@flowstate.local', name: 'R', onboardingCompleted: true);

void main() {
  late CalendarWorld world;
  late DateTime clock;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    clock = _at(0, 20); // evening of day D
    FlowClock.debugNowOverride = () => clock;
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    world = CalendarWorld(_day)
      ..serveToday = true
      ..add('A', 21) // today, still open
      ..add('T', 10, day: 1); // planned for tomorrow
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  /// Midnight passes: the server's calendar and the device clock both move on.
  void midnight({int minutesAfter = 0}) {
    world.rollOver();
    clock = _at(1, 0, minutesAfter, 30);
  }

  AppStateProvider makeProvider() {
    final p = AppStateProvider(customApi: ApiService(client: MockClient(world.handle)), initialUser: _user);
    p.setOnboardingCompleteForTesting(true);
    return p;
  }

  Future<AppStateProvider> pumpCalendar(WidgetTester tester) async {
    final provider = makeProvider();
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();
    await provider.loadCalendarDay(provider.selectedCalendarDate);
    await provider.refreshTodayData();
    await tester.pumpAndSettle();
    return provider;
  }

  group('provider: the local date changes', () {
    testWidgets('midnight in the foreground: Calendar day, Today payload and "tomorrow" all move on', (tester) async {
      final provider = await pumpCalendar(tester);
      expect(provider.selectedCalendarDate, _at(0, 0));
      expect(provider.todaySnapshot!.tomorrowTasks.map((t) => t.id), ['T']);

      midnight();
      FlowClock().debugTick(); // what the minute timer delivers at 00:00
      await tester.pumpAndSettle();

      expect(provider.selectedCalendarDate, _at(1, 0), reason: 'the day being viewed was today: it follows');
      final day = provider.selectedDateSchedule!;
      expect(day.date, world.dateStr(0));
      expect(day.isToday, isTrue);
      expect(day.timeline.map((i) => i.taskId), ['T'], reason: 'yesterday\'s tomorrow task is on today\'s route now');
      final snapshot = provider.todaySnapshot!;
      expect(snapshot.date, world.dateStr(0));
      expect(snapshot.tomorrowTasks, isEmpty, reason: 'T is not "tomorrow" any more');
      expect(snapshot.upcomingTimeline.map((i) => i.taskId), ['T']);
    });

    testWidgets('the phone slept through midnight, even after ticking on the old day: resume rolls over', (tester) async {
      final provider = await pumpCalendar(tester);
      clock = _at(0, 23, 59, 30);
      FlowClock().debugTick(); // a tick on the OLD day used to stamp "seen today" and defeat the resume check
      await tester.pump();

      world.rollOver();
      clock = _at(1, 7); // woken up the next morning
      provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(provider.selectedCalendarDate, _at(1, 0));
      expect(provider.selectedDateSchedule!.date, world.dateStr(0));
      expect(provider.selectedDateSchedule!.isToday, isTrue);
      expect(provider.todaySnapshot!.tomorrowTasks, isEmpty);
    });

    testWidgets('a day the user navigated to stays selected; stale cached days are dropped', (tester) async {
      final provider = await pumpCalendar(tester);
      await provider.loadCalendarDay(_at(3, 0));
      await tester.pumpAndSettle();
      expect(provider.dayScheduleCache.keys, isNotEmpty);

      midnight();
      FlowClock().debugTick();
      await tester.pumpAndSettle();

      expect(provider.selectedCalendarDate, _at(3, 0), reason: 'the user was looking at another day');
      expect(provider.dayScheduleCache.containsKey(world.dateStr(-1)), isFalse);
      expect(provider.todaySnapshot!.date, world.dateStr(0), reason: 'Today is re-read regardless');
    });

    testWidgets('a tick on the same day does not re-read Today (no churn)', (tester) async {
      final provider = await pumpCalendar(tester);
      final reads = world.todayGets;
      clock = _at(0, 20, 5);
      FlowClock().debugTick();
      await tester.pumpAndSettle();
      expect(world.todayGets, reads);
      expect(provider.selectedCalendarDate, _at(0, 0));
    });

    testWidgets('offline after midnight: yesterday\'s cached Today is NOT shown as today', (tester) async {
      final provider = await pumpCalendar(tester);
      expect(provider.todaySnapshot!.date, world.dateStr(0)); // cached to disk as day D

      midnight();
      world.failToday = true; // the Today read fails: the app would fall back to its cache
      FlowClock().debugTick();
      await tester.pumpAndSettle();

      expect(provider.todaySnapshot, isNull, reason: 'yesterday\'s payload must never stand in for today');
    });

    testWidgets('a LIVE payload is always accepted (the guard only rejects data fetched before today began)',
        (tester) async {
      final provider = await pumpCalendar(tester);
      midnight();
      FlowClock().debugTick();
      await tester.pumpAndSettle();
      expect(provider.todaySnapshot, isNotNull);
      expect(provider.todaySnapshot!.date, world.dateStr(0));
    });
  });

  group('Today tab', () {
    testWidgets('after midnight the TOMORROW section no longer lists the task that is now today', (tester) async {
      final api = ApiService(client: MockClient(world.handle));
      final provider = AppStateProvider(customApi: api, initialUser: _user)..setOnboardingCompleteForTesting(true);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: provider),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
          ChangeNotifierProvider<FlowProvider>.value(value: FlowProvider(api: api)),
        ],
        child: const MaterialApp(home: Scaffold(body: TodayDashboardTab())),
      ));
      await provider.loadCalendarDay(provider.selectedCalendarDate); // subscribes the provider to the clock
      await provider.refreshTodayData();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tomorrow_task_T')), findsOneWidget);

      midnight();
      FlowClock().debugTick();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('tomorrow_task_T')), findsNothing);
      expect(find.byKey(const Key('today_tomorrow_section')), findsNothing);
    });
  });

  group('relative deadline labels are worked out when drawn, not when parsed', () {
    TaskItem task(Map<String, dynamic> json) => TaskItem.fromJson({'id': 't', 'title': 'x', ...json});

    test('tomorrow\'s deadline reads "Due Tomorrow" today and "Due Today" after midnight', () {
      final t = task({'deadline_at': _at(1, 9).toUtc().toIso8601String()});
      expect(t.deadlineLabel, 'Due Tomorrow');
      clock = _at(1, 0, 5);
      expect(t.deadlineLabel, 'Due Today', reason: 'the same task, a day later');
    });

    test('a deadline tomorrow morning is "tomorrow" in the evening (calendar days, not 24-hour spans)', () {
      clock = _at(0, 20);
      expect(task({'deadline_at': _at(1, 9).toUtc().toIso8601String()}).deadlineLabel, 'Due Tomorrow');
      expect(task({'deadline_at': _at(0, 23, 30).toUtc().toIso8601String()}).deadlineLabel, 'Due Today');
    });

    test('a few days out reads as a date, and the user\'s own words are never rewritten', () {
      final far = task({'deadline_at': _at(4, 9).toUtc().toIso8601String()});
      expect(far.deadlineLabel, far.deadline);
      expect(far.deadlineLabel, isNot(startsWith('Due T')));
      final words = TaskItem.fromJson({'id': 't', 'title': 'x', 'deadline': 'Friday evening', 'deadline_at': _at(1, 9).toUtc().toIso8601String()});
      expect(words.deadlineLabel, 'Friday evening');
    });

    test('a task moved to "Tomorrow" is "Today" once that day arrives', () {
      final moved = task({'deadline_at': _at(1, 9).toUtc().toIso8601String()}).copyWith(
        deadline: 'Tomorrow',
        plannedDate: _at(1, 0),
      );
      expect(moved.deadlineLabel, 'Tomorrow');
      clock = _at(1, 0, 5);
      expect(moved.deadlineLabel, 'Today');
    });

    test('month end: Jan 31 to Feb 1', () {
      final jan31 = DateTime(2027, 1, 31, 22);
      final due = DateTime(2027, 2, 1, 9);
      clock = jan31;
      final t = task({'deadline_at': due.toUtc().toIso8601String()});
      expect(t.deadlineLabel, 'Due Tomorrow');
      clock = DateTime(2027, 2, 1, 0, 5);
      expect(t.deadlineLabel, 'Due Today');
    });
  });
}
