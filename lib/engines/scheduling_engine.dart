import 'package:intl/intl.dart';
import '../models/task_item.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../theme/flow_colors.dart';

/// Scheduling Explanation & Slot Result
class SchedulingSlotEvaluation {
  final DateTime slotStart;
  final DateTime slotEnd;
  final int dayOffset; // 0 = Today, 1 = Tomorrow
  final String slotDisplay; // e.g. "Tomorrow · 9:30 AM" or "Today · 2:30 PM"
  final String primaryReason; // e.g. "peak_window", "deadline_imminent", "explicit_time"
  final List<String> secondaryReasons;
  final String explanation; // User-facing "Why this time?"

  const SchedulingSlotEvaluation({
    required this.slotStart,
    required this.slotEnd,
    required this.dayOffset,
    required this.slotDisplay,
    required this.primaryReason,
    required this.secondaryReasons,
    required this.explanation,
  });
}

/// Scheduling Engine
/// Matches user tasks against cognitive readiness windows, deadlines, and hard constraints.
/// Acts as the single calendar scheduling authority. Strictly schedules REAL user tasks.
class SchedulingEngine {
  const SchedulingEngine();

  /// Enriches a list of task candidates with their best feasible slots and deterministic explanations.
  List<TaskItem> enrichTasksWithOptimalSlots(
    List<TaskItem> candidates, {
    List<TaskItem> existingTasks = const [],
    DateTime? nowLocal,
  }) {
    final now = nowLocal ?? DateTime.now();
    final List<TaskItem> enriched = [];
    final List<MapEntry<DateTime, DateTime>> busy = [];

    // Register existing scheduled tasks into busy intervals
    for (final et in existingTasks) {
      if (et.scheduledStart != null && et.scheduledEnd != null) {
        busy.add(MapEntry(et.scheduledStart!, et.scheduledEnd!));
      }
    }

    for (final task in candidates) {
      final eval = evaluateCandidateSlot(
        task,
        existingBusy: busy,
        nowLocal: now,
      );

      // Add allocated slot with buffer to busy intervals for subsequent tasks
      final bufferMins = (task.taskType == TaskType.deepWork || task.taskType == TaskType.study) ? 15 : 10;
      busy.add(MapEntry(eval.slotStart, eval.slotEnd.add(Duration(minutes: bufferMins))));

      enriched.add(
        task.copyWith(
          scheduledStart: task.scheduledStart ?? eval.slotStart,
          scheduledEnd: task.scheduledEnd ?? eval.slotEnd,
          scheduledTime: task.scheduledTime ?? eval.slotDisplay,
          recommendedSlotDisplay: eval.slotDisplay,
          schedulingExplanation: eval.explanation,
          schedulingReasons: {
            'primary_reason': eval.primaryReason,
            'secondary_reasons': eval.secondaryReasons,
          },
        ),
      );
    }

    return enriched;
  }

  /// Evaluates the best feasible slot for a single task candidate.
  SchedulingSlotEvaluation evaluateCandidateSlot(
    TaskItem task, {
    List<MapEntry<DateTime, DateTime>> existingBusy = const [],
    DateTime? nowLocal,
  }) {
    final now = nowLocal ?? DateTime.now();
    final dur = task.durationMinutes > 0 ? task.durationMinutes : 45;

    // 1. Explicit fixed time (User constraint always wins)
    if (task.scheduledStart != null) {
      final s = task.scheduledStart!;
      final e = task.scheduledEnd ?? s.add(Duration(minutes: dur));
      final dayDisplay = s.day == now.day ? 'Today' : (s.day == now.day + 1 ? 'Tomorrow' : DateFormat('MMM d').format(s));
      final timeDisplay = DateFormat('h:mm a').format(s);
      return SchedulingSlotEvaluation(
        slotStart: s,
        slotEnd: e,
        dayOffset: s.difference(DateTime(now.year, now.month, now.day)).inDays,
        slotDisplay: '$dayDisplay · $timeDisplay',
        primaryReason: 'explicit_time',
        secondaryReasons: const ['user_specified_time'],
        explanation: 'Scheduled at your requested time ($timeDisplay).',
      );
    }

    // Baseline cognitive windows (default profile)
    const peakStartHour = 9.5; // 9:30 AM
    const peakEndHour = 11.75; // 11:45 AM
    const dipStartHour = 14.0; // 2:00 PM
    const dipEndHour = 15.5; // 3:30 PM
    const bedtimeHour = 23; // 11:00 PM

    final nowHour = now.hour + now.minute / 60.0;
    final isPastTodayPeak = nowHour > peakEndHour;
    final deadline = task.deadlineAt;

    // Check if task has an imminent deadline (e.g. tomorrow before 10 AM or tonight)
    bool deadlineRequiresToday = false;
    if (deadline != null) {
      final hoursUntil = deadline.difference(now).inMinutes / 60.0;
      if (hoursUntil <= 16) {
        deadlineRequiresToday = true;
      }
    }

    // Determine target day and slot
    DateTime targetStart;
    int dayOffset = 0;
    String primaryReason = 'available_slot';
    final List<String> secondaryReasons = [];
    String explanation;

    // Rule: If past preferred window today and no urgent deadline, recommend Tomorrow morning!
    // But if urgent deadline (e.g. due tomorrow morning at 8:00 AM), deadline overrides peak window -> schedule Today!
    if (isPastTodayPeak && !deadlineRequiresToday && (task.taskType == TaskType.deepWork || task.taskType == TaskType.study)) {
      dayOffset = 1;
      final tmw = now.add(const Duration(days: 1));
      targetStart = DateTime(tmw.year, tmw.month, tmw.day, 9, 30);
      primaryReason = 'peak_window';
      secondaryReasons.addAll(['strong_focus_window', 'fresh_start_tomorrow']);
      explanation = "Tomorrow at 9:30 AM — That's one of your strongest focus windows with a clear uninterrupted block.";
    } else if (deadlineRequiresToday) {
      // Must be scheduled today to beat the deadline!
      dayOffset = 0;
      var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
      targetStart = cur;
      primaryReason = 'deadline_imminent';
      secondaryReasons.addAll(['imminent_deadline', 'protects_deadline']);
      final timeStr = DateFormat('h:mm a').format(targetStart);
      explanation = 'Today at $timeStr — Prioritized today to protect your upcoming deadline.';
    } else if (task.taskType == TaskType.admin || task.taskType == TaskType.shallowWork) {
      // Admin / light work fits dip window or afternoon
      final dipDt = DateTime(now.year, now.month, now.day, 14, 0);
      if (dipDt.isAfter(now)) {
        targetStart = dipDt;
        dayOffset = 0;
        primaryReason = 'dip_window';
        secondaryReasons.add('light_work_dip');
        explanation = 'Today at 2:00 PM — Fits your afternoon window to maintain momentum without cognitive strain.';
      } else {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Fits your afternoon availability.';
      }
    } else if (task.taskType == TaskType.physical) {
      // Physical fits early morning or late afternoon
      final pmDt = DateTime(now.year, now.month, now.day, 16, 30);
      if (pmDt.isAfter(now)) {
        targetStart = pmDt;
        dayOffset = 0;
        primaryReason = 'physical_window';
        secondaryReasons.add('optimal_workout_window');
        explanation = 'Today at 4:30 PM — Ideal physical session window with post-workout recovery space.';
      } else {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Ideal workout slot.';
      }
    } else {
      // Normal flexible deep work / task
      if (!isPastTodayPeak) {
        final peakDt = DateTime(now.year, now.month, now.day, 9, 30);
        targetStart = peakDt.isAfter(now) ? peakDt : now;
        dayOffset = 0;
        primaryReason = 'peak_window';
        secondaryReasons.add('strong_focus_window');
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Strong focus window with clear continuity.';
      } else {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Feasible working slot.';
      }
    }

    // Ensure slot does not collide with existing busy intervals
    DateTime resolvedStart = targetStart;
    bool foundFree = false;
    while (!foundFree) {
      final candEnd = resolvedStart.add(Duration(minutes: dur));
      DateTime? conflictEnd;
      for (final b in existingBusy) {
        if (resolvedStart.isBefore(b.value) && candEnd.isAfter(b.key)) {
          conflictEnd = (conflictEnd == null || b.value.isAfter(conflictEnd)) ? b.value : conflictEnd;
        }
      }
      if (conflictEnd == null) {
        foundFree = true;
      } else {
        resolvedStart = conflictEnd.add(const Duration(minutes: 5));
      }
    }

    final resolvedEnd = resolvedStart.add(Duration(minutes: dur));
    final dayLabel = resolvedStart.day == now.day ? 'Today' : (resolvedStart.day == now.day + 1 ? 'Tomorrow' : DateFormat('MMM d').format(resolvedStart));
    final timeStr = DateFormat('h:mm a').format(resolvedStart);
    final slotDisplay = '$dayLabel · $timeStr';

    return SchedulingSlotEvaluation(
      slotStart: resolvedStart,
      slotEnd: resolvedEnd,
      dayOffset: resolvedStart.difference(DateTime(now.year, now.month, now.day)).inDays,
      slotDisplay: slotDisplay,
      primaryReason: primaryReason,
      secondaryReasons: secondaryReasons,
      explanation: explanation,
    );
  }

  List<ScheduleItem> generateOptimizedSchedule({
    required List<TaskItem> tasks,
    required ReadinessModel readiness,
  }) {
    final List<ScheduleItem> schedule = [];

    // Filter uncompleted tasks
    final pendingTasks = tasks.where((t) => !t.isCompleted).toList();
    if (pendingTasks.isEmpty) {
      return [];
    }

    final now = DateTime.now();

    // 1. Anchored tasks (explicitly scheduled by the user)
    final anchoredTasks = pendingTasks.where((t) => t.scheduledStart != null).toList();
    final flexibleTasks = pendingTasks.where((t) => t.scheduledStart == null).toList();

    for (final task in anchoredTasks) {
      final sStart = task.scheduledStart!;
      final timeStr = DateFormat('h:mm').format(sStart);
      final periodStr = DateFormat('a').format(sStart);

      schedule.add(
        ScheduleItem(
          id: 'sched-${task.id}',
          time: timeStr,
          period: periodStr,
          title: task.title,
          type: _resolveTaskTypeLabel(task),
          tagText: _resolveTagText(task),
          tagBg: _resolveTagBg(task),
          tagColor: _resolveTagColor(task),
          isActive: task.status == TaskStatus.inProgress,
          durationMinutes: task.durationMinutes,
        ),
      );
    }

    // 2. Schedule flexible tasks
    flexibleTasks.sort((a, b) {
      if (a.isPriority != b.isPriority) {
        return a.isPriority ? -1 : 1;
      }
      return b.durationMinutes.compareTo(a.durationMinutes);
    });

    DateTime cursor = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
    if (cursor.hour < 9) {
      cursor = DateTime(now.year, now.month, now.day, 9, 0);
    }

    for (final task in flexibleTasks) {
      final timeStr = DateFormat('h:mm').format(cursor);
      final periodStr = DateFormat('a').format(cursor);

      schedule.add(
        ScheduleItem(
          id: 'sched-${task.id}',
          time: timeStr,
          period: periodStr,
          title: task.title,
          type: _resolveTaskTypeLabel(task),
          tagText: _resolveTagText(task),
          tagBg: _resolveTagBg(task),
          tagColor: _resolveTagColor(task),
          isActive: task.status == TaskStatus.inProgress,
          durationMinutes: task.durationMinutes,
        ),
      );

      cursor = cursor.add(Duration(minutes: task.durationMinutes + 15));
    }

    return schedule;
  }

  static String _resolveTaskTypeLabel(TaskItem task) {
    switch (task.taskType) {
      case TaskType.deepWork:
        return 'High Focus';
      case TaskType.study:
        return 'Study';
      case TaskType.admin:
        return 'Admin';
      case TaskType.physical:
        return 'Physical';
      default:
        return 'Focus';
    }
  }

  static String _resolveTagText(TaskItem task) {
    switch (task.taskType) {
      case TaskType.deepWork:
        return 'DEEP WORK';
      case TaskType.study:
        return 'MEDIUM';
      case TaskType.admin:
        return 'LIGHT';
      case TaskType.physical:
        return 'PHYSICAL';
      default:
        return 'TASK';
    }
  }

  static dynamic _resolveTagBg(TaskItem task) {
    switch (task.taskType) {
      case TaskType.deepWork:
        return FlowColors.tagDeepWorkBg;
      case TaskType.study:
        return FlowColors.tagMediumBg;
      case TaskType.admin:
        return FlowColors.tagLightBg;
      case TaskType.physical:
        return FlowColors.tagPhysicalBg;
      default:
        return FlowColors.tagMediumBg;
    }
  }

  static dynamic _resolveTagColor(TaskItem task) {
    switch (task.taskType) {
      case TaskType.deepWork:
        return FlowColors.tagDeepWorkText;
      case TaskType.study:
        return FlowColors.tagMediumText;
      case TaskType.admin:
        return FlowColors.tagLightText;
      case TaskType.physical:
        return FlowColors.tagPhysicalText;
      default:
        return FlowColors.tagMediumText;
    }
  }
}
