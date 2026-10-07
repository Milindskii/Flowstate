import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flowstate/components/plan_diff_view.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/calendar_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockApiService extends ApiService {
  dynamic lastPostPayload;
  String? lastPostEndpoint;
  bool shouldFailApply = false;
  int applyCallCount = 0;

  @override
  Future<dynamic> post(
    String endpoint, {
    dynamic body,
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    lastPostEndpoint = endpoint;
    lastPostPayload = body;

    if (endpoint == '/api/v1/calendar/apply-replan') {
      applyCallCount++;
      if (shouldFailApply) {
        throw const ApiException('Database transaction deadlock. Rollback complete.', statusCode: 500);
      }
      return {
        'success': true,
        'updated_count': 1,
        'created_count': 1,
        'cancelled_count': 1,
        'message': 'Successfully applied plan: 1 updated, 1 created, 1 cancelled.',
      };
    }
    if (endpoint == '/api/v1/ai/replan' || endpoint == '/api/v1/calendar/replan') {
      return {
        'success': true,
        'user_intent_summary': 'Moved report for urgent work',
        'plan_diff': {
          'plan_id': 'test-plan-123',
          'selected_date': '2026-10-01',
          'created_at': DateTime.now().toIso8601String(),
          'before_schedule': [
            {
              'id': 'task-report-id',
              'task_id': 'task-report-id',
              'title': 'Report',
              'time': '5:00',
              'period': 'PM',
              'duration_minutes': 60,
              'type': 'deep_work',
              'tag_text': 'DEEP WORK',
              'is_fixed': false,
              'start_time': '2026-10-01T17:00:00Z',
              'end_time': '2026-10-01T18:00:00Z',
            },
            {
              'id': 'fixed-dentist-id',
              'task_id': 'fixed-dentist-id',
              'title': 'Dentist',
              'time': '6:00',
              'period': 'PM',
              'duration_minutes': 60,
              'type': 'meeting',
              'tag_text': 'FIXED',
              'is_fixed': true,
              'start_time': '2026-10-01T18:00:00Z',
              'end_time': '2026-10-01T19:00:00Z',
            },
          ],
          'after_schedule': [
            {
              'id': 'new-urgent-id',
              'task_id': 'new-urgent-id',
              'title': 'Urgent Client Work',
              'time': '4:00',
              'period': 'PM',
              'duration_minutes': 60,
              'type': 'deep_work',
              'tag_text': 'DEEP WORK',
              'is_fixed': false,
              'start_time': '2026-10-01T16:00:00Z',
              'end_time': '2026-10-01T17:00:00Z',
            },
            {
              'id': 'task-report-id',
              'task_id': 'task-report-id',
              'title': 'Report',
              'time': '5:00',
              'period': 'PM',
              'duration_minutes': 60,
              'type': 'deep_work',
              'tag_text': 'DEEP WORK',
              'is_fixed': false,
              'start_time': '2026-10-01T17:00:00Z',
              'end_time': '2026-10-01T18:00:00Z',
            },
            {
              'id': 'fixed-dentist-id',
              'task_id': 'fixed-dentist-id',
              'title': 'Dentist',
              'time': '6:00',
              'period': 'PM',
              'duration_minutes': 60,
              'type': 'meeting',
              'tag_text': 'FIXED',
              'is_fixed': true,
              'start_time': '2026-10-01T18:00:00Z',
              'end_time': '2026-10-01T19:00:00Z',
            },
          ],
          'moved_tasks': [
            {
              'task_id': 'task-report-id',
              'title': 'Report',
              'change_type': 'moved',
              'old_time': '5:00 PM',
              'new_time': '5:00 PM',
              'duration_minutes': 60,
            }
          ],
          'newly_scheduled_tasks': [
            {
              'task_id': 'new-urgent-id',
              'title': 'Urgent Client Work',
              'change_type': 'new',
              'new_time': '4:00 PM',
              'duration_minutes': 60,
            }
          ],
          'unchanged_tasks': [
            {
              'task_id': 'fixed-dentist-id',
              'title': 'Dentist',
              'change_type': 'unchanged',
              'old_time': '6:00 PM',
              'new_time': '6:00 PM',
              'is_fixed': true,
              'duration_minutes': 60,
            }
          ],
          'cancelled_tasks': [],
          'unscheduled_tasks': [],
          'conflicts': [],
          'explanation': 'Added Urgent Client Work at 4:00 PM. Dentist remains fixed at 6:00 PM.',
        }
      };
    }
    return {};
  }

  @override
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    if (endpoint == '/api/v1/calendar/day') {
      return {
        'date': queryParams?['date'] ?? '2026-10-01',
        'is_today': true,
        'is_past': false,
        'timeline': [],
        'fixed_commitments': [],
        'completed_tasks': [],
        'remaining_tasks': [],
        'unscheduled_tasks': [],
        'conflicts': [],
        'workload': {
          'total_minutes': 120,
          'deep_work_minutes': 60,
          'shallow_work_minutes': 0,
          'task_count': 2,
        },
      };
    }
    if (endpoint == '/api/v1/today') {
      return {
        'lifecycle_state': 'in_progress',
        'tasks': [],
        'active_focus_task': null,
        'upcoming_tasks': [],
        'completed_tasks': [],
      };
    }
    if (endpoint == '/api/v1/tasks') {
      return [];
    }
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  final sampleDiff = PlanDiff(
    planId: 'plan-apply-xyz',
    selectedDate: '2026-10-01',
    createdAt: DateTime.parse('2026-10-01T12:00:00Z'),
    explanation: 'Moved gym to 7:00 PM and scheduled Urgent Task.',
    beforeSchedule: [
      ScheduleItem(
        id: 'task-gym-1',
        taskId: 'task-gym-1',
        time: '5:00',
        period: 'PM',
        title: 'Gym Session',
        type: 'Physical',
        tagText: 'PHYSICAL',
        durationMinutes: 45,
        startTime: DateTime.parse('2026-10-01T17:00:00Z'),
        endTime: DateTime.parse('2026-10-01T17:45:00Z'),
      ),
      ScheduleItem(
        id: 'fixed-dentist-1',
        taskId: 'fixed-dentist-1',
        time: '6:00',
        period: 'PM',
        title: 'Dentist Appointment',
        type: 'Meeting',
        tagText: 'FIXED',
        isFixed: true,
        durationMinutes: 60,
        startTime: DateTime.parse('2026-10-01T18:00:00Z'),
        endTime: DateTime.parse('2026-10-01T19:00:00Z'),
      ),
    ],
    afterSchedule: [
      ScheduleItem(
        id: 'new-urgent-1',
        taskId: 'new-urgent-1',
        time: '4:00',
        period: 'PM',
        title: 'Urgent Work',
        type: 'Focus',
        tagText: 'DEEP WORK',
        durationMinutes: 60,
        startTime: DateTime.parse('2026-10-01T16:00:00Z'),
        endTime: DateTime.parse('2026-10-01T17:00:00Z'),
      ),
      ScheduleItem(
        id: 'fixed-dentist-1',
        taskId: 'fixed-dentist-1',
        time: '6:00',
        period: 'PM',
        title: 'Dentist Appointment',
        type: 'Meeting',
        tagText: 'FIXED',
        isFixed: true,
        durationMinutes: 60,
        startTime: DateTime.parse('2026-10-01T18:00:00Z'),
        endTime: DateTime.parse('2026-10-01T19:00:00Z'),
      ),
      ScheduleItem(
        id: 'task-gym-1',
        taskId: 'task-gym-1',
        time: '7:00',
        period: 'PM',
        title: 'Gym Session',
        type: 'Physical',
        tagText: 'PHYSICAL',
        durationMinutes: 45,
        startTime: DateTime.parse('2026-10-01T19:00:00Z'),
        endTime: DateTime.parse('2026-10-01T19:45:00Z'),
      ),
    ],
    movedTasks: [
      const TaskDiffItem(
        taskId: 'task-gym-1',
        title: 'Gym Session',
        changeType: 'moved',
        oldTime: '5:00 PM',
        newTime: '7:00 PM',
        durationMinutes: 45,
      ),
    ],
    newlyScheduledTasks: [
      const TaskDiffItem(
        taskId: 'new-urgent-1',
        title: 'Urgent Work',
        changeType: 'new',
        newTime: '4:00 PM',
        durationMinutes: 60,
      ),
    ],
    unchangedTasks: [
      const TaskDiffItem(
        taskId: 'fixed-dentist-1',
        title: 'Dentist Appointment',
        changeType: 'unchanged',
        oldTime: '6:00 PM',
        newTime: '6:00 PM',
        isFixed: true,
        durationMinutes: 60,
      ),
    ],
    cancelledTasks: [
      const TaskDiffItem(
        taskId: 'task-optional-old',
        title: 'Optional Call',
        changeType: 'cancelled',
      ),
    ],
  );

  group('Task 6: Apply Replan Flow & Atomic Database Persistence Tests', () {
    test('1. PlanDiff.toApplyRequest() builds exact atomic payload with dates and times', () {
      final request = sampleDiff.toApplyRequest();

      expect(request.planId, equals('plan-apply-xyz'));
      expect(request.selectedDate, equals('2026-10-01'));

      // Check moved task updates
      expect(request.taskUpdates.length, equals(1));
      expect(request.taskUpdates.first.taskId, equals('task-gym-1'));
      expect(request.taskUpdates.first.scheduledStart, equals(DateTime.parse('2026-10-01T19:00:00Z')));
      expect(request.taskUpdates.first.scheduledEnd, equals(DateTime.parse('2026-10-01T19:45:00Z')));

      // Check new tasks to create
      expect(request.newTasks.length, equals(1));
      expect(request.newTasks.first.title, equals('Urgent Work'));
      expect(request.newTasks.first.estimatedMinutes, equals(60));
      expect(request.newTasks.first.scheduledStart, equals(DateTime.parse('2026-10-01T16:00:00Z')));

      // Check cancelled tasks
      expect(request.cancelledTaskIds, equals(['task-optional-old']));

      final json = request.toJson();
      expect(json['plan_id'], equals('plan-apply-xyz'));
      expect(json['selected_date'], equals('2026-10-01'));
      expect((json['task_updates'] as List).length, equals(1));
      expect((json['new_tasks'] as List).length, equals(1));
      expect((json['cancelled_task_ids'] as List).length, equals(1));
    });

    test('2. CalendarService.applyReplan invokes POST /api/v1/calendar/apply-replan and parses response', () async {
      final mockApi = MockApiService();
      final calendarService = CalendarService(api: mockApi);

      final req = sampleDiff.toApplyRequest();
      final res = await calendarService.applyReplan(req);

      expect(mockApi.lastPostEndpoint, equals('/api/v1/calendar/apply-replan'));
      expect(mockApi.lastPostPayload?['plan_id'], equals('plan-apply-xyz'));
      expect(mockApi.lastPostPayload?['selected_date'], equals('2026-10-01'));
      expect(res.success, isTrue);
      expect(res.updatedCount, equals(1));
      expect(res.createdCount, equals(1));
      expect(res.cancelledCount, equals(1));
      expect(res.message, contains('Successfully applied plan'));
    });

    testWidgets('3. PlanDiffView renders dominant Primary CTA for Apply Changes and disables during applying state', (WidgetTester tester) async {
      bool applied = false;

      // 3A. Normal state: Apply Changes is clickable
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(
                diff: sampleDiff,
                isApplying: false,
                onApply: () => applied = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Apply Changes'), findsOneWidget);
      await tester.ensureVisible(find.text('Apply Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Changes'));
      expect(applied, isTrue);

      // 3B. Applying state: Renders spinner and 'Applying Schedule...'
      applied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(
                diff: sampleDiff,
                isApplying: true,
                onApply: () => applied = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Applying Schedule...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.ensureVisible(find.text('Applying Schedule...'));
      await tester.pump();
      await tester.tap(find.text('Applying Schedule...'));
      // Callback must not fire while isApplying is true
      expect(applied, isFalse);
    });

    testWidgets('4. Responsive mobile check: Narrow screen (<360px) renders stacked Before-After view without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PlanDiffView(diff: sampleDiff),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Before → After tab
      await tester.tap(find.text('Before → After'));
      await tester.pumpAndSettle();

      // Verify stacked layout on narrow screen
      expect(find.textContaining('BEFORE:'), findsWidgets);
      expect(find.textContaining('AFTER:'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Full End-to-End Apply Flow: Tapping Apply Changes applies to backend, shows success, and closes sheet', (WidgetTester tester) async {
      final mockApi = MockApiService();
      final appState = AppStateProvider(
        customApi: mockApi,
        initialUser: const AuthUser(id: 'usr-1', email: 'test@flowstate.ai', name: 'Tester'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppStateProvider>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showReplanDaySheet(
                        context,
                        selectedDate: DateTime(2026, 10, 1),
                        currentSchedule: null,
                      );
                    },
                    child: const Text('Open Replan Sheet'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Replan Sheet'));
      await tester.pumpAndSettle();

      // Trigger replan message
      await tester.enterText(find.byType(TextField), 'Add urgent work and move gym');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Proposal is now displayed
      expect(find.text('Apply Changes'), findsOneWidget);

      // Tap Apply Changes
      await tester.ensureVisible(find.text('Apply Changes'));
      await tester.tap(find.text('Apply Changes'));
      // Pump multiple frames to allow all async awaits and slide-down pop transition to complete
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Assert backend apply-replan was called
      expect(mockApi.applyCallCount, equals(1));
      expect(mockApi.lastPostEndpoint, equals('/api/v1/calendar/apply-replan'));

      // Sheet should be popped after successful apply
      expect(find.byType(ReplanDaySheet), findsNothing);
      expect(find.textContaining('Successfully applied plan'), findsOneWidget);
    });

    testWidgets('6. Error Handling: Backend failure displays error message and does NOT pop sheet', (WidgetTester tester) async {
      final mockApi = MockApiService()..shouldFailApply = true;
      final appState = AppStateProvider(
        customApi: mockApi,
        initialUser: const AuthUser(id: 'usr-1', email: 'test@flowstate.ai', name: 'Tester'),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<AppStateProvider>.value(
          value: appState,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () {
                      showReplanDaySheet(
                        context,
                        selectedDate: DateTime(2026, 10, 1),
                        currentSchedule: null,
                      );
                    },
                    child: const Text('Open Replan Sheet'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Open sheet
      await tester.tap(find.text('Open Replan Sheet'));
      await tester.pumpAndSettle();

      // Trigger replan message
      await tester.enterText(find.byType(TextField), 'Add urgent work and move gym');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      // Proposal is displayed
      expect(find.text('Apply Changes'), findsOneWidget);

      // Tap Apply Changes
      await tester.ensureVisible(find.text('Apply Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply Changes'));
      await tester.pumpAndSettle();

      // Assert backend apply-replan was called
      expect(mockApi.applyCallCount, equals(1));

      // Sheet must NOT be popped on failure; error feedback displayed
      expect(find.byType(ReplanDaySheet), findsOneWidget);
      expect(find.textContaining("Couldn't apply that plan"), findsWidgets);
    });
  });
}
