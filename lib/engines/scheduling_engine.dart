import 'package:intl/intl.dart';
import '../models/task_item.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../theme/flow_colors.dart';

/// Scheduling Engine
/// Matches user tasks against cognitive readiness windows and explicit scheduled times.
/// Strictly schedules REAL user tasks. Never fabricates fake tasks or synthetic lunch breaks.
class SchedulingEngine {
  const SchedulingEngine();

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
    // Sort flexible tasks by urgency (priority high first, then duration)
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
