import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../components/task_date_time_pickers.dart';
import '../engines/task_state.dart';
import '../models/task_item.dart';
import 'flow_clock.dart';
import 'timezone_service.dart';

/// Lightweight data holder for pending notifications.
class PendingReminderInfo {
  final int id;
  final String? title;
  final String? body;
  final String? payload;
  final DateTime? scheduledDate;

  const PendingReminderInfo({
    required this.id,
    this.title,
    this.body,
    this.payload,
    this.scheduledDate,
  });
}

/// Abstract adapter enabling test mocking and platform abstraction.
abstract class NotificationAdapter {
  Future<void> initialize({
    required void Function(String? payload) onSelectNotification,
  });

  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String timezone,
    String? payload,
  });

  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<PendingReminderInfo>> getPendingReminders();
}

/// Production notification adapter backed by flutter_local_notifications.
class FlutterLocalNotificationsAdapter implements NotificationAdapter {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  @override
  Future<void> initialize({
    required void Function(String? payload) onSelectNotification,
  }) async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');
      const windowsSettings = WindowsInitializationSettings(
        appName: 'Flowstate',
        appUserModelId: 'Flowstate.App',
        guid: 'd198533e-cf97-4c48-81e0-6a987d60980c',
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
        linux: linuxSettings,
        windows: windowsSettings,
      );

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (response) {
          onSelectNotification(response.payload);
        },
      );
      _initialized = true;
    } catch (e) {
      debugPrint('Local notifications init fallback: $e');
    }
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String timezone,
    String? payload,
  }) async {
    if (!_initialized) return;
    try {
      tz.Location location;
      try {
        location = tz.getLocation(timezone);
      } catch (_) {
        location = tz.local;
      }

      final tzScheduled = tz.TZDateTime.from(scheduledDate, location);

      const androidDetails = AndroidNotificationDetails(
        'flowstate_task_reminders',
        'Task Reminders',
        channelDescription: 'Intelligent reminders for scheduled Flowstate tasks',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
      );

      const darwinDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: darwinDetails,
        macOS: darwinDetails,
      );

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzScheduled,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (e) {
      debugPrint('Local notification schedule notice: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    if (!_initialized) return;
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      debugPrint('Local notification cancel notice: $e');
    }
  }

  @override
  Future<void> cancelAll() async {
    if (!_initialized) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Local notification cancelAll notice: $e');
    }
  }

  @override
  Future<List<PendingReminderInfo>> getPendingReminders() async {
    try {
      final list = await _plugin.pendingNotificationRequests();
      return list
          .map((r) => PendingReminderInfo(id: r.id, title: r.title, body: r.body, payload: r.payload))
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

/// Fake in-memory notification adapter for unit & widget tests.
class FakeNotificationAdapter implements NotificationAdapter {
  final Map<int, PendingReminderInfo> scheduled = {};
  final List<int> cancelledIds = [];
  void Function(String? payload)? onSelect;

  @override
  Future<void> initialize({
    required void Function(String? payload) onSelectNotification,
  }) async {
    onSelect = onSelectNotification;
  }

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String timezone,
    String? payload,
  }) async {
    scheduled[id] = PendingReminderInfo(
      id: id,
      title: title,
      body: body,
      payload: payload,
      scheduledDate: scheduledDate,
    );
  }

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    scheduled.clear();
  }

  @override
  Future<List<PendingReminderInfo>> getPendingReminders() async {
    return scheduled.values.toList();
  }

  void simulateNotificationTap(String? payload) {
    onSelect?.call(payload);
  }
}

/// Smart task reminder service managing local notifications, intelligent suppression,
/// deterministic IDs, timezone alignment, and in-app Noya companion popups.
class SmartReminderService with WidgetsBindingObserver {
  static SmartReminderService? _instance;
  static SmartReminderService get instance => _instance ??= SmartReminderService();

  @visibleForTesting
  static void setInstanceForTesting(SmartReminderService service) {
    _instance = service;
  }

  @visibleForTesting
  static void resetInstance() {
    _instance?.dispose();
    _instance = null;
  }

  NotificationAdapter adapter;
  final DateTime Function() _clock;
  final Future<String?> Function() _timezoneGetter;

  bool _isForeground = true;
  bool get isForeground => _isForeground;

  /// Active task the user is viewing / editing (e.g. in EditTaskSheet).
  String? activeViewingTaskId;

  /// True while task creation sheet is open.
  bool isCreatingTask = false;

  /// Task currently running a focus session.
  String? activeFocusTaskId;

  /// Provider for the full live task list to verify schedule state and commitment blocks.
  List<TaskItem> Function()? taskListProvider;

  /// Callback when a notification or in-app reminder is tapped to navigate to the task.
  void Function(String taskId, DateTime? targetDate)? onOpenTask;

  /// Currently active in-app reminder (broadcasts to UI overlay).
  final ValueNotifier<TaskItem?> currentInAppReminder = ValueNotifier<TaskItem?>(null);

  /// Map of taskId -> deterministic notification ID.
  final Map<String, int> _scheduledNotificationIds = {};

  /// Map of taskId -> scheduled DateTime.
  final Map<String, DateTime> _scheduledNotificationTimes = {};

  /// Set of taskId:scheduledStartIso keys that already fired.
  final Set<String> _firedReminders = {};

  /// Recorded task creation times to ensure tasks created after scheduled start never immediately fire.
  final Map<String, DateTime> _taskCreationTimes = {};

  SmartReminderService({
    NotificationAdapter? adapter,
    DateTime Function()? clock,
    Future<String?> Function()? timezoneGetter,
  })  : adapter = adapter ?? FlutterLocalNotificationsAdapter(),
        _clock = clock ?? FlowClock.currentTime,
        _timezoneGetter = timezoneGetter ?? TimezoneService.localIanaName {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  Future<void> initialize() async {
    await adapter.initialize(onSelectNotification: handleNotificationTap);
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    currentInAppReminder.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = (state == AppLifecycleState.resumed);
  }

  @visibleForTesting
  void setForegroundForTesting(bool value) {
    _isForeground = value;
  }

  /// Calculates deterministic 31-bit positive notification ID for a task reminder.
  static int deterministicNotificationId(String taskId, [DateTime? date, String type = 'reminder']) {
    final dateStr = date != null
        ? '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'
        : '';
    final raw = '$taskId:$dateStr:$type';
    var hash = 0;
    for (var i = 0; i < raw.length; i++) {
      hash = (31 * hash + raw.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Extracts the effective local scheduled start DateTime of a task.
  static DateTime? getScheduledStartTime(TaskItem task) {
    if (task.scheduledStart != null) {
      return task.scheduledStart!.toLocal();
    }
    if (task.plannedDate != null && task.scheduledTime != null) {
      final parsedTime = TaskDateTimePickers.parseTimeString(task.scheduledTime);
      if (parsedTime != null) {
        final planned = task.plannedDate!;
        return DateTime(
          planned.year,
          planned.month,
          planned.day,
          parsedTime.hour,
          parsedTime.minute,
        );
      }
    }
    return null;
  }

  /// Returns whether a task is inside an active unavailable/commitment block.
  bool isInsideCommitmentBlock(DateTime now) {
    final tasks = taskListProvider?.call();
    if (tasks == null) return false;
    for (final t in tasks) {
      if (t.isCommitment && t.scheduledStart != null) {
        final start = t.scheduledStart!.toLocal();
        final end = t.scheduledEnd?.toLocal() ?? start.add(Duration(minutes: t.durationMinutes));
        if (!now.isBefore(start) && now.isBefore(end)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Evaluates smart suppression criteria.
  bool isTaskSuppressed(TaskItem task, {DateTime? now}) {
    final current = now ?? _clock();

    // 1. Task already completed
    if (task.isCompleted || task.status == TaskStatus.completed) return true;

    // 2. Task cancelled, skipped, or archived
    if (task.status == TaskStatus.cancelled || task.status == TaskStatus.archived) return true;

    // 3. Task is a fixed commitment block (not a work task to start)
    if (task.isCommitment) return true;

    // 4. User is currently creating a task
    if (isCreatingTask) return true;

    // 5. User is currently viewing or editing this same task
    if (activeViewingTaskId != null && activeViewingTaskId == task.id) return true;

    // 6. Task is already active / in progress
    if (task.status == TaskStatus.inProgress || activeFocusTaskId == task.id) return true;

    // 7. Currently inside another explicit commitment block
    if (isInsideCommitmentBlock(current)) return true;

    // 8. Period where task is no longer actionable (slot has ended)
    final start = getScheduledStartTime(task);
    if (start != null) {
      final end = task.scheduledEnd?.toLocal() ?? start.add(Duration(minutes: task.durationMinutes));
      if (slotHasEnded(end, current)) return true;
    }

    return false;
  }

  /// Schedules a local notification for a future scheduled task.
  Future<void> scheduleReminder(TaskItem task, {DateTime? now}) async {
    final current = now ?? _clock();
    final start = getScheduledStartTime(task);
    if (start == null) return;

    // If scheduled time is in the past, do NOT schedule or notify.
    if (start.isBefore(current) || start.isAtSameMomentAs(current)) {
      return;
    }

    // Check suppression
    if (isTaskSuppressed(task, now: current)) {
      return;
    }

    // Cancel old notification if time changed
    final existingTime = _scheduledNotificationTimes[task.id];
    if (existingTime != null && existingTime != start) {
      await cancelReminder(task.id);
    }

    final id = deterministicNotificationId(task.id, start);
    _scheduledNotificationIds[task.id] = id;
    _scheduledNotificationTimes[task.id] = start;

    final tzName = (await _timezoneGetter()) ?? 'UTC';
    final formattedTime = DateFormat('h:mm a').format(start);
    final payload = jsonEncode({
      'taskId': task.id,
      'scheduledStart': start.toIso8601String(),
    });

    await adapter.schedule(
      id: id,
      title: 'Noya \u{1F98A}',
      body: 'Time for ${task.title}\nYou planned this for $formattedTime.',
      scheduledDate: start,
      timezone: tzName,
      payload: payload,
    );
  }

  /// Cancels any scheduled reminder for the given task.
  Future<void> cancelReminder(String taskId) async {
    final id = _scheduledNotificationIds.remove(taskId);
    _scheduledNotificationTimes.remove(taskId);
    if (id != null) {
      await adapter.cancel(id);
    }
    if (currentInAppReminder.value?.id == taskId) {
      dismissInAppReminder();
    }
  }

  /// Checks for due tasks during minute boundary ticks when app is in the foreground.
  void checkDueReminders(DateTime now) {
    if (!_isForeground) return;

    final tasks = taskListProvider?.call();
    if (tasks == null || tasks.isEmpty) return;

    for (final task in tasks) {
      final start = getScheduledStartTime(task);
      if (start == null) continue;

      // Exact minute match
      final isSameMinute = start.year == now.year &&
          start.month == now.month &&
          start.day == now.day &&
          start.hour == now.hour &&
          start.minute == now.minute;

      if (!isSameMinute) continue;

      final fireKey = '${task.id}:${start.toIso8601String()}';
      if (_firedReminders.contains(fireKey)) continue;

      // Check if task was created after its scheduled time
      final createdAt = task.createdAt ?? _taskCreationTimes[task.id];
      if (createdAt != null && createdAt.isAfter(start)) {
        continue;
      }

      // Check suppression
      if (isTaskSuppressed(task, now: now)) continue;

      // Mark fired once
      _firedReminders.add(fireKey);

      // Cancel OS notification so user doesn't get duplicate system notification in foreground
      final id = _scheduledNotificationIds[task.id];
      if (id != null) {
        adapter.cancel(id);
      }

      // Show in-app Noya companion popup
      currentInAppReminder.value = task;
    }
  }

  /// Dismisses the in-app popup.
  void dismissInAppReminder() {
    currentInAppReminder.value = null;
  }

  /// User acted on in-app reminder (e.g. "Start").
  void handleInAppAction(BuildContext context, TaskItem task) {
    dismissInAppReminder();
    final start = getScheduledStartTime(task);
    onOpenTask?.call(task.id, start);
  }

  /// User tapped a system notification.
  void handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final taskId = data['taskId'] as String?;
      final startIso = data['scheduledStart'] as String?;
      if (taskId == null) return;

      DateTime? targetDate;
      if (startIso != null) {
        targetDate = DateTime.tryParse(startIso);
      }

      // Mark as fired/acknowledged so handling the tap does not create a second reminder
      if (startIso != null) {
        _firedReminders.add('$taskId:$startIso');
      }

      onOpenTask?.call(taskId, targetDate);
    } catch (e) {
      debugPrint('Error handling notification tap: $e');
    }
  }

  /// Handler when a new task is added.
  Future<void> onTaskAdded(TaskItem task, {DateTime? now}) async {
    final current = now ?? _clock();
    _taskCreationTimes[task.id] = current;

    final start = getScheduledStartTime(task);
    if (start != null && (start.isBefore(current) || start.isAtSameMomentAs(current))) {
      // Created in the past -> never immediately notify
      return;
    }

    await scheduleReminder(task, now: current);
  }

  /// Handler when a task is updated or edited.
  Future<void> onTaskUpdated(TaskItem task, TaskItem? previous, {DateTime? now}) async {
    final current = now ?? _clock();

    if (task.isCompleted ||
        task.status == TaskStatus.completed ||
        task.status == TaskStatus.cancelled ||
        task.status == TaskStatus.archived ||
        task.isCommitment) {
      await cancelReminder(task.id);
      return;
    }

    final newStart = getScheduledStartTime(task);
    final oldStart = previous != null ? getScheduledStartTime(previous) : null;

    if (newStart != oldStart) {
      await cancelReminder(task.id);
      if (newStart != null && newStart.isAfter(current)) {
        await scheduleReminder(task, now: current);
      }
    } else if (newStart != null && newStart.isAfter(current)) {
      await scheduleReminder(task, now: current);
    }
  }

  /// Handler when a task is rescheduled.
  Future<void> onTaskRescheduled(TaskItem task, {DateTime? now}) async {
    final current = now ?? _clock();
    await cancelReminder(task.id);
    final start = getScheduledStartTime(task);
    if (start != null && start.isAfter(current)) {
      await scheduleReminder(task, now: current);
    }
  }

  /// Handler when a task is completed.
  Future<void> onTaskCompleted(String taskId) async {
    await cancelReminder(taskId);
  }

  /// Handler when a task is skipped.
  Future<void> onTaskSkipped(String taskId) async {
    await cancelReminder(taskId);
  }

  /// Handler when a task is deleted.
  Future<void> onTaskDeleted(String taskId) async {
    await cancelReminder(taskId);
  }

  /// Handler when replan changes are applied.
  Future<void> onReplanApplied(List<TaskItem> tasks, {DateTime? now}) async {
    await syncTasks(tasks, now: now);
  }

  /// Handler when calendar date rolls over.
  Future<void> onDateRollover(DateTime newDate, List<TaskItem> tasks, {DateTime? now}) async {
    await syncTasks(tasks, now: now);
  }

  /// Full idempotent sync across all tasks.
  Future<void> syncTasks(List<TaskItem> tasks, {DateTime? now}) async {
    final current = now ?? _clock();
    final activeIds = tasks.map((t) => t.id).toSet();

    // Cancel reminders for tasks no longer present
    final removed = _scheduledNotificationIds.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in removed) {
      await cancelReminder(id);
    }

    for (final task in tasks) {
      if (task.isCompleted ||
          task.status == TaskStatus.completed ||
          task.status == TaskStatus.cancelled ||
          task.status == TaskStatus.archived ||
          task.isCommitment) {
        if (_scheduledNotificationIds.containsKey(task.id)) {
          await cancelReminder(task.id);
        }
        continue;
      }

      final start = getScheduledStartTime(task);
      if (start == null || start.isBefore(current) || start.isAtSameMomentAs(current)) {
        if (_scheduledNotificationIds.containsKey(task.id)) {
          await cancelReminder(task.id);
        }
        continue;
      }

      // Idempotency: skip if already scheduled for the exact same start time
      if (_scheduledNotificationTimes[task.id] == start) {
        continue;
      }

      await scheduleReminder(task, now: current);
    }
  }

  @visibleForTesting
  Map<String, int> get scheduledNotificationIds => Map.unmodifiable(_scheduledNotificationIds);

  @visibleForTesting
  Map<String, DateTime> get scheduledNotificationTimes => Map.unmodifiable(_scheduledNotificationTimes);

  @visibleForTesting
  Set<String> get firedReminders => Set.unmodifiable(_firedReminders);
}
