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

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    TaskDifficulty diff = TaskDifficulty.medium;
    final diffStr = (json['difficulty'] as String?)?.toLowerCase();
    if (diffStr == 'high' || diffStr == 'deep work') {
      diff = TaskDifficulty.high;
    } else if (diffStr == 'light' || diffStr == 'admin') {
      diff = TaskDifficulty.light;
    } else if (diffStr == 'physical' || diffStr == 'health') {
      diff = TaskDifficulty.physical;
    }

    return TaskItem(
      id: json['id'] as String? ?? 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Untitled Task',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 45,
      difficulty: diff,
      deadline: json['deadline'] as String? ?? 'Today',
      category: json['category'] as String? ?? 'General',
      isCompleted: json['is_completed'] as bool? ?? false,
      scheduledTime: json['scheduled_time'] as String?,
      isPriority: json['is_priority'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'duration_minutes': durationMinutes,
        'difficulty': difficulty.name,
        'deadline': deadline,
        'category': category,
        'is_completed': isCompleted,
        'scheduled_time': scheduledTime,
        'is_priority': isPriority,
      };
}
