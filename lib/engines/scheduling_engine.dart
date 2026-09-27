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

/// User Cognitive & Scheduling Planning Profile (Dart Client Mirror)
class PlanningProfile {
  final double wakeTime; // e.g. 7.0 (7:00 AM)
  final double weekendWakeTime; // e.g. 8.5 (8:30 AM)
  final double bedtime; // e.g. 23.0 (11:00 PM)
  final double peakWindowStart; // e.g. 8.5 (8:30 AM)
  final double peakWindowEnd; // e.g. 12.0 (12:00 PM)
  final int warmupMinutes; // e.g. 30, 60
  final List<String> highEnergyTaskTypes;
  final String tiredBehavior; // 'distracted', 'procrastinate', 'slower', 'mistakes'
  final String routineShiftPreference; // 'quick_recovery', 'slower_tempo', 'lighter_work'

  const PlanningProfile({
    this.wakeTime = 7.0,
    this.weekendWakeTime = 8.5,
    this.bedtime = 23.0,
    this.peakWindowStart = 9.5,
    this.peakWindowEnd = 11.75,
    this.warmupMinutes = 30,
    this.highEnergyTaskTypes = const ['coding', 'problem_solving', 'study', 'deep_work'],
    this.tiredBehavior = 'distracted',
    this.routineShiftPreference = 'quick_recovery',
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
    PlanningProfile profile = const PlanningProfile(),
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
        profile: profile,
      );

      // Add allocated slot with buffer to busy intervals for subsequent tasks
      final bufferMins = (task.taskType == TaskType.deepWork || task.taskType == TaskType.study) ? 15 : 10;
      busy.add(MapEntry(eval.slotStart, eval.slotEnd.add(Duration(minutes: bufferMins))));

      enriched.add(
        task.copyWith(
          scheduledStart: task.scheduledStart,
          scheduledEnd: task.scheduledEnd,
          scheduledTime: task.scheduledTime,
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
    PlanningProfile profile = const PlanningProfile(),
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

    // Cognitive profile parameters
    final peakStartHour = profile.peakWindowStart;
    final peakEndHour = profile.peakWindowEnd;
    final bedtimeHour = profile.bedtime;
    final wakeHour = now.weekday >= 6 ? profile.weekendWakeTime : profile.wakeTime;
    final warmupEndHour = wakeHour + (profile.warmupMinutes / 60.0);

    final nowHour = now.hour + now.minute / 60.0;
    final isPastTodayPeak = nowHour > peakEndHour;
    final isNearBedtime = nowHour >= (bedtimeHour - 1.25); // within 1h15m of bedtime
    final isLateEvening = isNearBedtime || nowHour >= 20.0;
    final deadline = task.deadlineAt;

    final lowerTitle = task.title.toLowerCase();
    final isCognitive = task.taskType == TaskType.deepWork ||
        task.taskType == TaskType.study ||
        profile.highEnergyTaskTypes.any((k) => lowerTitle.contains(k)) ||
        lowerTitle.contains('coding') ||
        lowerTitle.contains('code') ||
        lowerTitle.contains('problem solving') ||
        lowerTitle.contains('assignment');

    // Check if deadline requires completion tonight
    bool requiresTonightForDeadline = false;
    if (deadline != null) {
      final hoursUntil = deadline.difference(now).inMinutes / 60.0;
      final isTomorrowMorning = deadline.day == now.day + 1 && deadline.hour <= 10;
      if (hoursUntil <= 14 && (deadline.day == now.day || isTomorrowMorning)) {
        requiresTonightForDeadline = true;
      }
    }
    final deadlineRequiresToday = requiresTonightForDeadline;

    // Determine target day and slot
    DateTime targetStart;
    int dayOffset = 0;
    String primaryReason = 'available_slot';
    final List<String> secondaryReasons = [];
    String explanation;

    if (requiresTonightForDeadline) {
      // Must be scheduled tonight before bedtime to protect deadline!
      var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
      targetStart = cur;
      primaryReason = 'deadline_imminent';
      secondaryReasons.addAll(['deadline_safety_overrides_sleep', 'protects_deadline']);
      final timeStr = DateFormat('h:mm a').format(targetStart);
      explanation = 'Today at $timeStr — Prioritized tonight to protect your upcoming deadline before your bedtime.';
    } else if (isNearBedtime) {
      // SLEEP PROTECTION: Ordinary / no-deadline tasks are moved to tomorrow!
      final tmw = now.add(const Duration(days: 1));
      final tmwWake = tmw.weekday >= 6 ? profile.weekendWakeTime : profile.wakeTime;
      final tmwWarmupEnd = tmwWake + (profile.warmupMinutes / 60.0);

      if (isCognitive) {
        final startH = peakStartHour > tmwWarmupEnd ? peakStartHour : tmwWarmupEnd;
        final h = startH.toInt();
        final m = ((startH % 1) * 60).round();
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, h, m);
        dayOffset = 1;
        primaryReason = 'peak_window';
        secondaryReasons.addAll(['protects_sleep_schedule', 'strong_focus_window']);
        explanation = "Tomorrow at ${DateFormat('h:mm a').format(targetStart)} — That's one of your strongest focus windows with a clear uninterrupted block (protects your sleep schedule).";
      } else if (task.taskType == TaskType.physical) {
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, 16, 30);
        dayOffset = 1;
        primaryReason = 'physical_window';
        secondaryReasons.addAll(['protects_sleep_schedule', 'optimal_workout_window']);
        explanation = 'Tomorrow at 4:30 PM — Moved to tomorrow to protect your sleep schedule and workout recovery.';
      } else {
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, 14, 0);
        dayOffset = 1;
        primaryReason = 'dip_window';
        secondaryReasons.addAll(['protects_sleep_schedule', 'light_work_dip']);
        explanation = 'Tomorrow at 2:00 PM — Moved to tomorrow to protect your sleep schedule and wind-down window.';
      }
    } else if (task.taskType == TaskType.physical) {
      if (nowHour < 16.5) {
        targetStart = DateTime(now.year, now.month, now.day, 16, 30);
        dayOffset = 0;
        primaryReason = 'physical_window';
        secondaryReasons.add('optimal_workout_window');
        explanation = 'Today at 4:30 PM — Ideal physical session window with post-workout recovery space.';
      } else if (nowHour < 18.5) {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        primaryReason = 'physical_window';
        secondaryReasons.add('evening_workout_window');
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Fits your evening workout window.';
      } else {
        // Late evening: schedule for tomorrow late afternoon
        final tmw = now.add(const Duration(days: 1));
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, 16, 30);
        dayOffset = 1;
        primaryReason = 'physical_window';
        secondaryReasons.addAll(['optimal_workout_window', 'scheduled_tomorrow']);
        explanation = 'Tomorrow at 4:30 PM — Ideal late-afternoon workout slot.';
      }
    } else if (task.taskType == TaskType.admin || task.taskType == TaskType.shallowWork) {
      if (nowHour < 14.0) {
        targetStart = DateTime(now.year, now.month, now.day, 14, 0);
        dayOffset = 0;
        primaryReason = 'dip_window';
        secondaryReasons.add('light_work_dip');
        explanation = 'Today at 2:00 PM — Fits your afternoon window to maintain momentum without cognitive strain.';
      } else if (!isLateEvening) {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        primaryReason = 'dip_window';
        secondaryReasons.add('afternoon_admin_window');
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Fits your afternoon availability.';
      } else {
        // Late evening: schedule for tomorrow 2:00 PM
        final tmw = now.add(const Duration(days: 1));
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, 14, 0);
        dayOffset = 1;
        primaryReason = 'dip_window';
        secondaryReasons.addAll(['light_work_dip', 'fresh_start_tomorrow']);
        explanation = 'Tomorrow at 2:00 PM — Fits your afternoon window to maintain momentum without cognitive strain.';
      }
    } else {
      // Deep work, study, creative, or general tasks
      if (!isPastTodayPeak) {
        final startH = peakStartHour > warmupEndHour ? peakStartHour : warmupEndHour;
        final peakDt = DateTime(now.year, now.month, now.day, startH.toInt(), ((startH % 1) * 60).round());
        targetStart = peakDt.isAfter(now) ? peakDt : now;
        dayOffset = 0;
        primaryReason = 'peak_window';
        secondaryReasons.add('strong_focus_window');
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Strong focus window with clear continuity.';
      } else if (!isLateEvening && nowHour < 18.0) {
        var cur = now.minute % 15 == 0 ? now : now.add(Duration(minutes: 15 - (now.minute % 15)));
        targetStart = cur;
        dayOffset = 0;
        primaryReason = 'available_slot';
        secondaryReasons.add('afternoon_focus');
        explanation = 'Today at ${DateFormat('h:mm a').format(targetStart)} — Feasible working slot for focus.';
      } else {
        // Past peak or late evening: schedule for tomorrow morning in peak window
        final tmw = now.add(const Duration(days: 1));
        final tmwWake = tmw.weekday >= 6 ? profile.weekendWakeTime : profile.wakeTime;
        final tmwWarmupEnd = tmwWake + (profile.warmupMinutes / 60.0);
        final startH = peakStartHour > tmwWarmupEnd ? peakStartHour : tmwWarmupEnd;
        targetStart = DateTime(tmw.year, tmw.month, tmw.day, startH.toInt(), ((startH % 1) * 60).round());
        dayOffset = 1;
        primaryReason = 'peak_window';
        secondaryReasons.addAll(['strong_focus_window', 'fresh_start_tomorrow']);
        explanation = "Tomorrow at ${DateFormat('h:mm a').format(targetStart)} — That's one of your strongest focus windows with a clear uninterrupted block.";
      }
    }

    // Ensure slot does not collide with existing busy intervals
    DateTime resolvedStart = targetStart;
    bool foundFree = false;
    while (!foundFree) {
      // If conflict resolution pushes a non-urgent task past bedtime (22:00), roll over to tomorrow!
      if (!deadlineRequiresToday && resolvedStart.day == now.day && resolvedStart.hour >= bedtimeHour) {
        final tmw = now.add(const Duration(days: 1));
        final nextStartHour = (task.taskType == TaskType.physical)
            ? 16
            : (task.taskType == TaskType.admin || task.taskType == TaskType.shallowWork ? 14 : 9);
        final nextStartMin = (task.taskType == TaskType.physical || task.taskType == TaskType.deepWork || task.taskType == TaskType.study) ? 30 : 0;
        resolvedStart = DateTime(tmw.year, tmw.month, tmw.day, nextStartHour, nextStartMin);
        dayOffset = 1;
        primaryReason = 'fresh_start_tomorrow';
        secondaryReasons.addAll(['avoid_late_night_fatigue']);
        explanation = 'Tomorrow at ${DateFormat('h:mm a').format(resolvedStart)} — Avoids late-night fatigue and protects your recovery window.';
      }

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
    dayOffset = resolvedStart.difference(DateTime(now.year, now.month, now.day)).inDays;
    final dayLabel = resolvedStart.day == now.day ? 'Today' : (resolvedStart.day == now.day + 1 ? 'Tomorrow' : DateFormat('MMM d').format(resolvedStart));
    final timeStr = DateFormat('h:mm a').format(resolvedStart);
    final slotDisplay = '$dayLabel · $timeStr';

    return SchedulingSlotEvaluation(
      slotStart: resolvedStart,
      slotEnd: resolvedEnd,
      dayOffset: dayOffset,
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
