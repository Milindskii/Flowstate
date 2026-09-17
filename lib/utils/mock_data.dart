import '../models/task_item.dart';
import '../models/personal_data.dart';

class MockData {
  MockData._();

  static PersonalData get initialPersonalData => const PersonalData(
        sleepHours: 7.5,
        wakeTime: '6:45 AM',
        sleepQuality: 'Restful',
        focusPeak: 'Morning',
        energyDipTime: '2:30 PM',
        physicalActivityMinutes: 45,
        primaryGoal: 'College',
      );

  static List<TaskItem> get initialTasks => [
        const TaskItem(
          id: 'task-1',
          title: 'Finish ML Assignment',
          durationMinutes: 90,
          difficulty: TaskDifficulty.high,
          deadline: 'Due Tomorrow',
          category: 'College',
          isPriority: true,
          scheduledTime: '9:30 AM',
        ),
        const TaskItem(
          id: 'task-2',
          title: 'Review DBMS Notes',
          durationMinutes: 45,
          difficulty: TaskDifficulty.medium,
          deadline: 'Due Friday',
          category: 'College',
          isPriority: true,
          scheduledTime: '11:30 AM',
        ),
        const TaskItem(
          id: 'task-3',
          title: 'Weekly Grocery Shopping',
          durationMinutes: 30,
          difficulty: TaskDifficulty.light,
          deadline: 'Due Today',
          category: 'Personal',
        ),
        const TaskItem(
          id: 'task-4',
          title: 'Gym: Upper Body Session',
          durationMinutes: 60,
          difficulty: TaskDifficulty.physical,
          deadline: 'Due Today',
          category: 'Fitness',
          scheduledTime: '5:30 PM',
        ),
        const TaskItem(
          id: 'task-5',
          title: 'Update Portfolio Website',
          durationMinutes: 120,
          difficulty: TaskDifficulty.high,
          deadline: 'Next Week',
          category: 'Personal',
        ),
        const TaskItem(
          id: 'task-6',
          title: 'Research Paper Deep Dive',
          durationMinutes: 75,
          difficulty: TaskDifficulty.high,
          deadline: 'Due Sunday',
          category: 'Study',
        ),
        const TaskItem(
          id: 'task-7',
          title: 'Team Standup & Sync',
          durationMinutes: 25,
          difficulty: TaskDifficulty.light,
          deadline: 'Today',
          category: 'Work',
          scheduledTime: '2:30 PM',
        ),
        const TaskItem(
          id: 'task-8',
          title: 'Evening Mobility & Stretch',
          durationMinutes: 20,
          difficulty: TaskDifficulty.physical,
          deadline: 'Tonight',
          category: 'Health',
        ),
      ];

  static const List<String> categories = [
    'All',
    'Work',
    'Personal',
    'Study',
    'Health',
  ];
}
