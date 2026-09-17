import '../models/task_item.dart';
import '../models/readiness_model.dart';
import '../models/schedule_item.dart';
import '../theme/flow_colors.dart';

/// Scheduling Engine
/// Matches task difficulty, duration, and deadlines against optimal cognitive readiness windows.
class SchedulingEngine {
  const SchedulingEngine();

  List<ScheduleItem> generateOptimizedSchedule({
    required List<TaskItem> tasks,
    required ReadinessModel readiness,
  }) {
    final List<ScheduleItem> schedule = [];

    // Filter uncompleted tasks
    final pendingTasks = tasks.where((t) => !t.isCompleted).toList();

    // 1. Primary Deep Work during peak focus window (e.g. 9:30 AM)
    final deepWorkTasks = pendingTasks.where((t) => t.difficulty == TaskDifficulty.high).toList();
    if (deepWorkTasks.isNotEmpty) {
      final task = deepWorkTasks.first;
      schedule.add(
        ScheduleItem(
          id: 'sched-1',
          time: '9:30',
          period: 'AM',
          title: task.title,
          type: 'High Focus',
          tagText: 'DEEP WORK',
          tagBg: FlowColors.tagDeepWorkBg,
          tagColor: FlowColors.tagDeepWorkText,
          durationMinutes: task.durationMinutes,
        ),
      );
    }

    // 2. Medium focus task before lunch (e.g. 11:30 AM)
    final mediumTasks = pendingTasks.where((t) => t.difficulty == TaskDifficulty.medium).toList();
    if (mediumTasks.isNotEmpty) {
      final task = mediumTasks.first;
      schedule.add(
        ScheduleItem(
          id: 'sched-2',
          time: '11:30',
          period: 'AM',
          title: task.title,
          type: 'Study',
          tagText: 'MEDIUM',
          tagBg: FlowColors.tagMediumBg,
          tagColor: FlowColors.tagMediumText,
          isActive: true,
          durationMinutes: task.durationMinutes,
        ),
      );
    }

    // 3. Natural Rest / Recovery break at midday (1:00 PM)
    schedule.add(
      const ScheduleItem(
        id: 'sched-3',
        time: '1:00',
        period: 'PM',
        title: 'Lunch & Recovery Walk',
        type: 'Rest',
        tagText: 'REST',
        tagBg: FlowColors.tagRestBg,
        tagColor: FlowColors.tagRestText,
        durationMinutes: 45,
      ),
    );

    // 4. Light/Admin task during energy dip window (2:30 PM)
    final lightTasks = pendingTasks.where((t) => t.difficulty == TaskDifficulty.light).toList();
    if (lightTasks.isNotEmpty) {
      final task = lightTasks.first;
      schedule.add(
        ScheduleItem(
          id: 'sched-4',
          time: '2:30',
          period: 'PM',
          title: task.title,
          type: 'Admin',
          tagText: 'LIGHT',
          tagBg: FlowColors.tagLightBg,
          tagColor: FlowColors.tagLightText,
          durationMinutes: task.durationMinutes,
        ),
      );
    }

    // 5. Physical or Fitness block later in the afternoon (5:30 PM)
    final physicalTasks = pendingTasks.where((t) => t.difficulty == TaskDifficulty.physical).toList();
    if (physicalTasks.isNotEmpty) {
      final task = physicalTasks.first;
      schedule.add(
        ScheduleItem(
          id: 'sched-5',
          time: '5:30',
          period: 'PM',
          title: task.title,
          type: 'Health',
          tagText: 'PHYSICAL',
          tagBg: FlowColors.tagPhysicalBg,
          tagColor: FlowColors.tagPhysicalText,
          durationMinutes: task.durationMinutes,
        ),
      );
    } else {
      schedule.add(
        const ScheduleItem(
          id: 'sched-5',
          time: '5:30',
          period: 'PM',
          title: 'Gym Session',
          type: 'Health',
          tagText: 'PHYSICAL',
          tagBg: FlowColors.tagPhysicalBg,
          tagColor: FlowColors.tagPhysicalText,
          durationMinutes: 60,
        ),
      );
    }

    return schedule;
  }
}
