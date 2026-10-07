import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import 'package:flowstate/components/companion/noya_reaction_controller.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/components/primary_button.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/calendar_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// D1: assert path stop presence and title for FlowDayPath canonical rendering
void expectRowState(WidgetTester tester, {required String state, required String id, required String title, String? label}) {
  final stop = find.byKey(Key('path_stop_$id'));
  expect(stop, findsOneWidget, reason: '$state stop for $id');
  expect(find.descendant(of: stop, matching: find.text(title)), findsOneWidget);
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  group('Task 1: Calendar Data & Date Navigation Tests', () {
    test('1. DayScheduleResponse.fromJson correctly parses backend schema', () {
      final jsonPayload = {
        'date': '2026-10-02',
        'is_today': false,
        'is_past': false,
        'timeline': [
          {
            'id': 'sched-dentist',
            'task_id': 'task-dentist-1',
            'title': 'Dentist Appointment',
            'start_time': '2026-10-02T18:00:00+05:30',
            'end_time': '2026-10-02T18:45:00+05:30',
            'time': '6:00',
            'period': 'PM',
            'duration_minutes': 45,
            'type': 'meeting',
            'tag_text': 'FIXED',
            'is_fixed': true,
            'is_completed': false,
            'is_active': false,
            'is_conflict': false,
          },
          {
            'id': 'sched-urgent',
            'task_id': 'task-urgent-1',
            'title': 'Urgent Report',
            'start_time': '2026-10-02T19:00:00+05:30',
            'end_time': '2026-10-02T20:00:00+05:30',
            'time': '7:00',
            'period': 'PM',
            'duration_minutes': 60,
            'type': 'deep_work',
            'tag_text': 'DEEP WORK',
            'is_fixed': false,
            'is_completed': false,
          },
        ],
        'fixed_commitments': [
          {
            'id': 'sched-dentist',
            'task_id': 'task-dentist-1',
            'title': 'Dentist Appointment',
            'time': '6:00',
            'period': 'PM',
            'duration_minutes': 45,
            'type': 'meeting',
            'tag_text': 'FIXED',
            'is_fixed': true,
          }
        ],
        'completed_tasks': [],
        'remaining_tasks': [],
        'unscheduled_tasks': [
          {
            'id': 'unsched-gym',
            'task_id': 'task-gym-1',
            'title': 'Gym Session',
            'time': '--:--',
            'period': '',
            'duration_minutes': 60,
            'type': 'physical',
            'tag_text': 'UNSCHEDULED',
            'is_conflict': true,
            'explanation': 'Could not be fitted into schedule',
          }
        ],
        'conflicts': [],
        'workload': {
          'planned_minutes': 105,
          'formatted_workload': '1h 45m planned',
          'message': 'Your day looks manageable.',
          'is_overloaded': false,
          'available_minutes': 400,
        },
        'focus_window': '9:30 AM – 11:30 AM',
        'readiness_score': 82,
        'total_planned_minutes': 105,
        'remaining_capacity_minutes': 400,
      };

      final response = DayScheduleResponse.fromJson(jsonPayload);

      expect(response.date, '2026-10-02');
      expect(response.isToday, isFalse);
      expect(response.timeline.length, 2);
      expect(response.timeline[0].title, 'Dentist Appointment');
      expect(response.timeline[0].isFixed, isTrue);
      expect(response.timeline[0].tagText, 'FIXED');
      expect(response.timeline[1].title, 'Urgent Report');
      expect(response.timeline[1].isFixed, isFalse);
      expect(response.unscheduledTasks.length, 1);
      expect(response.unscheduledTasks[0].title, 'Gym Session');
      expect(response.focusWindow, '9:30 AM – 11:30 AM');
      expect(response.readinessScore, 82);
    });

    test('2. CalendarService.getDaySchedule queries /api/v1/calendar/day with correct date parameter', () async {
      String? requestedUrl;
      final mockClient = MockClient((request) async {
        requestedUrl = request.url.toString();
        if (request.url.path == '/api/v1/calendar/day') {
          final targetDate = request.url.queryParameters['date'] ?? '2026-10-02';
          return http.Response(
            jsonEncode({
              'date': targetDate,
              'is_today': false,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-1',
                  'title': 'Test Item for $targetDate',
                  'time': '10:00',
                  'period': 'AM',
                  'duration_minutes': 45,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
              'workload': {'planned_minutes': 45},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiService = ApiService(client: mockClient);
      final calendarService = CalendarService(api: apiService);

      final result = await calendarService.getDaySchedule('2026-10-05', timezone: 'Asia/Kolkata');

      expect(requestedUrl, contains('/api/v1/calendar/day'));
      expect(requestedUrl, contains('date=2026-10-05'));
      expect(requestedUrl, contains('timezone=Asia%2FKolkata'));
      expect(result.date, '2026-10-05');
      expect(result.timeline.first.title, 'Test Item for 2026-10-05');
    });

    test('3. AppStateProvider.loadCalendarDay clears stale data immediately and sets authoritative timeline', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final date = request.url.queryParameters['date'];
          return http.Response(
            jsonEncode({
              'date': date,
              'is_today': false,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-$date',
                  'title': 'Schedule for $date',
                  'time': '3:00',
                  'period': 'PM',
                  'duration_minutes': 60,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      final dateA = DateTime(2026, 10, 2);
      final dateB = DateTime(2026, 10, 3);

      // Load date A
      await provider.loadCalendarDay(dateA);
      expect(provider.selectedDateSchedule?.date, '2026-10-02');
      expect(provider.selectedDateSchedule?.timeline.first.title, 'Schedule for 2026-10-02');

      // Now start loading date B — verify loading state and stale data cleared
      final loadFuture = provider.loadCalendarDay(dateB);
      // Immediately after triggering, stale data must be cleared
      expect(provider.selectedDateSchedule, isNull);
      expect(provider.isLoadingCalendarDay, isTrue);

      await loadFuture;
      expect(provider.isLoadingCalendarDay, isFalse);
      expect(provider.selectedDateSchedule?.date, '2026-10-03');
      expect(provider.selectedDateSchedule?.timeline.first.title, 'Schedule for 2026-10-03');
    });

    test('4. Local fallback schedule never uses deadline_at as scheduled_start or falls back to midnight', () {
      final provider = AppStateProvider();
      provider.clearAllTasksForNewUserState();

      // Add a task with deadline on Friday, but NO scheduledStart
      final targetFriday = DateTime(2026, 10, 2);
      final taskWithOnlyDeadline = TaskItem(
        id: 't-deadline-only',
        title: 'Project Submission',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Friday',
        category: 'Work',
        deadlineAt: DateTime(2026, 10, 2, 23, 59),
        scheduledStart: null, // NOT scheduled!
      );

      // Add a task with real scheduledStart on Friday at 2:00 PM
      final scheduledTask = TaskItem(
        id: 't-scheduled',
        title: 'Team Sync',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Friday',
        category: 'Work',
        scheduledStart: DateTime(2026, 10, 2, 14, 0),
        scheduledEnd: DateTime(2026, 10, 2, 14, 45),
      );

      // Set internal tasks list for test
      provider.setTasksForTesting([taskWithOnlyDeadline, scheduledTask]);

      // Trigger load for demo/offline
      provider.setDemoMode(true);
      provider.loadCalendarDay(targetFriday);

      final items = provider.selectedDateSchedule!.timeline;
      // Must contain ONLY the task with real scheduledStart; deadline-only task must NOT appear as midnight
      expect(items.any((i) => i.title == 'Project Submission'), isFalse);
      expect(items.any((i) => i.title == 'Team Sync'), isTrue);
      final syncItem = items.firstWhere((i) => i.title == 'Team Sync');
      expect(syncItem.time, isNot('12:00')); // Not fake midnight
      expect(syncItem.time, '2:00');
      expect(syncItem.period, 'PM');
    });

    testWidgets('5. CalendarTab widget renders authoritative timeline and responds to date navigation', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        final date = request.url.queryParameters['date'] ?? 'today';
        return http.Response(
          jsonEncode({
            'date': date,
            'is_today': true,
            'is_past': false,
            'timeline': [
              {
                'id': 'sched-dentist-fixed',
                'title': 'Dentist Appointment',
                'time': '6:00',
                'period': 'PM',
                'duration_minutes': 45,
                'type': 'meeting',
                'tag_text': 'FIXED',
                'is_fixed': true,
                'is_completed': false,
              }
            ],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [
              {
                'id': 'unsched-gym',
                'title': 'Evening Workout',
                'time': '--:--',
                'period': '',
                'duration_minutes': 60,
                'type': 'physical',
                'tag_text': 'UNSCHEDULED',
                'is_conflict': true,
                'explanation': 'Insufficient capacity before bedtime',
              }
            ],
            'conflicts': [],
            'focus_window': '10:00 AM – 12:00 PM',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );

      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();

      // Verify Dentist is shown as Fixed on path
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expect(find.textContaining('6:00 PM'), findsOneWidget);
      expectRowState(tester, state: 'fixed', id: 'sched-dentist-fixed', title: 'Dentist Appointment', label: 'Fixed');

      // Verify unscheduled item is also rendered on day path
      expect(find.text('Evening Workout'), findsOneWidget);
      expectRowState(tester, state: 'unscheduled', id: 'unsched-gym', title: 'Evening Workout', label: 'Unscheduled');

      // Verify focus window is rendered as one line
      expect(find.text('Focus window 10:00 AM – 12:00 PM'), findsOneWidget);
      semantics.dispose();

      // Now tap tomorrow in the horizontal date strip
      await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
      await tester.pumpAndSettle();

      // Timeline must re-render for the selected day
      expect(find.text('Dentist Appointment'), findsOneWidget);
    });

    testWidgets('6. Visual States: Clearly distinguishes FIXED, FLOWSTATE, NOW, COMPLETED, CONFLICT, and UNSCHEDULED with proper hierarchy', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'date': '2026-10-02',
            'is_today': true,
            'is_past': false,
            'timeline': [
              {
                'id': 'sched-done',
                'title': 'Morning Meditation',
                'time': '8:00',
                'period': 'AM',
                'duration_minutes': 20,
                'type': 'rest',
                'tag_text': 'REST',
                'is_completed': true,
              },
              {
                'id': 'sched-now',
                'title': 'Urgent Deep Work',
                'time': '9:30',
                'period': 'AM',
                'duration_minutes': 60,
                'type': 'deep_work',
                'tag_text': 'DEEP WORK',
                'is_active': true,
                'explanation': 'Peak energy focus window',
              },
              {
                'id': 'sched-flowstate',
                'title': 'Write Documentation',
                'time': '11:00',
                'period': 'AM',
                'duration_minutes': 45,
                'type': 'deep_work',
                'tag_text': 'DEEP WORK',
                'is_fixed': false,
                'explanation': 'Aligned with focus window',
              },
              {
                'id': 'sched-fixed',
                'title': 'Dentist Appointment',
                'time': '2:00',
                'period': 'PM',
                'duration_minutes': 45,
                'type': 'meeting',
                'tag_text': 'FIXED',
                'is_fixed': true,
                'explanation': 'Requested fixed time',
              },
              {
                'id': 'sched-conflict',
                'title': 'Overlapping Client Call',
                'time': '2:15',
                'period': 'PM',
                'duration_minutes': 30,
                'type': 'meeting',
                'tag_text': 'CONFLICT',
                'is_conflict': true,
                'explanation': 'Direct conflict with Dentist Appointment',
              },
            ],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [
              {
                'id': 'unsched-extra',
                'title': 'Gym Session',
                'time': '--:--',
                'period': '',
                'duration_minutes': 60,
                'type': 'physical',
                'tag_text': 'UNSCHEDULED',
                'explanation': 'Could not fit before bedtime',
              }
            ],
            'conflicts': [],
            'focus_window': '9:30 AM – 11:30 AM',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );

      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();

      // 1. COMPLETED: title on path stop
      expect(find.text('Morning Meditation'), findsOneWidget);
      expectRowState(tester, state: 'completed', id: 'sched-done', title: 'Morning Meditation');

      // 2. NOW: active row on path stop
      expect(find.text('Urgent Deep Work'), findsOneWidget);
      expectRowState(tester, state: 'now', id: 'sched-now', title: 'Urgent Deep Work', label: 'NOW');

      // 3. Default: placed on path
      expect(find.text('Write Documentation'), findsOneWidget);

      // 4. FIXED: Fixed item on path
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expectRowState(tester, state: 'fixed', id: 'sched-fixed', title: 'Dentist Appointment', label: 'Fixed');

      // 5. CONFLICT: Conflict item on path
      expect(find.text('Overlapping Client Call'), findsOneWidget);
      expectRowState(tester, state: 'conflict', id: 'sched-conflict', title: 'Overlapping Client Call', label: 'Conflict');

      // 6. UNSCHEDULED: Unscheduled item on path
      expect(find.text('Gym Session'), findsOneWidget);
      expectRowState(tester, state: 'unscheduled', id: 'unsched-extra', title: 'Gym Session', label: 'Unscheduled');
      semantics.dispose();
    });

    testWidgets('7. Empty State: Displays dynamic day plan prompt and Build My Day opens Brain Dump flow', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'date': '2026-10-02',
            'is_today': true,
            'is_past': false,
            'timeline': [],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [],
            'conflicts': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(
        customApi: api,
        initialUser: const AuthUser(
          id: 'u1',
          email: 'test@example.com',
          name: 'Tester',
          onboardingCompleted: true,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify empty state text
      expect(find.textContaining('No plan for'), findsOneWidget);
      expect(find.textContaining("Tell Flowstate what you need to get done and we'll build the day."), findsOneWidget);
      expect(find.text('Build My Day'), findsOneWidget);

      // Scroll into view & Tap [Build My Day]
      await tester.ensureVisible(find.text('Build My Day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build My Day'));
      await tester.pumpAndSettle();

      // Verify Brain Dump sheet opened
      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);
    });
  });

  group('Phase 2: Adversarial Date Test Matrix (Tests 1 to 14)', () {
    testWidgets('TEST 1: Open Calendar on today\'s date displays today\'s tasks immediately', (WidgetTester tester) async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          return http.Response(
            jsonEncode({
              'date': todayStr,
              'is_today': true,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-today-1',
                  'title': 'Deep Work Session Today',
                  'time': '10:00',
                  'period': 'AM',
                  'duration_minutes': 60,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Deep Work Session Today'), findsOneWidget);
      expect(find.textContaining('10:00 AM'), findsOneWidget);
    });

    testWidgets('TEST 2: Tap tomorrow immediately loads and displays tomorrow\'s tasks', (WidgetTester tester) async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final reqDate = request.url.queryParameters['date'];
          if (reqDate == tomorrowStr) {
            return http.Response(
              jsonEncode({
                'date': tomorrowStr,
                'is_today': false,
                'is_past': false,
                'timeline': [
                  {
                    'id': 'sched-tomorrow-1',
                    'title': 'Tomorrow Planning Session',
                    'time': '11:00',
                    'period': 'AM',
                    'duration_minutes': 45,
                    'type': 'planning',
                    'tag_text': 'TASK',
                  }
                ],
                'fixed_commitments': [],
                'completed_tasks': [],
                'remaining_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'date': todayStr,
              'is_today': true,
              'is_past': false,
              'timeline': [],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
      await tester.pumpAndSettle();

      expect(find.text('Tomorrow Planning Session'), findsOneWidget);
    });

    testWidgets('TEST 3: Tap yesterday immediately loads and displays yesterday\'s tasks', (WidgetTester tester) async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final yesterdayStr = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final reqDate = request.url.queryParameters['date'];
          if (reqDate == yesterdayStr) {
            return http.Response(
              jsonEncode({
                'date': yesterdayStr,
                'is_today': false,
                'is_past': true,
                'timeline': [
                  {
                    'id': 'sched-yesterday-1',
                    'title': 'Yesterday Retrospective',
                    'time': '5:00',
                    'period': 'PM',
                    'duration_minutes': 30,
                    'type': 'review',
                    'tag_text': 'TASK',
                  }
                ],
                'fixed_commitments': [],
                'completed_tasks': [],
                'remaining_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            jsonEncode({
              'date': todayStr,
              'is_today': true,
              'is_past': false,
              'timeline': [],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('calendar_day_chip_yesterday')));
      await tester.pumpAndSettle();

      expect(find.text('Yesterday Retrospective'), findsOneWidget);
    });

    testWidgets('TEST 4: Today -> Tomorrow -> Today correctly restores each date\'s data', (WidgetTester tester) async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(now.add(const Duration(days: 1)));

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final reqDate = request.url.queryParameters['date'];
          final isTmrw = reqDate == tomorrowStr;
          return http.Response(
            jsonEncode({
              'date': reqDate,
              'is_today': reqDate == todayStr,
              'is_past': false,
              'timeline': [
                {
                  'id': isTmrw ? 'sched-tmrw' : 'sched-today',
                  'title': isTmrw ? 'Task for Tomorrow' : 'Task for Today',
                  'time': '9:00',
                  'period': 'AM',
                  'duration_minutes': 45,
                  'type': 'work',
                  'tag_text': 'TASK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Task for Today'), findsOneWidget);
      expect(find.text('Task for Tomorrow'), findsNothing);

      // Tap Tomorrow
      await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
      await tester.pumpAndSettle();
      expect(find.text('Task for Tomorrow'), findsOneWidget);
      expect(find.text('Task for Today'), findsNothing);

      // Tap Today
      await tester.tap(find.byKey(const Key('calendar_day_chip_today')));
      await tester.pumpAndSettle();
      expect(find.text('Task for Today'), findsOneWidget);
      expect(find.text('Task for Tomorrow'), findsNothing);
    });

    testWidgets('TEST 5: Multi-day navigation produces no stale data', (WidgetTester tester) async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);
      final day2 = today.add(const Duration(days: 2));
      final day3 = today.add(const Duration(days: 3));

      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final day2Str = DateFormat('yyyy-MM-dd').format(day2);
      final day3Str = DateFormat('yyyy-MM-dd').format(day3);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final reqDate = request.url.queryParameters['date'];
          return http.Response(
            jsonEncode({
              'date': reqDate,
              'is_today': reqDate == todayStr,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-$reqDate',
                  'title': 'Unique Schedule for $reqDate',
                  'time': '2:00',
                  'period': 'PM',
                  'duration_minutes': 60,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Unique Schedule for $todayStr'), findsOneWidget);

      // Tap Day 2
      await tester.tap(find.byKey(Key('calendar_day_chip_$day2Str')));
      await tester.pumpAndSettle();
      expect(find.text('Unique Schedule for $day2Str'), findsOneWidget);
      expect(find.text('Unique Schedule for $todayStr'), findsNothing);

      // Tap Day 3
      await tester.tap(find.byKey(Key('calendar_day_chip_$day3Str')));
      await tester.pumpAndSettle();
      expect(find.text('Unique Schedule for $day3Str'), findsOneWidget);
      expect(find.text('Unique Schedule for $day2Str'), findsNothing);

      // Return to Today
      await tester.tap(find.byKey(const Key('calendar_day_chip_today')));
      await tester.pumpAndSettle();
      expect(find.text('Unique Schedule for $todayStr'), findsOneWidget);
      expect(find.text('Unique Schedule for $day3Str'), findsNothing);
    });

    test('TEST 6: Rapidly switching dates discards older async responses using request generation tokens', () async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final dayAfter = today.add(const Duration(days: 2));

      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);
      final dayAfterStr = DateFormat('yyyy-MM-dd').format(dayAfter);

      // Simulate network delays: Tomorrow is slow (100ms), DayAfter is slow (60ms), Today is fast (10ms)
      final mockClient = MockClient((request) async {
        final reqDate = request.url.queryParameters['date'];
        if (reqDate == tomorrowStr) {
          await Future.delayed(const Duration(milliseconds: 100));
        } else if (reqDate == dayAfterStr) {
          await Future.delayed(const Duration(milliseconds: 60));
        } else {
          await Future.delayed(const Duration(milliseconds: 10));
        }
        return http.Response(
          jsonEncode({
            'date': reqDate,
            'is_today': reqDate == todayStr,
            'is_past': false,
            'timeline': [
              {
                'id': 'sched-$reqDate',
                'title': 'Response for $reqDate',
                'time': '1:00',
                'period': 'PM',
                'duration_minutes': 60,
                'type': 'work',
                'tag_text': 'TASK',
              }
            ],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [],
            'conflicts': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));

      // Rapidly fire requests: Tomorrow -> DayAfter -> Today
      final fTomorrow = provider.loadCalendarDay(tomorrow);
      final fDayAfter = provider.loadCalendarDay(dayAfter);
      final fToday = provider.loadCalendarDay(today);

      await Future.wait([fTomorrow, fDayAfter, fToday]);

      // Final selected date MUST win:
      expect(provider.selectedDateSchedule?.date, todayStr);
      expect(provider.selectedDateSchedule?.timeline.first.title, 'Response for $todayStr');
    });

    testWidgets('TEST 7: Selected date with no tasks shows empty state without stale data', (WidgetTester tester) async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final tomorrowStr = DateFormat('yyyy-MM-dd').format(tomorrow);

      final mockClient = MockClient((request) async {
        final reqDate = request.url.queryParameters['date'];
        if (reqDate == todayStr) {
          return http.Response(
            jsonEncode({
              'date': todayStr,
              'is_today': true,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-busy',
                  'title': 'Heavy Focus Session',
                  'time': '9:00',
                  'period': 'AM',
                  'duration_minutes': 90,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'date': tomorrowStr,
            'is_today': false,
            'is_past': false,
            'timeline': [],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [],
            'conflicts': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Heavy Focus Session'), findsOneWidget);

      // Tap Tomorrow (empty day)
      await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
      await tester.pumpAndSettle();

      expect(find.text('Heavy Focus Session'), findsNothing);
      expect(find.textContaining('No plan for'), findsOneWidget);
      expect(find.text('Build My Day'), findsOneWidget);
    });

    testWidgets('TEST 8: Selected date with completed tasks renders them with line-through and a check node', (WidgetTester tester) async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'date': todayStr,
            'is_today': true,
            'is_past': false,
            'timeline': [
              {
                'id': 'sched-done-1',
                'title': 'Morning Team Huddle',
                'time': '8:30',
                'period': 'AM',
                'duration_minutes': 30,
                'type': 'meeting',
                'tag_text': 'COMPLETED',
                'is_completed': true,
              }
            ],
            'fixed_commitments': [],
            'completed_tasks': [],
            'remaining_tasks': [],
            'unscheduled_tasks': [],
            'conflicts': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        MaterialApp(
          home: ChangeNotifierProvider<AppStateProvider>.value(
            value: provider,
            child: const CalendarTab(),
          ),
        ),
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();

      expect(find.text('Morning Team Huddle'), findsOneWidget);
      expectRowState(tester, state: 'completed', id: 'sched-done-1', title: 'Morning Team Huddle');
      semantics.dispose();
    });

    test('TEST 9: Reschedule a task from Date A to Date B clears Date A and places on Date B', () async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      final provider = AppStateProvider();
      provider.setDemoMode(true);

      final task = TaskItem(
        id: 'task-move-1',
        title: 'Important Financial Review',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Finance',
        scheduledStart: DateTime(today.year, today.month, today.day, 10, 0),
        scheduledEnd: DateTime(today.year, today.month, today.day, 11, 0),
      );

      provider.setTasksForTesting([task]);

      // Check Date A (today)
      await provider.loadCalendarDay(today);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Important Financial Review'), isTrue);

      // Reschedule to Date B (tomorrow at 3 PM)
      await provider.rescheduleTask(
        'task-move-1',
        targetDate: tomorrow,
        targetTime: const TimeOfDay(hour: 15, minute: 0),
      );

      // Check Date A (today) — task must be gone from today
      await provider.loadCalendarDay(today);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Important Financial Review'), isFalse);

      // Check Date B (tomorrow) — task must now appear on tomorrow
      await provider.loadCalendarDay(tomorrow);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Important Financial Review'), isTrue);
    });

    test('TEST 10: Task mutations (create, edit, complete, delete) refresh calendar schedule', () async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);

      final provider = AppStateProvider();
      provider.setDemoMode(true);
      provider.clearAllTasksForNewUserState();

      // Load calendar day for today (initially empty)
      await provider.loadCalendarDay(today);
      expect(provider.selectedDateSchedule!.timeline, isEmpty);

      // 1. Add Task
      final created = await provider.addTask(
        title: 'Sprint Planning',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );
      // Give it a scheduled start on today so it appears in day timeline
      provider.updateTask(created.copyWith(
        scheduledStart: DateTime(today.year, today.month, today.day, 11, 0),
        scheduledEnd: DateTime(today.year, today.month, today.day, 11, 45),
      ));
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Sprint Planning'), isTrue);

      // 2. Edit Task
      final updated = created.copyWith(
        title: 'Sprint Planning Updated',
        scheduledStart: DateTime(today.year, today.month, today.day, 11, 0),
        scheduledEnd: DateTime(today.year, today.month, today.day, 11, 45),
      );
      provider.updateTask(updated);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Sprint Planning Updated'), isTrue);

      // 3. Complete Task
      provider.toggleTaskCompletion(created.id);
      expect(provider.selectedDateSchedule!.timeline.firstWhere((t) => t.taskId == created.id).isCompleted, isTrue);

      // 4. Delete Task
      provider.removeTask(created.id);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.taskId == created.id), isFalse);
    });

    test('TEST 11: Leaving Calendar tab and returning preserves selected date and triggers fresh load', () async {
      final now = FlowClock().now;
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      final provider = AppStateProvider();
      provider.setDemoMode(true);

      // Navigate to Calendar tab and select Tomorrow
      provider.setNavIndex(2);
      await provider.loadCalendarDay(tomorrow);
      expect(provider.selectedCalendarDate.day, tomorrow.day);

      // Leave Calendar tab to Today tab (index 0)
      provider.setNavIndex(0);
      expect(provider.currentNavIndex, 0);

      // Return to Calendar tab (index 2)
      provider.setNavIndex(2);
      expect(provider.currentNavIndex, 2);
      expect(provider.selectedCalendarDate.day, tomorrow.day);
      expect(provider.selectedDateSchedule, isNotNull);
    });

    test('TEST 12: Restarting/rebuilding app restores persisted calendar data correctly', () async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          return http.Response(
            jsonEncode({
              'date': todayStr,
              'is_today': true,
              'is_past': false,
              'timeline': [
                {
                  'id': 'sched-persisted-1',
                  'title': 'Persisted Database Task',
                  'time': '10:00',
                  'period': 'AM',
                  'duration_minutes': 45,
                  'type': 'deep_work',
                  'tag_text': 'DEEP WORK',
                }
              ],
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      // Simulate fresh app launch
      final freshProvider = AppStateProvider(customApi: ApiService(client: mockClient));
      await freshProvider.loadCalendarDay(now);

      expect(freshProvider.selectedDateSchedule, isNotNull);
      expect(freshProvider.selectedDateSchedule!.timeline.first.title, 'Persisted Database Task');
    });

    test('TEST 13: User A and User B calendars are strictly isolated across sign out/sign in', () async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final authHeader = request.headers['Authorization'] ?? '';
          if (authHeader.contains('token-user-a')) {
            return http.Response(
              jsonEncode({
                'date': todayStr,
                'is_today': true,
                'is_past': false,
                'timeline': [
                  {
                    'id': 'sched-user-a',
                    'title': 'Secret User A Task',
                    'time': '9:00',
                    'period': 'AM',
                    'duration_minutes': 60,
                    'type': 'work',
                    'tag_text': 'TASK',
                  }
                ],
                'fixed_commitments': [],
                'completed_tasks': [],
                'remaining_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          } else if (authHeader.contains('token-user-b')) {
            return http.Response(
              jsonEncode({
                'date': todayStr,
                'is_today': true,
                'is_past': false,
                'timeline': [
                  {
                    'id': 'sched-user-b',
                    'title': 'Confidential User B Task',
                    'time': '2:00',
                    'period': 'PM',
                    'duration_minutes': 30,
                    'type': 'work',
                    'tag_text': 'TASK',
                  }
                ],
                'fixed_commitments': [],
                'completed_tasks': [],
                'remaining_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response('Unauthorized', 401);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      // Authenticate User A
      api.setAuthToken('token-user-a');
      await provider.onUserAuthenticated(const AuthUser(id: 'u-a', email: 'a@test.com', name: 'User A', onboardingCompleted: true));
      await provider.loadCalendarDay(now);

      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Secret User A Task'), isTrue);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Confidential User B Task'), isFalse);

      // Logout User A
      await provider.logout();
      expect(provider.selectedDateSchedule, isNull);
      expect(provider.dayScheduleCache, isEmpty);

      // Authenticate User B
      api.setAuthToken('token-user-b');
      await provider.onUserAuthenticated(const AuthUser(id: 'u-b', email: 'b@test.com', name: 'User B', onboardingCompleted: true));
      await provider.loadCalendarDay(now);

      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Confidential User B Task'), isTrue);
      expect(provider.selectedDateSchedule!.timeline.any((t) => t.title == 'Secret User A Task'), isFalse);
    });

    test('TEST 14: Switching back to User A completely restores User A\'s calendar', () async {
      final now = FlowClock().now;
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/calendar/day') {
          final authHeader = request.headers['Authorization'] ?? '';
          if (authHeader.contains('token-user-a')) {
            return http.Response(
              jsonEncode({
                'date': todayStr,
                'is_today': true,
                'is_past': false,
                'timeline': [
                  {
                    'id': 'sched-user-a',
                    'title': 'Secret User A Task',
                    'time': '9:00',
                    'period': 'AM',
                    'duration_minutes': 60,
                    'type': 'work',
                    'tag_text': 'TASK',
                  }
                ],
                'fixed_commitments': [],
                'completed_tasks': [],
                'remaining_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
        }
        return http.Response('Unauthorized', 401);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      // Log in as User A again
      api.setAuthToken('token-user-a');
      await provider.onUserAuthenticated(const AuthUser(id: 'u-a', email: 'a@test.com', name: 'User A', onboardingCompleted: true));
      await provider.loadCalendarDay(now);

      expect(provider.selectedDateSchedule!.timeline.first.title, 'Secret User A Task');
    });
  });

  group('M2 Task 14: Calendar refinement (B2.2–B2.7, §7.1, §8.4–8.5, D4, D10)', () {
    Map<String, dynamic> row(String id, String title, String time, String period, {int minutes = 45}) => {
          'id': id,
          'title': title,
          'time': time,
          'period': period,
          'duration_minutes': minutes,
          'type': 'deep_work',
          'tag_text': 'DEEP WORK',
        };

    String dayJson(String date, List<Map<String, dynamic>> timeline, {String? focus}) => jsonEncode({
          'date': date,
          'is_today': false,
          'is_past': false,
          'timeline': timeline,
          'fixed_commitments': [],
          'completed_tasks': [],
          'remaining_tasks': [],
          'unscheduled_tasks': [],
          'conflicts': [],
          if (focus != null) 'focus_window': focus,
        });

    Future<AppStateProvider> pumpCalendar(
      WidgetTester tester,
      Future<http.Response> Function(http.Request) handler, {
      ThemeProvider? theme,
      bool settle = true,
    }) async {
      final provider = AppStateProvider(customApi: ApiService(client: MockClient(handler)));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: provider),
          if (theme != null) ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: const MaterialApp(home: CalendarTab()),
      ));
      if (settle) await tester.pumpAndSettle();
      return provider;
    }

    http.Response ok(String body) => http.Response(body, 200, headers: {'content-type': 'application/json'});

    testWidgets('Replan hidden on empty day', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [])));
      expect(find.byKey(const Key('calendar_replan_button')), findsNothing);
      expect(find.textContaining('Replan'), findsNothing);
    });

    testWidgets('Replan is a compact tonal header action when the day has items', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [row('a', 'Write outline', '9:30', 'AM')])));
      final replan = find.byKey(const Key('calendar_replan_button'));
      expect(replan, findsOneWidget);
      expect(find.descendant(of: replan, matching: find.text('Replan')), findsOneWidget);
      expect(find.descendant(of: replan, matching: find.byIcon(Icons.auto_awesome_rounded)), findsOneWidget);
      expect(find.textContaining('✨'), findsNothing);
      expect(find.byType(PrimaryButton), findsNothing);
      // Header row: level with the "Calendar" title, right-aligned.
      expect((tester.getCenter(replan).dy - tester.getCenter(find.text('Calendar')).dy).abs(), lessThan(24));
      expect(tester.getTopRight(replan).dx, greaterThan(tester.getTopRight(find.text('Calendar')).dx));
      expect(find.text('Flowstate detects changes/conflicts and builds a new feasible schedule.'), findsNothing);
    });

    testWidgets('exactly one filled button in empty state', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [])));
      expect(find.byType(PrimaryButton), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Build My Day'), findsOneWidget);
    });

    testWidgets('empty state shows NoyaMotionView, unboxed, and greets once per session', (tester) async {
      final provider = await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [])));
      final noya = find.byType(NoyaMotionView);
      expect(noya, findsOneWidget);
      final view = tester.widget<NoyaMotionView>(noya);
      expect(view.size, 72);
      expect(view.enter, isTrue);
      expect(find.byIcon(Icons.event_note_outlined), findsNothing);
      // Today's empty-state mood follows the real clock (no clock override exists): wind-down
      // from 20:00 with no greet (§7.1, D5), otherwise rest with one greet per session.
      final evening = FlowClock().now.hour >= 20;
      expect(view.mood, evening ? NoyaMood.windDown : NoyaMood.rest);
      if (evening) {
        expect(view.reactions?.value, isNull);
      } else {
        expect(view.reactions?.value?.reaction, NoyaReaction.greet);
      }
      final firstGreet = view.reactions!.value?.id;

      // Another empty day in the same session: no second greet (and tomorrow rests; it never greets twice).
      await tester.tap(find.byKey(const Key('calendar_day_chip_tomorrow')));
      await tester.pumpAndSettle();
      final tomorrowView = tester.widget<NoyaMotionView>(find.byType(NoyaMotionView));
      expect(tomorrowView.mood, NoyaMood.rest);
      if (!evening) expect(tomorrowView.reactions!.value!.id, firstGreet);
      final afterTomorrow = tomorrowView.reactions!.value?.id;
      await tester.tap(find.byKey(const Key('calendar_day_chip_today')));
      await tester.pumpAndSettle();
      expect(tester.widget<NoyaMotionView>(find.byType(NoyaMotionView)).reactions!.value?.id, afterTomorrow);
      expect(provider.selectedCalendarDate.day, FlowClock().now.day);

      // The empty state is not a bordered card.
      final ancestors = tester.widgetList<Container>(find.ancestor(of: noya, matching: find.byType(Container)));
      expect(ancestors.any((c) => c.decoration is BoxDecoration && (c.decoration as BoxDecoration).border != null), isFalse);
    });

    test('empty-state mood: rest by day, wind-down on an evening today (D5), rest on other days', () {
      expect(CalendarTab.emptyMoodFor(DateTime(2026, 10, 2, 10), isToday: true), NoyaMood.rest);
      expect(CalendarTab.emptyMoodFor(DateTime(2026, 10, 2, 20), isToday: true), NoyaMood.windDown);
      expect(CalendarTab.emptyMoodFor(DateTime(2026, 10, 2, 21), isToday: false), NoyaMood.rest);
    });

    testWidgets("focus window rendered as one line 'Focus window 10:00 AM – 12:00 PM' ≤ 32dp", (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [row('a', 'Write outline', '9:30', 'AM')], focus: '10:00 AM – 12:00 PM')));
      final line = find.byKey(const Key('calendar_focus_window'));
      expect(line, findsOneWidget);
      expect(find.descendant(of: line, matching: find.text('Focus window 10:00 AM – 12:00 PM')), findsOneWidget);
      expect(find.descendant(of: line, matching: find.byIcon(Icons.bolt_rounded)), findsOneWidget);
      expect(tester.getSize(line).height, lessThanOrEqualTo(32));
      expect(find.text('Optimal Focus Window'), findsNothing);
    });

    testWidgets('rows starting inside the focus window get rendered on path', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [
            row('in', 'Inside', '10:30', 'AM'),
            row('out', 'Outside', '1:00', 'PM'),
          ], focus: '10:00 AM – 12:00 PM')));
      expect(find.byKey(const Key('path_stop_in')), findsOneWidget);
      expect(find.byKey(const Key('path_stop_out')), findsOneWidget);
    });

    testWidgets('loading shows skeleton, no CircularProgressIndicator', (tester) async {
      final gate = Completer<http.Response>();
      await pumpCalendar(tester, (r) => gate.future, settle: false);
      await tester.pump();
      expect(find.byKey(const Key('calendar_loading_skeleton')), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      gate.complete(ok(dayJson(DateFormat('yyyy-MM-dd').format(FlowClock().now), [])));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('calendar_loading_skeleton')), findsNothing);
    });

    testWidgets('date change slides content from +16px when moving forward, −16px backward', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [row('a-${r.url.queryParameters['date']}', 'Task', '9:30', 'AM')])));
      final restX = tester.getTopLeft(find.byKey(const Key('calendar_day_content'))).dx;

      Future<double> offsetAfterTap(String chip) async {
        await tester.tap(find.byKey(Key(chip)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final incoming = find.byKey(const Key('calendar_day_content')).last;
        final dx = tester.getTopLeft(incoming).dx - restX;
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byKey(const Key('calendar_day_content'))).dx, restX);
        return dx;
      }

      final forward = await offsetAfterTap('calendar_day_chip_tomorrow');
      expect(forward, greaterThan(4));
      expect(forward, lessThanOrEqualTo(16));
      final backward = await offsetAfterTap('calendar_day_chip_today');
      expect(backward, lessThan(-4));
      expect(backward, greaterThanOrEqualTo(-16));
    });

    testWidgets('renders all path stops on day schedule', (tester) async {
      await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, [
            row('a', 'First', '9:30', 'AM'),
            row('b', 'Second', '11:00', 'AM'),
          ])));
      expect(find.byKey(const Key('path_stop_a')), findsOneWidget);
      expect(find.byKey(const Key('path_stop_b')), findsOneWidget);
    });

    testWidgets('row inserted after reload updates schedule correctly', (tester) async {
      var rows = [row('a', 'Stays', '9:30', 'AM'), row('b', 'Leaves', '11:00', 'AM')];
      final provider = await pumpCalendar(tester, (r) async => ok(dayJson(r.url.queryParameters['date']!, rows)));
      rows = [row('a', 'Stays', '9:30', 'AM'), row('c', 'Arrives', '1:00', 'PM')];

      unawaited(provider.loadCalendarDay(provider.selectedCalendarDate));
      await tester.pumpAndSettle();
      expect(find.text('Leaves'), findsNothing);
      expect(find.text('Arrives'), findsOneWidget);
    });
  });

  group('Calendar history path', () {
    Map<String, dynamic> row(String id, String title, String time, String period, {bool completed = false, String? taskId}) => {
          'id': id,
          if (taskId != null) 'task_id': taskId,
          'title': title,
          'time': time,
          'period': period,
          'duration_minutes': 60,
          'type': 'physical',
          'tag_text': completed ? 'COMPLETED' : 'PHYSICAL',
          'is_completed': completed,
        };

    Future<AppStateProvider> pumpPath(WidgetTester tester, List<Map<String, dynamic>> timeline) async {
      final provider = AppStateProvider(customApi: ApiService(client: MockClient((r) async => http.Response(
            jsonEncode({
              'date': r.url.queryParameters['date'],
              'is_today': false,
              'is_past': false,
              'timeline': timeline,
              'fixed_commitments': [],
              'completed_tasks': [],
              'remaining_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': [],
            }),
            200,
            headers: {'content-type': 'application/json'},
          ))));
      await tester.pumpWidget(MaterialApp(
        home: ChangeNotifierProvider<AppStateProvider>.value(value: provider, child: const CalendarTab()),
      ));
      await tester.pumpAndSettle();
      return provider;
    }

    testWidgets('Calendar opens on the day path unconditionally', (tester) async {
      await pumpPath(tester, [row('comp-gym', 'Gym', '7:00', 'AM', completed: true, taskId: 'gym'), row('sched-read', 'Read', '9:00', 'PM')]);
      expect(find.byKey(const Key('flow_day_path_line')), findsOneWidget);
      // a task's stop keeps one identity whatever its state (done here): sched-<task id>
      expect(find.byKey(const Key('path_stop_sched-gym')), findsOneWidget);
      expect(find.byKey(const Key('path_stop_sched-read')), findsOneWidget);
    });

    testWidgets('tapping a finished stop opens its history with the reflection recorded on this device', (tester) async {
      final provider = await pumpPath(tester, [row('comp-gym', 'Gym', '7:00', 'AM', completed: true, taskId: 'gym')]);
      await provider.reflectionsReady;
      provider.setTasksForTesting([
        const TaskItem(id: 'gym', title: 'Gym', durationMinutes: 60, difficulty: TaskDifficulty.medium, deadline: 'Today', category: 'Fitness'),
      ]);
      provider.recordTaskFeedback(
        taskId: 'gym', actualMinutes: 50, feeling: 3, energyScore: 4, focusScore: 3, difficultyScore: 2, distractionScore: 2,
        completedAt: DateTime(2026, 10, 3, 8, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('Done 8:00 AM · 50 min'), findsOneWidget);
      // Category comes from the task, feeling from the reflection.
      expect(find.text('Fitness · Felt good'), findsOneWidget);

      await tester.tap(find.byKey(const Key('path_node_sched-gym')));
      await tester.pumpAndSettle();
      final sheet = find.byKey(const Key('history_moment_sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('Good')), findsOneWidget);
      expect(find.byKey(const Key('history_signal_energy_4')), findsOneWidget);
    });
  });
}
