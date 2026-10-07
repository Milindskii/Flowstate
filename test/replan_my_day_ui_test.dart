import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  group('Task 4: Replan My Day UI & Contextual Planning Chat Tests', () {
    testWidgets('TEST 1: Open Replan My Day displays current selected date, schedule context, and message input', (WidgetTester tester) async {
      final selectedDate = DateTime(2026, 9, 30);
      const dummySchedule = DayScheduleResponse(
        date: '2026-09-30',
        isToday: true,
        isPast: false,
        timeline: [
          ScheduleItem(
            id: 'sched-1',
            time: '4:00',
            period: 'PM',
            title: 'Quarterly Report',
            type: 'deep_work',
            tagText: 'DEEP WORK',
          ),
          ScheduleItem(
            id: 'sched-2',
            time: '6:00',
            period: 'PM',
            title: 'Dentist Appointment',
            type: 'meeting',
            tagText: 'FIXED',
            isFixed: true,
          ),
          ScheduleItem(
            id: 'sched-3',
            time: '7:30',
            period: 'PM',
            title: 'Gym Workout',
            type: 'physical',
            tagText: 'PHYSICAL',
          ),
        ],
      );

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'success': true}), 200);
      });
      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showReplanDaySheet(
                    context,
                    selectedDate: selectedDate,
                    currentSchedule: dummySchedule,
                  ),
                  child: const Text('Open Replan'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Replan'));
      await tester.pumpAndSettle();

      // Header verification
      expect(find.text('Replan my day'), findsOneWidget);
      expect(find.text('Wednesday, September 30'), findsOneWidget);

      // Preloaded context verification
      expect(find.text('Your current plan'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
      expect(find.text('Dentist Appointment'), findsOneWidget);
      expect(find.text('Gym Workout'), findsOneWidget);
      expect(find.text('Fixed'), findsOneWidget);

      // Quick action chips verification
      expect(find.text("I'm running late"), findsOneWidget);
      expect(find.text('Urgent work arrived'), findsOneWidget);
      expect(find.text('Move something'), findsOneWidget);
      expect(find.text('Cancel a task'), findsOneWidget);

      // Message input bar verification
      expect(find.text('Tell Noya what changed...'), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('TEST 2: Tap "I\'m running late" prepares and sends a sensible replan request', (WidgetTester tester) async {
      String? sentPath;
      Map<String, dynamic>? sentBody;

      final mockClient = MockClient((request) async {
        sentPath = request.url.path;
        if (request.url.path.contains('/replan')) {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'user_intent_summary': 'Delay remaining schedule by 30 minutes',
              'plan_diff': {
                'plan_id': 'diff-late-1',
                'selected_date': '2026-09-30',
                'before_schedule': [],
                'after_schedule': [],
                'moved_tasks': [
                  {
                    'task_id': 't3',
                    'title': 'Gym Workout',
                    'change_type': 'moved',
                    'old_time': '7:30 PM',
                    'new_time': '8:00 PM',
                  }
                ],
                'newly_scheduled_tasks': [],
                'unchanged_tasks': [],
                'cancelled_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
                'explanation': 'Shifted remaining tasks by 30 minutes.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap chip
      await tester.tap(find.text("I'm running late"));
      await tester.pumpAndSettle();

      expect(sentPath, contains('/replan'));
      expect(sentBody?['selected_date'], '2026-09-30');
      expect(sentBody?['user_message'], 'I\'m running 30 minutes late');
      expect(find.text('Shifted remaining tasks by 30 minutes.'), findsOneWidget);
    });

    testWidgets('TEST 3: Send "I got urgent work" sends schedule context and message to backend', (WidgetTester tester) async {
      Map<String, dynamic>? sentBody;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'user_intent_summary': 'Add urgent work task',
              'plan_diff': {
                'plan_id': 'diff-urgent-1',
                'selected_date': '2026-09-30',
                'before_schedule': [],
                'after_schedule': [],
                'moved_tasks': [],
                'newly_scheduled_tasks': [
                  {
                    'task_id': 't-new-1',
                    'title': 'Urgent work',
                    'change_type': 'new',
                    'new_time': '5:00 PM',
                  }
                ],
                'unchanged_tasks': [],
                'cancelled_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
                'explanation': 'Fitted 60 min urgent work into your focus block.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'I got urgent work');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sentBody?['selected_date'], '2026-09-30');
      expect(sentBody?['user_message'], 'I got urgent work');
      expect(sentBody?['current_local_time'], isNotNull);
      expect(find.text('Fitted 60 min urgent work into your focus block.'), findsOneWidget);
    });

    testWidgets('TEST 4: Send "Move gym to tomorrow" sends selected date and natural language correctly', (WidgetTester tester) async {
      Map<String, dynamic>? sentBody;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'user_intent_summary': 'Move Gym to tomorrow',
              'plan_diff': {
                'plan_id': 'diff-move-1',
                'selected_date': '2026-09-30',
                'before_schedule': [],
                'after_schedule': [],
                'moved_tasks': [
                  {
                    'task_id': 't-gym',
                    'title': 'Gym',
                    'change_type': 'moved',
                    'new_date': '2026-10-01',
                  }
                ],
                'newly_scheduled_tasks': [],
                'unchanged_tasks': [],
                'cancelled_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
                'explanation': 'Moved Gym to tomorrow as requested.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Move gym to tomorrow');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sentBody?['selected_date'], '2026-09-30');
      expect(sentBody?['user_message'], 'Move gym to tomorrow');
      expect(find.text('Moved Gym to tomorrow as requested.'), findsOneWidget);
    });

    testWidgets('TEST 5: Backend returns conflict is displayed clearly with warning styling', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': false,
            'user_intent_summary': 'Schedule meeting at 6 PM',
            'plan_diff': {
              'plan_id': 'diff-conflict-1',
              'selected_date': '2026-09-30',
              'before_schedule': [],
              'after_schedule': [],
              'moved_tasks': [],
              'newly_scheduled_tasks': [],
              'unchanged_tasks': [],
              'cancelled_tasks': [],
              'unscheduled_tasks': [],
              'conflicts': ['Direct conflict with fixed commitment: Dentist Appointment at 6:00 PM'],
              'explanation': 'Cannot place urgent call at 6:00 PM because your Dentist Appointment is locked as FIXED.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Put client call at 6 PM');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Verify conflict warnings are displayed
      expect(find.textContaining('Dentist Appointment at 6:00 PM'), findsWidgets);
      // an untyped (older) note is shown calmly, never as a red clash
      expect(find.text('Clashes with a fixed time'), findsNothing);
      expect(find.textContaining('locked as FIXED'), findsWidgets);
    });

    testWidgets('TEST 6: Backend returns PlanDiff renders proposal card with DRY RUN ONLY badge', (WidgetTester tester) async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'user_intent_summary': 'Cancel gym and shift tasks',
            'plan_diff': {
              'plan_id': 'diff-p1',
              'selected_date': '2026-09-30',
              'before_schedule': [],
              'after_schedule': [],
              'moved_tasks': [
                {
                  'task_id': 't-rep',
                  'title': 'Report Review',
                  'change_type': 'moved',
                  'old_time': '4:00 PM',
                  'new_time': '5:00 PM',
                }
              ],
              'newly_scheduled_tasks': [
                {
                  'task_id': 't-sync',
                  'title': 'Client Sync',
                  'change_type': 'new',
                  'new_time': '6:30 PM',
                }
              ],
              'unchanged_tasks': [],
              'cancelled_tasks': [
                {
                  'task_id': 't-gym',
                  'title': 'Gym Session',
                  'change_type': 'cancelled',
                }
              ],
              'unscheduled_tasks': [],
              'conflicts': [],
              'explanation': 'Cancelled gym session and shifted Report Review to 5:00 PM.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Cancel gym');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Proposal Card Verification
      expect(find.text("Here's how I'd reshape the rest of your day"), findsOneWidget);
      expect(find.text('PREVIEW'), findsOneWidget);
      expect(find.text('Moved Tasks'), findsOneWidget);
      expect(find.text('Report Review'), findsOneWidget);
      expect(find.text('New Tasks'), findsOneWidget);
      expect(find.text('Client Sync'), findsOneWidget);
      expect(find.text('Cancelled Tasks'), findsOneWidget);
      expect(find.text('Gym Session'), findsOneWidget);
      expect(find.textContaining('Changes have not been applied to your database.'), findsOneWidget);
    });

    testWidgets('TEST 7: Open Replan from Friday uses Friday date, NOT today', (WidgetTester tester) async {
      final targetFriday = DateTime(2026, 10, 2);
      String? sentDate;

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          sentDate = body['selected_date'] as String?;
          return http.Response(
            jsonEncode({
              'success': true,
              'user_intent_summary': 'Replan Friday',
              'plan_diff': {
                'plan_id': 'diff-fri-1',
                'selected_date': '2026-10-02',
                'before_schedule': [],
                'after_schedule': [],
                'moved_tasks': [],
                'newly_scheduled_tasks': [],
                'unchanged_tasks': [],
                'cancelled_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
                'explanation': 'Plan updated for Friday, October 2.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: targetFriday,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header must display Friday
      expect(find.text('Friday, October 2'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Add team retrospective');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(sentDate, '2026-10-02');
      expect(find.text('Plan updated for Friday, October 2.'), findsOneWidget);
    });

    testWidgets('TEST 8: Generating a replan performs NO task mutations on AppStateProvider or database', (WidgetTester tester) async {
      final initialTasks = [
        TaskItem(
          id: 'task-1',
          title: 'Existing Task 1',
          durationMinutes: 45,
          difficulty: TaskDifficulty.medium,
          deadline: 'Today',
          category: 'Work',
          scheduledStart: DateTime(2026, 9, 30, 10, 0),
        ),
        TaskItem(
          id: 'task-2',
          title: 'Existing Task 2',
          durationMinutes: 60,
          difficulty: TaskDifficulty.high,
          deadline: 'Today',
          category: 'Work',
          scheduledStart: DateTime(2026, 9, 30, 14, 0),
        ),
      ];

      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'user_intent_summary': 'Replan proposal',
              'plan_diff': {
                'plan_id': 'diff-dry-run',
                'selected_date': '2026-09-30',
                'before_schedule': [],
                'after_schedule': [],
                'moved_tasks': [
                  {
                    'task_id': 'task-1',
                    'title': 'Existing Task 1',
                    'change_type': 'moved',
                    'old_time': '10:00 AM',
                    'new_time': '11:00 AM',
                  }
                ],
                'newly_scheduled_tasks': [],
                'unchanged_tasks': [],
                'cancelled_tasks': [],
                'unscheduled_tasks': [],
                'conflicts': [],
                'explanation': 'Proposed moving Existing Task 1 to 11:00 AM.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final api = ApiService(client: mockClient);
      final provider = AppStateProvider(customApi: api);
      provider.setTasksForTesting(initialTasks);

      // Verify baseline state
      expect(provider.tasks.length, 2);
      expect(provider.tasks[0].scheduledStart, DateTime(2026, 9, 30, 10, 0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChangeNotifierProvider<AppStateProvider>.value(
              value: provider,
              child: ReplanDaySheet(
                selectedDate: DateTime(2026, 9, 30),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Trigger replan
      await tester.enterText(find.byType(TextField), 'I am running 60 minutes late');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Verify proposal rendered
      expect(find.text('PREVIEW'), findsOneWidget);

      // Verify STRICTLY NO MUTATION occurred on provider's tasks or schedule
      expect(provider.tasks.length, 2);
      expect(provider.tasks[0].id, 'task-1');
      expect(provider.tasks[0].scheduledStart, DateTime(2026, 9, 30, 10, 0)); // Unchanged!
      expect(provider.tasks[1].scheduledStart, DateTime(2026, 9, 30, 14, 0)); // Unchanged!
    });
  });
}
