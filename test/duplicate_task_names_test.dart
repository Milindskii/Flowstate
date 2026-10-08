import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/schedule_item.dart';
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

/// Two tasks can share a name ("Gym" today and "Gym" tomorrow). Identity is the id, never the title: finishing
/// tomorrow's Gym early must not hide, complete or open today's.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();
const _user = AuthUser(id: 'user-dup', email: 'dup@flowstate.local', name: 'D', onboardingCompleted: true);

ScheduleItem _item(String taskId, String title) => ScheduleItem.fromJson({
      'id': 'sched-$taskId',
      'task_id': taskId,
      'title': title,
      'time': '5:00',
      'period': 'PM',
      'duration_minutes': 30,
      'type': 'physical',
      'tag_text': 'PHYSICAL',
    });

TaskItem _task(String id, String title) => TaskItem.fromJson({'id': id, 'title': title, 'status': 'todo'});

void main() {
  late CalendarWorld world;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    FlowClock.debugNowOverride = () => DateTime(_day.year, _day.month, _day.day, 10, 5);
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    world = CalendarWorld(_day)
      ..serveToday = true
      ..add('report', 10, title: 'Write report')
      ..add('gym_today', 17, title: 'Gym')
      ..add('gym_tomorrow', 17, day: 1, title: 'Gym', done: true); // finished early
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  Future<AppStateProvider> load() async {
    final p = AppStateProvider(customApi: ApiService(client: MockClient(world.handle)), initialUser: _user)
      ..setOnboardingCompleteForTesting(true);
    await p.loadUserTasks();
    await p.refreshTodayData();
    return p;
  }

  testWidgets('Today: UP NEXT still lists today\'s Gym when tomorrow\'s Gym is already done', (tester) async {
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
    await provider.loadUserTasks();
    await provider.refreshTodayData();
    await tester.pumpAndSettle();

    expect(provider.tasks.where((t) => t.title == 'Gym' && t.isCompleted).length, 1, reason: 'tomorrow\'s is done');
    expect(find.text('Gym'), findsWidgets, reason: 'today\'s Gym is open and must be listed');
  });

  testWidgets('Today: the server\'s recommendation is not dropped because a same-named task elsewhere is done', (tester) async {
    world.recommendId = 'gym_today';
    final provider = await load();
    expect(provider.recommendedTask?.id, 'gym_today');
  });

  group('Calendar: which task a stop opens', () {
    test('the id wins over a same-named task', () {
      final tasks = [_task('gym_tomorrow', 'Gym'), _task('gym_today', 'Gym')];
      expect(CalendarTab.taskBehind(tasks, _item('gym_today', 'Gym'))?.id, 'gym_today');
    });

    test('a title is only a fallback when it names exactly one task', () {
      final unique = [_task('a', 'Write report'), _task('gym', 'Gym')];
      expect(CalendarTab.taskBehind(unique, _item('unknown-id', 'Gym'))?.id, 'gym');
    });

    test('an unknown id and an ambiguous title open nothing rather than the wrong one', () {
      final dupes = [_task('gym_tomorrow', 'Gym'), _task('gym_today', 'Gym')];
      expect(CalendarTab.taskBehind(dupes, _item('unknown-id', 'Gym')), isNull);
    });
  });
}
