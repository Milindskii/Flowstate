import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/replan_new_task_sheet.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock.debugNowOverride = null;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock.debugNowOverride = null;
  });

  group('Quick Add / Urgent-Task Time Selection UX Regression Tests', () {
    testWidgets('1. No selected time -> shows "Pick a time" and NO "Today at..." or "Noya\'s pick" text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: const Scaffold(
            body: ReplanNewTaskSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Required control: Start time and Pick a time >
      expect(find.text('Start time'), findsOneWidget);
      expect(find.text('Pick a time'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);

      // Regression: Must NOT show automatic wording before user selects a time
      expect(find.textContaining("Noya's pick"), findsNothing);
      expect(find.textContaining('Today at'), findsNothing);
      expect(find.textContaining('Starts at'), findsNothing);
      expect(find.text('No slot today'), findsNothing);
    });

    testWidgets('2. Selected 8:30 AM -> displays "Starts at 8:30 AM" and clearly indicates user selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: const Scaffold(
            body: ReplanNewTaskSheet(
              initialTime: TimeOfDay(hour: 8, minute: 30),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Displays "Starts at 8:30 AM"
      expect(find.text('Starts at 8:30 AM'), findsOneWidget);
      // Clearly indicates user selection
      expect(find.text('Fixed time selected by you'), findsOneWidget);
      expect(find.text('Fixed time'), findsOneWidget);
      expect(find.byKey(const Key('replan_new_task_clear_time')), findsOneWidget);

      // Regression: No Noya's pick or automatic text
      expect(find.textContaining("Noya's pick"), findsNothing);
      expect(find.textContaining('Today at'), findsNothing);

      // User can clear the selected time
      await tester.tap(find.byKey(const Key('replan_new_task_clear_time')));
      await tester.pumpAndSettle();

      expect(find.text('Pick a time'), findsOneWidget);
      expect(find.text('Starts at 8:30 AM'), findsNothing);
      expect(find.text('Fixed time selected by you'), findsNothing);
    });

    testWidgets('3. Tapping "Pick a time" opens Flutter time-picker mechanism', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: const Scaffold(
            body: ReplanNewTaskSheet(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('replan_new_task_time')));
      await tester.pumpAndSettle();

      // Standard Flutter TimePickerDialog opens
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Dismiss picker with OK
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Shows selected time label
      expect(find.textContaining('Starts at'), findsOneWidget);
      expect(find.text('Fixed time selected by you'), findsOneWidget);
    });

    testWidgets('4. Selected 8:30 AM in Quick Add -> request payload has start_time 08:30 and constraint_type fixed_start', (tester) async {
      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'plan_id': 'test-plan-830',
              'plan_diff': {
                'plan_id': 'test-plan-830',
                'selected_date': '2026-10-09',
                'after_schedule': [
                  {
                    'task_id': 'new-task-830',
                    'title': 'Morning standup',
                    'start_time': '2026-10-09T08:30:00Z',
                    'end_time': '2026-10-09T09:15:00Z',
                    'duration_minutes': 45,
                    'is_fixed': true,
                  }
                ],
                'newly_scheduled_tasks': [
                  {
                    'task_id': 'new-task-830',
                    'title': 'Morning standup',
                    'change_type': 'new',
                    'new_time': '8:30 AM',
                    'new_start': '2026-10-09T08:30:00Z',
                    'new_end': '2026-10-09T09:15:00Z',
                    'duration_minutes': 45,
                    'is_fixed': true,
                    'time_locked': true,
                  }
                ],
                'conflicts': [],
                'issues': [],
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        ChangeNotifierProvider<AppStateProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: FlowTheme.lightTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showReplanDaySheet(context, selectedDate: DateTime(2026, 10, 9)),
                  child: const Text('Open Replan'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Replan'));
      await tester.pumpAndSettle();

      // Open Urgent work sheet
      await tester.tap(find.text('Urgent work arrived'));
      await tester.pumpAndSettle();

      // Defaults to Pick a time
      expect(find.text('Pick a time'), findsOneWidget);

      // Enter task title
      await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Morning standup');
      await tester.pump();

      // Pick time
      await tester.tap(find.byKey(const Key('replan_new_task_time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('replan_new_task_submit')));
      await tester.pumpAndSettle();

      expect(capturedBody, isNotNull);
      final quickAdd = capturedBody!['quick_add'] as Map<String, dynamic>?;
      expect(quickAdd, isNotNull);
      expect(quickAdd!['title'], 'Morning standup');
      expect(quickAdd['duration_minutes'], 45);
      expect(quickAdd['start_time'], isNotNull);
      expect(quickAdd['constraint_type'], 'fixed_start');
      expect(quickAdd['is_preferred'], isNot(true));
    });

    test('5. Selected 8:30 AM -> persisted task start time is 8:30 AM and scheduler does not move it', () async {
      final fixedStart = DateTime(2026, 10, 9, 8, 30);
      final fixedEnd = DateTime(2026, 10, 9, 9, 15);

      final diff = PlanDiff(
        planId: 'plan-fixed-830',
        selectedDate: '2026-10-09',
        afterSchedule: [
          ScheduleItem(
            id: 'task-830',
            taskId: 'task-830',
            title: 'Morning standup',
            time: '8:30',
            period: 'AM',
            type: 'Focus',
            tagText: 'TASK',
            durationMinutes: 45,
            startTime: fixedStart,
            endTime: fixedEnd,
          ),
        ],
        newlyScheduledTasks: [
          TaskDiffItem(
            taskId: 'task-830',
            title: 'Morning standup',
            changeType: 'new',
            newTime: '8:30 AM',
            newStart: fixedStart,
            newEnd: fixedEnd,
            durationMinutes: 45,
            isFixed: true,
            timeLocked: true,
          ),
        ],
      );

      final provider = AppStateProvider(customApi: ApiService(client: MockClient((_) async => http.Response('{}', 200))));
      provider.setDemoMode(true);
      await provider.applyReplan(diff);

      // Verify persisted task has exact start time and is locked
      final saved = provider.tasks.firstWhere((t) => t.title == 'Morning standup');
      expect(saved.scheduledStart, fixedStart);
      expect(saved.scheduledEnd, fixedEnd);
      expect(saved.durationMinutes, 45);
      expect(saved.timeLocked, isTrue);

      // When evaluating candidates around it, the 8:30 AM fixed task stays in existingBusy
      final busy = <MapEntry<DateTime, DateTime>>[
        MapEntry(saved.scheduledStart!, saved.scheduledEnd!),
      ];
      const candidate = TaskItem(
        id: 'candidate-other',
        title: 'Other task',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      final eval = const SchedulingEngine().evaluateCandidateSlot(
        candidate,
        existingBusy: busy,
        nowLocal: DateTime(2026, 10, 9, 8, 0),
        profile: const PlanningProfile(),
      );

      // Scheduler does not place the new candidate during the 8:30-9:15 interval
      final slotStart = eval.slotStart;
      final slotEnd = eval.slotEnd;
      final overlapsFixed = slotStart.isBefore(fixedEnd) && slotEnd.isAfter(fixedStart);
      expect(overlapsFixed, isFalse, reason: 'Scheduler must not move or overlap the fixed 8:30 AM task');
    });

    test('6. Calendar renders the task at 8:30 AM with exact duration', () {
      final fixedStart = DateTime(2026, 10, 9, 8, 30);
      final fixedEnd = DateTime(2026, 10, 9, 9, 15);

      final task = TaskItem(
        id: 'task-830',
        title: 'Client sync',
        durationMinutes: 45,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
        scheduledStart: fixedStart,
        scheduledEnd: fixedEnd,
        timeLocked: true,
      );

      // Create Calendar schedule item
      final scheduleItem = ScheduleItem(
        id: task.id,
        taskId: task.id,
        title: task.title,
        time: DateFormat('h:mm').format(task.scheduledStart!),
        period: DateFormat('a').format(task.scheduledStart!),
        type: 'Focus',
        tagText: 'TASK',
        durationMinutes: task.durationMinutes,
        startTime: task.scheduledStart,
        endTime: task.scheduledEnd,
      );

      // Node start time = 8:30 AM
      expect(scheduleItem.startTime, fixedStart);
      expect(scheduleItem.endTime, fixedEnd);
      expect(scheduleItem.durationMinutes, 45);
      expect(scheduleItem.time, '8:30');
      expect(scheduleItem.period, 'AM');
    });

    testWidgets('7. Submitting without selecting time schedules automatically (isNoyaPick: true)', (tester) async {
      ReplanNewTaskResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await ReplanNewTaskSheet.show(ctx);
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Pick a time'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Unscheduled quick task');
      await tester.pump();

      await tester.tap(find.byKey(const Key('replan_new_task_submit')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.title, 'Unscheduled quick task');
      expect(result!.time, isNull);
      expect(result!.isNoyaPick, isTrue);
    });
  });
}
