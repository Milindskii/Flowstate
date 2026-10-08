import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/noya_reminder_overlay.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/smart_reminder_service.dart';

void main() {
  late FakeNotificationAdapter fakeAdapter;
  late SmartReminderService reminderService;
  late DateTime clockTime;

  final DateTime day = DateTime(2026, 10, 8);
  DateTime at(int hour, [int minute = 0, int dayOffset = 0]) =>
      DateTime(day.year, day.month, day.day + dayOffset, hour, minute);

  setUp(() async {
    clockTime = at(14, 0); // 2:00 PM
    FlowClock.debugNowOverride = () => clockTime;
    fakeAdapter = FakeNotificationAdapter();
    reminderService = SmartReminderService(
      adapter: fakeAdapter,
      clock: () => clockTime,
      timezoneGetter: () async => 'Asia/Kolkata',
    );
    await reminderService.initialize();
    SmartReminderService.setInstanceForTesting(reminderService);
  });

  tearDown(() {
    SmartReminderService.resetInstance();
    FlowClock.debugNowOverride = null;
  });

  TaskItem createTask({
    required String id,
    required String title,
    required DateTime scheduledStart,
    int durationMinutes = 45,
    bool isCompleted = false,
    bool isCommitment = false,
    TaskStatus status = TaskStatus.todo,
    DateTime? plannedDate,
    String? scheduledTime,
    String? routineId,
  }) {
    return TaskItem(
      id: id,
      title: title,
      durationMinutes: durationMinutes,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      scheduledStart: scheduledStart,
      scheduledEnd: scheduledStart.add(Duration(minutes: durationMinutes)),
      isCompleted: isCompleted,
      isCommitment: isCommitment,
      status: status,
      plannedDate: plannedDate,
      scheduledTime: scheduledTime,
      routineId: routineId,
    );
  }

  group('Smart Task Reminders - Core Requirements', () {
    test('1. task at 4 PM schedules reminder', () async {
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0), // 4:00 PM
      );

      await reminderService.onTaskAdded(task);

      expect(fakeAdapter.scheduled.length, 1);
      final entry = fakeAdapter.scheduled.values.first;
      expect(entry.title, contains('Noya'));
      expect(entry.body, contains('Time for Gym'));
      expect(entry.body, contains('4:00 PM'));
      expect(entry.scheduledDate, at(16, 0));
    });

    test('2. task edited to 5 PM cancels 4 PM and schedules 5 PM', () async {
      final task4pm = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      await reminderService.onTaskAdded(task4pm);
      expect(fakeAdapter.scheduled.length, 1);
      final initialId = fakeAdapter.scheduled.keys.first;

      final task5pm = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(17, 0), // 5:00 PM
      );
      await reminderService.onTaskUpdated(task5pm, task4pm);

      expect(fakeAdapter.cancelledIds, contains(initialId));
      expect(fakeAdapter.scheduled.length, 1);
      final updatedEntry = fakeAdapter.scheduled.values.first;
      expect(updatedEntry.scheduledDate, at(17, 0));
      expect(updatedEntry.body, contains('5:00 PM'));
    });

    test('3. task completed cancels reminder', () async {
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      await reminderService.onTaskAdded(task);
      expect(fakeAdapter.scheduled.length, 1);
      final notifId = fakeAdapter.scheduled.keys.first;

      await reminderService.onTaskCompleted(task.id);

      expect(fakeAdapter.cancelledIds, contains(notifId));
      expect(fakeAdapter.scheduled.containsKey(notifId), isFalse);
    });

    test('4. task skipped cancels reminder', () async {
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      await reminderService.onTaskAdded(task);
      expect(fakeAdapter.scheduled.length, 1);
      final notifId = fakeAdapter.scheduled.keys.first;

      await reminderService.onTaskSkipped(task.id);

      expect(fakeAdapter.cancelledIds, contains(notifId));
      expect(fakeAdapter.scheduled.containsKey(notifId), isFalse);
    });

    test('5. task deleted cancels reminder', () async {
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      await reminderService.onTaskAdded(task);
      expect(fakeAdapter.scheduled.length, 1);
      final notifId = fakeAdapter.scheduled.keys.first;

      await reminderService.onTaskDeleted(task.id);

      expect(fakeAdapter.cancelledIds, contains(notifId));
      expect(fakeAdapter.scheduled.containsKey(notifId), isFalse);
    });

    test('6. task created after its scheduled time does not immediately notify', () async {
      clockTime = at(16, 30); // Clock is 4:30 PM
      final pastTask = createTask(
        id: 'task-past',
        title: 'Quick Call',
        scheduledStart: at(16, 0), // 4:00 PM (past)
      );

      await reminderService.onTaskAdded(pastTask);

      expect(fakeAdapter.scheduled, isEmpty);
      expect(reminderService.currentInAppReminder.value, isNull);
    });

    testWidgets('7. app foreground shows Noya overlay at task time', (tester) async {
      reminderService.setForegroundForTesting(true);
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      reminderService.taskListProvider = () => [task];
      await reminderService.onTaskAdded(task);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: NoyaReminderOverlay(service: reminderService),
        ),
      ));
      expect(find.byKey(const Key('noya_reminder_overlay')), findsNothing);

      // Time advances to 4:00 PM
      clockTime = at(16, 0);
      reminderService.checkDueReminders(clockTime);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const Key('noya_reminder_overlay')), findsOneWidget);
      expect(find.text('Time for Gym'), findsOneWidget);
      expect(find.text('Ready to start?'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    test('8. app background/closed uses system notification', () async {
      reminderService.setForegroundForTesting(false); // App in background
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      reminderService.taskListProvider = () => [task];
      await reminderService.onTaskAdded(task);

      expect(fakeAdapter.scheduled.length, 1);

      // Time advances to 4:00 PM while backgrounded
      clockTime = at(16, 0);
      reminderService.checkDueReminders(clockTime);

      // Foreground overlay is not shown
      expect(reminderService.currentInAppReminder.value, isNull);
      // System notification remains scheduled for background delivery
      expect(fakeAdapter.scheduled.values.first.scheduledDate, at(16, 0));
    });

    test('9. task detail screen suppresses same-task popup', () async {
      reminderService.setForegroundForTesting(true);
      final task = createTask(
        id: 'task-gym',
        title: 'Gym',
        scheduledStart: at(16, 0),
      );
      reminderService.taskListProvider = () => [task];
      await reminderService.onTaskAdded(task);

      // User opens detail sheet for this task
      reminderService.activeViewingTaskId = 'task-gym';

      clockTime = at(16, 0);
      reminderService.checkDueReminders(clockTime);

      // Suppressed because user is viewing this task
      expect(reminderService.currentInAppReminder.value, isNull);

      // User closes detail sheet
      reminderService.activeViewingTaskId = null;

      // Another task becoming due is not suppressed
      final otherTask = createTask(
        id: 'task-study',
        title: 'Study',
        scheduledStart: at(16, 0),
      );
      reminderService.taskListProvider = () => [task, otherTask];
      reminderService.checkDueReminders(clockTime);
      expect(reminderService.currentInAppReminder.value?.id, 'task-study');
    });

    test('10. no duplicate notifications after app restart', () async {
      final tasks = [
        createTask(id: 'task-1', title: 'Task 1', scheduledStart: at(15, 0)),
        createTask(id: 'task-2', title: 'Task 2', scheduledStart: at(16, 0)),
      ];

      // Initial sync on app open
      await reminderService.syncTasks(tasks);
      expect(fakeAdapter.scheduled.length, 2);

      // Multiple simulated restarts / refresh cycles
      await reminderService.syncTasks(tasks);
      await reminderService.syncTasks(tasks);
      await reminderService.syncTasks(tasks);

      expect(fakeAdapter.scheduled.length, 2);
    });

    test('11. Replan moves reminder correctly', () async {
      clockTime = at(13, 0); // 1:00 PM
      final taskStudy = createTask(
        id: 'task-study',
        title: 'Deep Study',
        scheduledStart: at(14, 0), // Originally 2:00 PM
      );
      await reminderService.onTaskAdded(taskStudy);
      expect(fakeAdapter.scheduled.length, 1);
      final oldId = fakeAdapter.scheduled.keys.first;

      // Replan moves task to 3:30 PM
      final movedTask = createTask(
        id: 'task-study',
        title: 'Deep Study',
        scheduledStart: at(15, 30), // 3:30 PM
      );

      await reminderService.onReplanApplied([movedTask]);

      expect(fakeAdapter.cancelledIds, contains(oldId));
      expect(fakeAdapter.scheduled.length, 1);
      final newEntry = fakeAdapter.scheduled.values.first;
      expect(newEntry.scheduledDate, at(15, 30));
      expect(newEntry.body, contains('3:30 PM'));
    });

    test('12. recurring tasks schedule the correct occurrence', () async {
      clockTime = at(8, 0); // 8:00 AM (both 9:00 AM occurrences are in the future)
      // Routine occurrences for today and tomorrow
      final occurrenceToday = createTask(
        id: 'routine-occ-1',
        title: 'Morning Routine',
        scheduledStart: at(9, 0, 0), // Today 9:00 AM
        routineId: 'routine-morning',
      );
      final occurrenceTomorrow = createTask(
        id: 'routine-occ-2',
        title: 'Morning Routine',
        scheduledStart: at(9, 0, 1), // Tomorrow 9:00 AM
        routineId: 'routine-morning',
      );

      // Sync tasks including both occurrences
      await reminderService.syncTasks([occurrenceToday, occurrenceTomorrow]);

      // Both occurrences have separate distinct scheduled notifications
      expect(fakeAdapter.scheduled.length, 2);
      final dates = fakeAdapter.scheduled.values.map((e) => e.scheduledDate).toSet();
      expect(dates, contains(at(9, 0, 0)));
      expect(dates, contains(at(9, 0, 1)));
    });

    test('13. date rollover keeps reminders on correct dates', () async {
      // Task planned for tomorrow at 10:00 AM
      final tomorrowTask = createTask(
        id: 'task-tomorrow',
        title: 'Dentist',
        scheduledStart: at(10, 0, 1), // Tomorrow 10:00 AM
        plannedDate: at(0, 0, 1),
      );

      await reminderService.syncTasks([tomorrowTask]);
      expect(fakeAdapter.scheduled.values.first.scheduledDate, at(10, 0, 1));

      // Advance clock through midnight to tomorrow morning
      clockTime = at(0, 5, 1); // 00:05 AM of tomorrow
      await reminderService.onDateRollover(at(0, 0, 1), [tomorrowTask]);

      // Reminder remains scheduled for tomorrow's 10:00 AM
      expect(fakeAdapter.scheduled.values.first.scheduledDate, at(10, 0, 1));

      // At 10:00 AM of tomorrow, it becomes due
      reminderService.setForegroundForTesting(true);
      reminderService.taskListProvider = () => [tomorrowTask];
      clockTime = at(10, 0, 1);
      reminderService.checkDueReminders(clockTime);

      expect(reminderService.currentInAppReminder.value?.id, 'task-tomorrow');
    });

    test('smart context: commitment blocks suppress reminders', () async {
      reminderService.setForegroundForTesting(true);
      final commitmentBlock = createTask(
        id: 'comm-doctor',
        title: 'Doctor Appointment',
        scheduledStart: at(15, 30),
        durationMinutes: 60, // 3:30 PM to 4:30 PM
        isCommitment: true,
      );
      final workTask = createTask(
        id: 'task-work',
        title: 'Draft Report',
        scheduledStart: at(16, 0), // 4:00 PM (falls inside commitment block)
      );

      reminderService.taskListProvider = () => [commitmentBlock, workTask];
      clockTime = at(16, 0);

      reminderService.checkDueReminders(clockTime);

      // Suppressed because user is in an active commitment block
      expect(reminderService.currentInAppReminder.value, isNull);
    });

    test('interaction: tapping system notification does not create second reminder', () async {
      String? openedTaskId;
      DateTime? openedDate;
      reminderService.onOpenTask = (id, date) {
        openedTaskId = id;
        openedDate = date;
      };

      const payload = '{"taskId":"task-gym","scheduledStart":"2026-10-08T16:00:00.000"}';
      fakeAdapter.simulateNotificationTap(payload);

      expect(openedTaskId, 'task-gym');
      expect(openedDate, DateTime(2026, 10, 8, 16, 0));
      // No extra scheduled notification created
      expect(fakeAdapter.scheduled, isEmpty);
    });
  });

  group('Smart Task Reminders - AppStateProvider Integration', () {
    test('provider.addTask at 4 PM schedules reminder via provider', () async {
      final provider = AppStateProvider();
      final added = await provider.addTask(
        title: 'Evening Run',
        durationMinutes: 30,
        difficulty: TaskDifficulty.physical,
        deadline: 'Today',
        category: 'Fitness',
        scheduledStart: at(16, 0),
      );

      expect(fakeAdapter.scheduled.length, 1);
      final notif = fakeAdapter.scheduled.values.first;
      expect(notif.body, contains('Evening Run'));
      expect(notif.scheduledDate, at(16, 0));

      // Reschedule via provider
      await provider.rescheduleTask(
        added.id,
        targetDate: day,
        targetTime: const TimeOfDay(hour: 17, minute: 30),
      );

      expect(fakeAdapter.scheduled.length, 1);
      final updatedNotif = fakeAdapter.scheduled.values.first;
      expect(updatedNotif.scheduledDate, at(17, 30));

      // Complete via provider
      provider.toggleTaskCompletion(added.id);
      expect(fakeAdapter.scheduled, isEmpty);
    });

    test('provider.removeTask cancels reminder', () async {
      final provider = AppStateProvider();
      final added = await provider.addTask(
        title: 'Meditation',
        durationMinutes: 20,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Personal',
        scheduledStart: at(16, 0),
      );
      expect(fakeAdapter.scheduled.length, 1);

      provider.removeTask(added.id);
      expect(fakeAdapter.scheduled, isEmpty);
    });
  });
}
