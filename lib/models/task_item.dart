import 'package:intl/intl.dart';

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

enum TaskStatus {
  todo,
  inProgress,
  completed,
  cancelled,
  postponed,
  archived;

  static TaskStatus fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'in_progress':
      case 'inprogress':
        return TaskStatus.inProgress;
      case 'completed':
        return TaskStatus.completed;
      case 'cancelled':
      case 'canceled':
        return TaskStatus.cancelled;
      case 'postponed':
        return TaskStatus.postponed;
      case 'archived':
        return TaskStatus.archived;
      case 'todo':
      default:
        return TaskStatus.todo;
    }
  }

  String get value {
    switch (this) {
      case TaskStatus.inProgress:
        return 'in_progress';
      case TaskStatus.completed:
        return 'completed';
      case TaskStatus.cancelled:
        return 'cancelled';
      case TaskStatus.postponed:
        return 'postponed';
      case TaskStatus.archived:
        return 'archived';
      case TaskStatus.todo:
        return 'todo';
    }
  }
}

enum TaskType {
  deepWork,
  shallowWork,
  study,
  creative,
  admin,
  physical,
  meeting,
  personal;

  static TaskType fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'deep_work':
      case 'deepwork':
        return TaskType.deepWork;
      case 'shallow_work':
      case 'shallowwork':
        return TaskType.shallowWork;
      case 'study':
        return TaskType.study;
      case 'creative':
        return TaskType.creative;
      case 'admin':
        return TaskType.admin;
      case 'physical':
        return TaskType.physical;
      case 'meeting':
        return TaskType.meeting;
      case 'personal':
        return TaskType.personal;
      default:
        return TaskType.deepWork;
    }
  }

  String get value {
    switch (this) {
      case TaskType.deepWork:
        return 'deep_work';
      case TaskType.shallowWork:
        return 'shallow_work';
      case TaskType.study:
        return 'study';
      case TaskType.creative:
        return 'creative';
      case TaskType.admin:
        return 'admin';
      case TaskType.physical:
        return 'physical';
      case TaskType.meeting:
        return 'meeting';
      case TaskType.personal:
        return 'personal';
    }
  }

  String get label {
    switch (this) {
      case TaskType.deepWork:
        return 'Deep Work';
      case TaskType.shallowWork:
        return 'Shallow Work';
      case TaskType.study:
        return 'Study';
      case TaskType.creative:
        return 'Creative';
      case TaskType.admin:
        return 'Admin';
      case TaskType.physical:
        return 'Physical';
      case TaskType.meeting:
        return 'Meeting';
      case TaskType.personal:
        return 'Personal';
    }
  }
}

enum TaskPriority {
  low,
  medium,
  high,
  urgent;

  static TaskPriority fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'urgent':
        return TaskPriority.urgent;
      case 'medium':
      default:
        return TaskPriority.medium;
    }
  }

  String get value {
    switch (this) {
      case TaskPriority.low:
        return 'low';
      case TaskPriority.high:
        return 'high';
      case TaskPriority.urgent:
        return 'urgent';
      case TaskPriority.medium:
        return 'medium';
    }
  }
}

enum TaskSource {
  manual,
  aiParsed,
  calendar,
  imported;

  static TaskSource fromString(String? val) {
    switch (val?.toLowerCase()) {
      case 'ai_parsed':
      case 'aiparsed':
        return TaskSource.aiParsed;
      case 'calendar':
        return TaskSource.calendar;
      case 'imported':
        return TaskSource.imported;
      case 'manual':
      default:
        return TaskSource.manual;
    }
  }

  String get value {
    switch (this) {
      case TaskSource.aiParsed:
        return 'ai_parsed';
      case TaskSource.calendar:
        return 'calendar';
      case TaskSource.imported:
        return 'imported';
      case TaskSource.manual:
        return 'manual';
    }
  }
}

/// Task Data Model
/// Incorporates Difficulty, Duration, Deadline, Category, and Real Temporal Bounds.
class TaskItem {
  final String id;
  final String title;
  final String? description;
  final int durationMinutes;
  final TaskDifficulty difficulty;
  final String deadline; // e.g. "Due Tomorrow", "Friday", "Today"
  final String category; // "College", "Work", "Personal", "Fitness", "Study"
  final bool isCompleted;
  final String? scheduledTime; // e.g. "9:30 AM"
  final bool isPriority;
  final TaskType taskType;
  final TaskPriority priority;
  final TaskStatus status;
  final TaskSource source;
  final DateTime? deadlineAt;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? confidence;
  final List<String> missingFields;
  final List<String> ambiguities;
  final String? prioritySource; // 'explicit', 'inferred', 'unspecified'
  final String? schedulingExplanation;
  final String? recommendedSlotDisplay;
  final Map<String, dynamic>? schedulingReasons;

  bool get isPriorityExplicit => prioritySource == 'explicit';
  bool get isPriorityInferred => prioritySource == 'inferred' || ambiguities.contains('inferred_priority');
  bool get isPriorityUnspecified =>
      prioritySource == 'unspecified' ||
      ambiguities.contains('priority_unspecified') ||
      (!isPriorityExplicit && !isPriorityInferred);

  String get type => taskType == TaskType.deepWork ? 'deep_work' : taskType.name;
  String? get priorityValue => isPriorityUnspecified ? null : priority.name;

  const TaskItem({
    required this.id,
    required this.title,
    this.description,
    required this.durationMinutes,
    required this.difficulty,
    required this.deadline,
    required this.category,
    this.isCompleted = false,
    this.scheduledTime,
    this.isPriority = false,
    this.taskType = TaskType.deepWork,
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.todo,
    this.source = TaskSource.manual,
    this.deadlineAt,
    this.scheduledStart,
    this.scheduledEnd,
    this.startedAt,
    this.completedAt,
    this.confidence,
    this.missingFields = const [],
    this.ambiguities = const [],
    this.prioritySource,
    this.schedulingExplanation,
    this.recommendedSlotDisplay,
    this.schedulingReasons,
  });

  TaskItem copyWith({
    String? id,
    String? title,
    String? description,
    int? durationMinutes,
    TaskDifficulty? difficulty,
    String? deadline,
    String? category,
    bool? isCompleted,
    String? scheduledTime,
    bool? isPriority,
    TaskType? taskType,
    TaskPriority? priority,
    TaskStatus? status,
    TaskSource? source,
    DateTime? deadlineAt,
    DateTime? scheduledStart,
    DateTime? scheduledEnd,
    DateTime? startedAt,
    DateTime? completedAt,
    double? confidence,
    List<String>? missingFields,
    List<String>? ambiguities,
    String? prioritySource,
    String? schedulingExplanation,
    String? recommendedSlotDisplay,
    Map<String, dynamic>? schedulingReasons,
  }) {
    return TaskItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      difficulty: difficulty ?? this.difficulty,
      deadline: deadline ?? this.deadline,
      category: category ?? this.category,
      isCompleted: isCompleted ?? this.isCompleted,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      isPriority: isPriority ?? this.isPriority,
      taskType: taskType ?? this.taskType,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      source: source ?? this.source,
      deadlineAt: deadlineAt ?? this.deadlineAt,
      scheduledStart: scheduledStart ?? this.scheduledStart,
      scheduledEnd: scheduledEnd ?? this.scheduledEnd,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      confidence: confidence ?? this.confidence,
      missingFields: missingFields ?? this.missingFields,
      ambiguities: ambiguities ?? this.ambiguities,
      prioritySource: prioritySource ?? this.prioritySource,
      schedulingExplanation: schedulingExplanation ?? this.schedulingExplanation,
      recommendedSlotDisplay: recommendedSlotDisplay ?? this.recommendedSlotDisplay,
      schedulingReasons: schedulingReasons ?? this.schedulingReasons,
    );
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    TaskDifficulty diff = TaskDifficulty.medium;
    final diffStr = (json['difficulty'] as String?)?.toLowerCase();
    if (diffStr == 'high' || diffStr == 'deep work' || diffStr == 'deep_work') {
      diff = TaskDifficulty.high;
    } else if (diffStr == 'light' || diffStr == 'admin') {
      diff = TaskDifficulty.light;
    } else if (diffStr == 'physical' || diffStr == 'health') {
      diff = TaskDifficulty.physical;
    }

    final parsedStatus = TaskStatus.fromString(json['status'] as String?);
    final isDone = (json['is_completed'] as bool?) ?? (parsedStatus == TaskStatus.completed);

    final parsedPriority = TaskPriority.fromString(json['priority'] as String?);
    final isHighPri = (json['is_priority'] as bool?) ??
        (parsedPriority == TaskPriority.high || parsedPriority == TaskPriority.urgent);

    DateTime? deadlineDate;
    if (json['deadline_at'] != null) {
      deadlineDate = DateTime.tryParse(json['deadline_at'].toString());
    }

    DateTime? schedStart;
    if (json['scheduled_start'] != null) {
      schedStart = DateTime.tryParse(json['scheduled_start'].toString());
    }

    DateTime? schedEnd;
    if (json['scheduled_end'] != null) {
      schedEnd = DateTime.tryParse(json['scheduled_end'].toString());
    }

    DateTime? started;
    if (json['started_at'] != null) {
      started = DateTime.tryParse(json['started_at'].toString());
    }

    DateTime? completed;
    if (json['completed_at'] != null) {
      completed = DateTime.tryParse(json['completed_at'].toString());
    }

    // Determine human-readable deadline label
    String deadlineStr = json['deadline'] as String? ?? '';
    if (deadlineStr.isEmpty && deadlineDate != null) {
      final now = DateTime.now();
      final diffDays = deadlineDate.difference(now).inDays;
      if (diffDays == 0) {
        deadlineStr = 'Due Today';
      } else if (diffDays == 1) {
        deadlineStr = 'Due Tomorrow';
      } else {
        deadlineStr = DateFormat('EEE, MMM d').format(deadlineDate.toLocal());
      }
    } else if (deadlineStr.isEmpty) {
      deadlineStr = 'Today';
    }

    // Determine scheduledTime label if present
    String? schedTimeStr = json['scheduled_time'] as String?;
    if (schedTimeStr == null && schedStart != null) {
      schedTimeStr = DateFormat('h:mm a').format(schedStart.toLocal());
    }

    return TaskItem(
      id: json['id'] as String? ?? 'task-${DateTime.now().millisecondsSinceEpoch}',
      title: json['title'] as String? ?? 'Untitled Task',
      description: json['description'] as String?,
      durationMinutes: (json['estimated_minutes'] ?? json['duration_minutes'] as num?)?.toInt() ?? 45,
      difficulty: diff,
      deadline: deadlineStr,
      category: json['category'] as String? ?? 'General',
      isCompleted: isDone,
      scheduledTime: schedTimeStr,
      isPriority: isHighPri,
      taskType: TaskType.fromString(json['task_type'] as String?),
      priority: parsedPriority,
      status: isDone ? TaskStatus.completed : parsedStatus,
      source: TaskSource.fromString(json['source'] as String?),
      deadlineAt: deadlineDate,
      scheduledStart: schedStart,
      scheduledEnd: schedEnd,
      startedAt: started,
      completedAt: completed,
      confidence: (json['confidence'] as num?)?.toDouble(),
      missingFields: (json['missing_fields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      ambiguities: (json['ambiguities'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      prioritySource: json['priority_source'] as String?,
      schedulingExplanation: json['scheduling_explanation'] as String?,
      recommendedSlotDisplay: json['recommended_slot_display'] as String?,
      schedulingReasons: json['scheduling_reasons'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'duration_minutes': durationMinutes,
        'estimated_minutes': durationMinutes,
        'difficulty': difficulty.name,
        'deadline': deadline,
        'category': category,
        'is_completed': isCompleted,
        'scheduled_time': scheduledTime,
        'is_priority': isPriority,
        'task_type': taskType.value,
        'priority': priority.value,
        'status': status.value,
        'source': source.value,
        'deadline_at': deadlineAt?.toUtc().toIso8601String(),
        'scheduled_start': scheduledStart?.toUtc().toIso8601String(),
        'scheduled_end': scheduledEnd?.toUtc().toIso8601String(),
        'started_at': startedAt?.toUtc().toIso8601String(),
        'completed_at': completedAt?.toUtc().toIso8601String(),
        if (confidence != null) 'confidence': confidence,
        if (missingFields.isNotEmpty) 'missing_fields': missingFields,
        if (ambiguities.isNotEmpty) 'ambiguities': ambiguities,
        if (prioritySource != null) 'priority_source': prioritySource,
        if (schedulingExplanation != null) 'scheduling_explanation': schedulingExplanation,
        if (recommendedSlotDisplay != null) 'recommended_slot_display': recommendedSlotDisplay,
        if (schedulingReasons != null) 'scheduling_reasons': schedulingReasons,
      };

  String get energyRequired {
    if (difficulty == TaskDifficulty.high || taskType == TaskType.deepWork) {
      return 'High';
    } else if (difficulty == TaskDifficulty.medium || taskType == TaskType.study || taskType == TaskType.creative) {
      return 'Medium';
    }
    return 'Low';
  }

  String get importanceLabel {
    switch (priority) {
      case TaskPriority.urgent:
      case TaskPriority.high:
        return 'High';
      case TaskPriority.medium:
        return 'Medium';
      case TaskPriority.low:
        return 'Low';
    }
  }

  int get difficultyScore {
    switch (difficulty) {
      case TaskDifficulty.high:
        return 4;
      case TaskDifficulty.medium:
        return 3;
      case TaskDifficulty.light:
        return 1;
      case TaskDifficulty.physical:
        return 2;
    }
  }
}
