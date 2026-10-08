import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/components/reschedule_task_sheet.dart';
import 'package:flowstate/components/task_date_time_pickers.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'support/date_picker_helpers.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  Widget buildTestApp({
    required AppStateProvider appState,
  }) {
    appState.setDemoMode(true);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: TodayDashboardTab(),
        ),
      ),
    );
  }

  testWidgets('Phase 1: 1. "Later" button opens full reschedule UI with TaskDateTimePickers', (WidgetTester tester) async {
    final appState = AppStateProvider();
    const task1 = TaskItem(
      id: 'task-alpha',
      title: 'Analyze Financial Report',
      durationMinutes: 45,
      difficulty: TaskDifficulty.high,
      deadline: 'Today',
      category: 'Work',
      isPriority: true,
    );
    appState.setTasksForTesting([task1]);

    await tester.pumpWidget(buildTestApp(appState: appState));
    await tester.pumpAndSettle();

    // Verify task is displayed on Today
    expect(find.text('Analyze Financial Report'), findsWidgets);
    expect(find.text('Later'), findsOneWidget);

    // Tap "Later"
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // Verify RescheduleTaskSheet is presented
    expect(find.byType(RescheduleTaskSheet), findsOneWidget);
    expect(find.text('Reschedule Task'), findsOneWidget);
    expect(find.text('Analyze Financial Report'), findsWidgets);
    // ONE date control and ONE time control: no second set of chips, no "Calendar date" / "Clock time" twins
    expect(find.byType(TaskDateTimePickers), findsOneWidget);
    expect(find.byKey(const Key('reschedule_date_picker_button')), findsOneWidget);
    expect(find.byKey(const Key('reschedule_time_picker_button')), findsOneWidget);
    expect(find.text('DATE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(find.text('Pick Date'), findsNothing);
    expect(find.text('CALENDAR DATE'), findsNothing);
    expect(find.text('CLOCK TIME'), findsNothing);
    expect(find.byKey(const Key('reschedule_chip_today')), findsNothing);
    expect(find.byKey(const Key('reschedule_chip_tomorrow')), findsNothing);
    expect(find.byIcon(Icons.calendar_today_rounded), findsOneWidget);
    expect(find.byIcon(Icons.access_time_rounded), findsOneWidget);
    expect(find.byKey(const Key('reschedule_cancel_button')), findsOneWidget);
    expect(find.byKey(const Key('reschedule_confirm_button')), findsOneWidget);
  });

  testWidgets('Phase 1: 2. Rescheduling to Tomorrow moves task to tomorrow and updates Today recommendation', (WidgetTester tester) async {
    final appState = AppStateProvider();
    const task1 = TaskItem(
      id: 'task-alpha',
      title: 'Deep Focus Task',
      durationMinutes: 45,
      difficulty: TaskDifficulty.high,
      deadline: 'Today',
      category: 'Work',
      isPriority: true,
    );
    const task2 = TaskItem(
      id: 'task-beta',
      title: 'Secondary Prep',
      durationMinutes: 20,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Admin',
      isPriority: false,
    );
    appState.setTasksForTesting([task1, task2]);

    await tester.pumpWidget(buildTestApp(appState: appState));
    await tester.pumpAndSettle();

    expect(appState.recommendedTask?.id, equals('task-alpha'));

    // Open reschedule sheet
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    // Tap "Tomorrow"
    await pickDateVia(tester, find.byKey(const Key('reschedule_date_picker_button')), DateTime.now().add(const Duration(days: 1)));

    // Confirm reschedule
    await tester.tap(find.byKey(const Key('reschedule_confirm_button')));
    await tester.pumpAndSettle();

    // Verify task1 is rescheduled to tomorrow
    final updated = appState.tasks.firstWhere((t) => t.id == 'task-alpha');
    expect(updated.deadline, equals('Tomorrow'));
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    expect(updated.deadlineAt?.day, equals(tomorrow.day));
    expect(updated.isCompleted, isFalse);

    // Today recommendation immediately shifts to task-beta
    expect(appState.recommendedTask?.id, equals('task-beta'));
  });

  testWidgets('Phase 1: 3. Rescheduling with custom calendar date persists date and updates schedule', (WidgetTester tester) async {
    final appState = AppStateProvider();
    const task1 = TaskItem(
      id: 'task-custom-date',
      title: 'Quarterly Planning',
      durationMinutes: 60,
      difficulty: TaskDifficulty.high,
      deadline: 'Today',
      category: 'Strategy',
      isPriority: true,
    );
    appState.setTasksForTesting([task1]);

    await tester.pumpWidget(buildTestApp(appState: appState));
    await tester.pumpAndSettle();

    // Programmatically reschedule to a custom date in 4 days with no fixed time
    final targetDate = DateTime.now().add(const Duration(days: 4));
    await appState.rescheduleTask('task-custom-date', targetDate: targetDate, targetTime: null);
    await tester.pumpAndSettle();

    final task = appState.tasks.firstWhere((t) => t.id == 'task-custom-date');
    expect(task.deadlineAt?.day, equals(targetDate.day));
    expect(task.deadline, equals(DateFormat('EEE, MMM d').format(targetDate)));
    expect(task.scheduledStart, isNull);
    expect(task.scheduledTime, isNull);
  });

  testWidgets('Phase 1: 4. Rescheduling to custom clock time sets scheduledStart and scheduledTime', (WidgetTester tester) async {
    final appState = AppStateProvider();
    const task1 = TaskItem(
      id: 'task-clock-time',
      title: 'Team Standup Review',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Meeting',
      isPriority: true,
    );
    appState.setTasksForTesting([task1]);

    await tester.pumpWidget(buildTestApp(appState: appState));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    await appState.rescheduleTask(
      'task-clock-time',
      targetDate: today,
      targetTime: const TimeOfDay(hour: 14, minute: 30),
    );
    await tester.pumpAndSettle();

    final task = appState.tasks.firstWhere((t) => t.id == 'task-clock-time');
    expect(task.scheduledStart, isNotNull);
    expect(task.scheduledStart?.hour, equals(14));
    expect(task.scheduledStart?.minute, equals(30));
    expect(task.scheduledTime, equals('2:30 PM'));
    expect(task.scheduledEnd?.hour, equals(15));
    expect(task.scheduledEnd?.minute, equals(0));
  });

  testWidgets('Phase 1: 5. Rescheduling with "No fixed time" clears scheduledStart while preserving date', (WidgetTester tester) async {
    final appState = AppStateProvider();
    final fixedStart = DateTime(2026, 10, 5, 11, 0);
    final task1 = TaskItem(
      id: 'task-clear-time',
      title: 'Write Documentation',
      durationMinutes: 45,
      difficulty: TaskDifficulty.light,
      deadline: 'Mon, Oct 5',
      category: 'Admin',
      scheduledStart: fixedStart,
      scheduledEnd: fixedStart.add(const Duration(minutes: 45)),
      scheduledTime: '11:00 AM',
      deadlineAt: DateTime(2026, 10, 5),
    );
    appState.setTasksForTesting([task1]);

    // Reschedule to Oct 5 with No fixed time (targetTime == null)
    appState.setDemoMode(true); // bypass backend so local state update isn't reverted
    await appState.rescheduleTask(
      'task-clear-time',
      targetDate: DateTime(2026, 10, 5),
      targetTime: null,
    );

    final task = appState.tasks.firstWhere((t) => t.id == 'task-clear-time');
    expect(task.scheduledStart, isNull, reason: 'scheduledStart must be cleared');
    expect(task.scheduledEnd, isNull, reason: 'scheduledEnd must be cleared');
    expect(task.scheduledTime, isNull, reason: 'scheduledTime must be cleared');
    expect(task.deadlineAt?.day, equals(5));
  });

  testWidgets('Phase 1: 6. Cancellation dismisses sheet and leaves task schedule unchanged', (WidgetTester tester) async {
    final appState = AppStateProvider();
    const task1 = TaskItem(
      id: 'task-cancel',
      title: 'Unchanged Task',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Personal',
      isPriority: true,
    );
    appState.setTasksForTesting([task1]);

    await tester.pumpWidget(buildTestApp(appState: appState));
    await tester.pumpAndSettle();

    // Open reschedule sheet
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(find.byType(RescheduleTaskSheet), findsOneWidget);

    // Tap Cancel
    await tester.tap(find.byKey(const Key('reschedule_cancel_button')));
    await tester.pumpAndSettle();

    // Sheet is dismissed
    expect(find.byType(RescheduleTaskSheet), findsNothing);

    // Task is unchanged
    final task = appState.tasks.firstWhere((t) => t.id == 'task-cancel');
    expect(task.deadline, equals('Today'));
    expect(task.scheduledStart, isNull);
  });

  testWidgets('Phase 1: 7. Today and Calendar synchronization reflects rescheduled date', (WidgetTester tester) async {
    final appState = AppStateProvider();
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));

    const task1 = TaskItem(
      id: 'task-sync-1',
      title: 'Sync Task Today',
      durationMinutes: 45,
      difficulty: TaskDifficulty.high,
      deadline: 'Today',
      category: 'Work',
      isPriority: true,
    );
    appState.setTasksForTesting([task1]);

    // Reschedule task to tomorrow at 10:00 AM
    appState.setDemoMode(true); // bypass backend so local state update isn't reverted
    await appState.rescheduleTask(
      'task-sync-1',
      targetDate: tomorrow,
      targetTime: const TimeOfDay(hour: 10, minute: 0),
    );

    // Calendar for tomorrow should contain this task
    await appState.loadCalendarDay(tomorrow);
    final schedule = appState.selectedDateSchedule;
    expect(schedule, isNotNull);
    final matching = schedule!.timeline.where((item) => item.title == 'Sync Task Today').toList();
    expect(matching.isNotEmpty, isTrue, reason: 'Task should be present on tomorrow calendar schedule');
    expect(matching.first.time, equals('10:00'));

    // Today's recommendedTask should NOT be this tomorrow task
    expect(appState.recommendedTask, isNull);
  });
}
