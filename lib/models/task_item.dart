import 'package:intl/intl.dart';
import '../services/flow_clock.dart';

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

  static TaskPriority? tryFromString(String? val) {
    if (val == null || val.isEmpty || val == 'unspecified') return null;
    switch (val.toLowerCase()) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      case 'urgent':
        return TaskPriority.urgent;
      case 'medium':
        return TaskPriority.medium;
      default:
        return null;
    }
  }

  static TaskPriority fromString(String? val) {
    return tryFromString(val) ?? TaskPriority.medium;
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
  final TaskPriority? priority;
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
  final bool autoReschedule; // Whether this task may move when Flowstate replans the day
  /// True ONLY when the user (or an external calendar) fixed this start time. Scheduler-chosen
  /// times are never locked and may be moved by Replan.
  final bool timeLocked;
  /// A fixed block (always also timeLocked): not work, never remaining/current/missed/completable.
  final bool isCommitment;
  /// "Intended for this day, time not chosen" (local calendar date). Replaces misusing deadlineAt.
  final DateTime? plannedDate;
  /// When the task was first entered (server created_at). Orders unscheduled tasks: first entered on top.
  final DateTime? createdAt;
  // Build My Day contract (spec 2026-10-03). *Source: 'explicit' (user-stated) | 'inferred'.
  final String? candidateId;
  final String? routineOverrideId; // preview only: replaces that routine's occurrence on routineOverrideDate
  final String? routineOverrideDate;
  final String? routineId; // set on tasks generated by a routine
  final String? durationSource;
  final String? focusLevel; // 'low' | 'medium' | 'high'
  final String? focusSource;
  final String? deadlineKind; // 'hard' (never exceeded) | 'soft' (preferred target)
  final List<String> dependsOn; // candidate ids (preview) / task ids (persisted) that must finish first
  // Only user-stated preferred times; never inferred.
  final DateTime? preferredStart;
  final DateTime? preferredWindowStart;
  final DateTime? preferredWindowEnd;
  final String? unscheduledReason; // preview only: why the planner could not place it

  TaskPriority get effectivePriority => priority ?? TaskPriority.medium;

  bool get isPriorityExplicit => prioritySource == 'explicit';
  bool get isPriorityInferred => prioritySource == 'inferred' || ambiguities.contains('inferred_priority');
  bool get isPriorityUnspecified =>
      prioritySource == 'unspecified' ||
      ambiguities.contains('priority_unspecified') ||
      (!isPriorityExplicit && !isPriorityInferred);

  bool get isDurationExplicit => !missingFields.contains('duration');
  String get type => taskType == TaskType.deepWork ? 'deep_work' : taskType.name;
  String? get priorityValue => isPriorityUnspecified ? null : (priority?.name ?? 'medium');

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
    this.priority,
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
    this.autoReschedule = true,
    this.timeLocked = false,
    this.isCommitment = false,
    this.plannedDate,
    this.createdAt,
    this.candidateId,
    this.routineOverrideId,
    this.routineOverrideDate,
    this.routineId,
    this.durationSource,
    this.focusLevel,
    this.focusSource,
    this.deadlineKind,
    this.dependsOn = const [],
    this.preferredStart,
    this.preferredWindowStart,
    this.preferredWindowEnd,
    this.unscheduledReason,
  });

  /// The day this task belongs to (local calendar date): its planned day, else the day of its slot. Never the day it
  /// was completed or created. The same ownership the server uses (planned date first, the slot only for older rows),
  /// so Calendar, Today, History and Insights agree on which day a task is on. Null when it has neither.
  DateTime? get owningDate {
    final planned = plannedDate;
    if (planned != null) return DateTime(planned.year, planned.month, planned.day);
    final slot = scheduledStart?.toLocal();
    if (slot != null) return DateTime(slot.year, slot.month, slot.day);
    return null;
  }

  /// The deadline as it reads RIGHT NOW. `deadline` is text written when the task was parsed or moved ("Due Tomorrow",
  /// "Tomorrow"); a relative word goes stale at midnight, so it is re-derived from the dates the task still holds.
  /// Anything the user wrote ("Friday evening") or a plain date is returned as is.
  String get deadlineLabel {
    final lower = deadline.toLowerCase();
    final due = lower.startsWith('due ');
    final word = due ? lower.substring(4) : lower;
    if (word != 'today' && word != 'tomorrow') return deadline;
    final anchor = due ? (deadlineAt ?? plannedDate) : (plannedDate ?? deadlineAt);
    if (anchor == null) return deadline;
    return relativeDayWord(anchor, FlowClock.currentTime(), duePrefix: due);
  }

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
    bool clearScheduledTime = false,
    bool? isPriority,
    TaskType? taskType,
    TaskPriority? priority,
    bool clearPriority = false,
    TaskStatus? status,
    TaskSource? source,
    DateTime? deadlineAt,
    bool clearDeadlineAt = false,
    DateTime? scheduledStart,
    bool clearScheduledStart = false,
    DateTime? scheduledEnd,
    bool clearScheduledEnd = false,
    DateTime? startedAt,
    DateTime? completedAt,
    double? confidence,
    List<String>? missingFields,
    List<String>? ambiguities,
    String? prioritySource,
    String? schedulingExplanation,
    String? recommendedSlotDisplay,
    Map<String, dynamic>? schedulingReasons,
    bool? autoReschedule,
    bool? timeLocked,
    bool? isCommitment,
    DateTime? plannedDate,
    bool clearPlannedDate = false,
    DateTime? createdAt,
    String? candidateId,
    String? routineOverrideId,
    String? routineOverrideDate,
    String? routineId,
    String? durationSource,
    String? focusLevel,
    String? focusSource,
    String? deadlineKind,
    List<String>? dependsOn,
    DateTime? preferredStart,
    DateTime? preferredWindowStart,
    DateTime? preferredWindowEnd,
    String? unscheduledReason,
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
      scheduledTime: clearScheduledTime ? null : (scheduledTime ?? this.scheduledTime),
      isPriority: isPriority ?? this.isPriority,
      taskType: taskType ?? this.taskType,
      priority: clearPriority ? null : (priority ?? this.priority),
      status: status ?? this.status,
      source: source ?? this.source,
      deadlineAt: clearDeadlineAt ? null : (deadlineAt ?? this.deadlineAt),
      scheduledStart: clearScheduledStart ? null : (scheduledStart ?? this.scheduledStart),
      scheduledEnd: clearScheduledEnd ? null : (scheduledEnd ?? this.scheduledEnd),
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      confidence: confidence ?? this.confidence,
      missingFields: missingFields ?? this.missingFields,
      ambiguities: ambiguities ?? this.ambiguities,
      prioritySource: prioritySource ?? this.prioritySource,
      schedulingExplanation: schedulingExplanation ?? this.schedulingExplanation,
      recommendedSlotDisplay: recommendedSlotDisplay ?? this.recommendedSlotDisplay,
      schedulingReasons: schedulingReasons ?? this.schedulingReasons,
      autoReschedule: autoReschedule ?? this.autoReschedule,
      timeLocked: timeLocked ?? this.timeLocked,
      isCommitment: isCommitment ?? this.isCommitment,
      plannedDate: clearPlannedDate ? null : (plannedDate ?? this.plannedDate),
      createdAt: createdAt ?? this.createdAt,
      candidateId: candidateId ?? this.candidateId,
      routineOverrideId: routineOverrideId ?? this.routineOverrideId,
      routineOverrideDate: routineOverrideDate ?? this.routineOverrideDate,
      routineId: routineId ?? this.routineId,
      durationSource: durationSource ?? this.durationSource,
      focusLevel: focusLevel ?? this.focusLevel,
      focusSource: focusSource ?? this.focusSource,
      deadlineKind: deadlineKind ?? this.deadlineKind,
      dependsOn: dependsOn ?? this.dependsOn,
      preferredStart: preferredStart ?? this.preferredStart,
      preferredWindowStart: preferredWindowStart ?? this.preferredWindowStart,
      preferredWindowEnd: preferredWindowEnd ?? this.preferredWindowEnd,
      unscheduledReason: unscheduledReason ?? this.unscheduledReason,
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

    final parsedPriority = (json['priority_source'] == 'unspecified' || json['priority'] == null)
        ? null
        : TaskPriority.tryFromString(json['priority'] as String?);
    final isHighPri = (json['is_priority'] as bool?) ??
        (parsedPriority == TaskPriority.high || parsedPriority == TaskPriority.urgent);

    DateTime? deadlineDate;
    if (json['deadline_at'] != null) {
      deadlineDate = DateTime.tryParse(json['deadline_at'].toString())?.toLocal();
    }

    DateTime? schedStart;
    if (json['scheduled_start'] != null) {
      schedStart = DateTime.tryParse(json['scheduled_start'].toString())?.toLocal();
    }

    DateTime? schedEnd;
    if (json['scheduled_end'] != null) {
      schedEnd = DateTime.tryParse(json['scheduled_end'].toString())?.toLocal();
    }

    DateTime? started;
    if (json['started_at'] != null) {
      started = DateTime.tryParse(json['started_at'].toString())?.toLocal();
    }

    DateTime? completed;
    if (json['completed_at'] != null) {
      completed = DateTime.tryParse(json['completed_at'].toString())?.toLocal();
    }

    // Determine human-readable deadline label
    String deadlineStr = json['deadline'] as String? ?? '';
    if (deadlineStr.isEmpty && deadlineDate != null) {
      deadlineStr = relativeDayWord(deadlineDate, FlowClock.currentTime(), duePrefix: true);
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
      autoReschedule: (json['auto_reschedule'] as bool?) ?? true,
      timeLocked: (json['time_locked'] as bool?) ?? false,
      isCommitment: (json['is_commitment'] as bool?) ?? false,
      plannedDate: json['planned_date'] != null ? DateTime.tryParse(json['planned_date'].toString()) : null,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString())?.toLocal() : null,
      candidateId: json['candidate_id'] as String?,
      routineId: json['routine_id'] as String?,
      durationSource: json['duration_source'] as String?,
      focusLevel: json['focus_level'] as String?,
      focusSource: json['focus_source'] as String?,
      deadlineKind: json['deadline_kind'] as String?,
      dependsOn: (json['depends_on'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      preferredStart: _instant(json['preferred_start']),
      preferredWindowStart: _instant(json['preferred_window_start']),
      preferredWindowEnd: _instant(json['preferred_window_end']),
    );
  }

  static DateTime? _instant(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

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
        if (priority != null) 'priority': priority!.value,
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
        'auto_reschedule': autoReschedule,
        'time_locked': timeLocked,
        'is_commitment': isCommitment,
        'planned_date': plannedDate == null ? null : DateFormat('yyyy-MM-dd').format(plannedDate!),
        if (createdAt != null) 'created_at': createdAt!.toUtc().toIso8601String(),
      };

  bool get isActive => status == TaskStatus.inProgress;

  String get energyRequired {
    if (difficulty == TaskDifficulty.high || taskType == TaskType.deepWork) {
      return 'High';
    } else if (difficulty == TaskDifficulty.medium || taskType == TaskType.study || taskType == TaskType.creative) {
      return 'Medium';
    }
    return 'Low';
  }

  String get importanceLabel {
    if (isPriorityUnspecified || priority == null) {
      return 'Not specified';
    }
    switch (priority!) {
      case TaskPriority.urgent:
        return 'Urgent';
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

/// Task list order, derived only from persisted fields so it is identical after a reload:
/// 1. owning day (planned_date, else the slot's local day; undated last);
/// 2. scheduled tasks by start time, before unscheduled ones;
/// 3. unscheduled: an explicitly set priority first (urgent → low), otherwise first entered on top.
/// Never by completion time or response order, so completing a task keeps its place.
int compareTaskOrder(TaskItem a, TaskItem b) {
  DateTime? day(TaskItem t) {
    final d = t.plannedDate ?? t.scheduledStart?.toLocal();
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  int nullsLast(Comparable? x, Comparable? y) {
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  final byDay = nullsLast(day(a), day(b));
  if (byDay != 0) return byDay;
  final byStart = nullsLast(a.scheduledStart, b.scheduledStart);
  if (byStart != 0) return byStart;
  if (a.scheduledStart == null) {
    // unspecified priority ranks as medium; only an explicit choice moves a task up or down
    int rank(TaskItem t) => t.isPriorityExplicit ? t.effectivePriority.index - TaskPriority.medium.index : 0;
    final byPriority = rank(b).compareTo(rank(a));
    if (byPriority != 0) return byPriority;
  }
  final byCreated = nullsLast(a.createdAt, b.createdAt);
  return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
}


/// Calendar days from [now]'s date to [day]'s date (0 = same day, 1 = the next day). Whole days by date, never by
/// 24-hour spans: a deadline tomorrow at 09:00 is "tomorrow" at 20:00 tonight, and DST changes cannot shift it.
int calendarDaysBetween(DateTime now, DateTime day) {
  final a = DateTime.utc(now.year, now.month, now.day);
  final b = DateTime.utc(day.year, day.month, day.day);
  return b.difference(a).inDays;
}

/// "Today" / "Tomorrow" / "Mon, Oct 12" for [day] as seen from [now]; with [duePrefix]: "Due Today" ...
String relativeDayWord(DateTime day, DateTime now, {bool duePrefix = false}) {
  final local = day.toLocal();
  final diff = calendarDaysBetween(now, local);
  final word = diff == 0 ? 'Today' : (diff == 1 ? 'Tomorrow' : DateFormat('EEE, MMM d').format(local));
  return duePrefix ? 'Due $word' : word;
}
