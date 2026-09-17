enum TaskDifficulty {
  high, // Deep Work (Cyan/Mint)
  medium, // Medium Focus / Study (Mint)
  light, // Light / Admin (Ice Blue)
  physical, // Physical / Health (Deep Teal)
}

extension TaskDifficultyExtension on TaskDifficulty {
  String get label {
    switch (this) {
      case TaskDifficulty.high:
        return 'High Focus';
      case TaskDifficulty.medium:
        return 'Medium Focus';
      case TaskDifficulty.light:
        return 'Light';
      case TaskDifficulty.physical:
        return 'Physical';
    }
  }

  String get tagText {
    switch (this) {
      case TaskDifficulty.high:
        return 'DEEP WORK';
      case TaskDifficulty.medium:
        return 'MEDIUM';
      case TaskDifficulty.light:
        return 'LIGHT';
      case TaskDifficulty.physical:
        return 'PHYSICAL';
    }
  }
}

/// Task Data Model
/// Incorporates Difficulty, Duration, Deadline, and Category.
class TaskItem {
  final String id;
  final String title;
  final int durationMinutes;
  final TaskDifficulty difficulty;
  final String deadline; // e.g. "Due Tomorrow", "Friday", "Today"
  final String category; // "College", "Work", "Personal", "Fitness", "Study"
  final bool isCompleted;
  final String? scheduledTime; // e.g. "9:30 AM"
  final bool isPriority;

  const TaskItem({
    required this.id,
    required this.title,
    required this.durationMinutes,
    required this.difficulty,
    required this.deadline,
    required this.category,
    this.isCompleted = false,
    this.scheduledTime,
    this.isPriority = false,
  });

  TaskItem copyWith({
    String? id,
    String? title,
    int? durationMinutes,
    TaskDifficulty? difficulty,
    String? deadline,
    String? category,
    bool? isCompleted,
    String? scheduledTime,
    bool? isPriority,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      difficulty: difficulty ?? this.difficulty,
      deadline: deadline ?? this.deadline,
      category: category ?? this.category,
      isCompleted: isCompleted ?? this.isCompleted,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      isPriority: isPriority ?? this.isPriority,
    );
  }
}
