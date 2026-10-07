/// What the user told Flowstate after finishing a task (the "How did that feel?" sheet).
///
/// Stored on this device and synced to `/tasks/{id}/feedback`. While a sync is outstanding (offline, server down)
/// [pendingSync] holds the exact payload to send — only values the user actually gave, never a made-up default —
/// and it is cleared once the server has it.
class TaskReflection {
  final String taskId;
  final String title;

  /// 1 = drained 😫, 2 = meh 😐, 3 = good 🙂, 4 = on fire 🔥.
  final int feeling;
  final int energy; // 1–5
  final int focus; // 1–5
  final int difficulty; // 1–5
  final int distraction; // 1–5 (1 = none)
  final DateTime completedAt;
  final int actualMinutes;
  final int? plannedMinutes;
  final DateTime? plannedStart;

  /// 'shorter' | 'about_right' | 'longer'
  final String? durationFeedback;
  final String? note;

  /// The feedback body still to be delivered to the server, or null when synced.
  final Map<String, dynamic>? pendingSync;

  const TaskReflection({
    required this.taskId,
    required this.title,
    required this.feeling,
    required this.energy,
    required this.focus,
    required this.difficulty,
    required this.distraction,
    required this.completedAt,
    required this.actualMinutes,
    this.plannedMinutes,
    this.plannedStart,
    this.durationFeedback,
    this.note,
    this.pendingSync,
  });

  TaskReflection markSynced() => TaskReflection(
        taskId: taskId,
        title: title,
        feeling: feeling,
        energy: energy,
        focus: focus,
        difficulty: difficulty,
        distraction: distraction,
        completedAt: completedAt,
        actualMinutes: actualMinutes,
        plannedMinutes: plannedMinutes,
        plannedStart: plannedStart,
        durationFeedback: durationFeedback,
        note: note,
      );

  static String feelingLabel(int feeling) {
    switch (feeling) {
      case 1:
        return 'Drained';
      case 2:
        return 'Okay';
      case 3:
        return 'Good';
      default:
        return 'On fire';
    }
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'title': title,
        'feeling': feeling,
        'energy': energy,
        'focus': focus,
        'difficulty': difficulty,
        'distraction': distraction,
        'completed_at': completedAt.toIso8601String(),
        'actual_minutes': actualMinutes,
        if (plannedMinutes != null) 'planned_minutes': plannedMinutes,
        if (plannedStart != null) 'planned_start': plannedStart!.toIso8601String(),
        if (durationFeedback != null) 'duration_feedback': durationFeedback,
        if (note != null) 'note': note,
        if (pendingSync != null) 'pending_sync': pendingSync,
      };

  factory TaskReflection.fromJson(Map<String, dynamic> json) => TaskReflection(
        taskId: json['task_id'] as String,
        title: json['title'] as String? ?? '',
        feeling: (json['feeling'] as num).toInt(),
        energy: (json['energy'] as num?)?.toInt() ?? 3,
        focus: (json['focus'] as num?)?.toInt() ?? 3,
        difficulty: (json['difficulty'] as num?)?.toInt() ?? 3,
        distraction: (json['distraction'] as num?)?.toInt() ?? 1,
        completedAt: DateTime.parse(json['completed_at'] as String),
        actualMinutes: (json['actual_minutes'] as num?)?.toInt() ?? 0,
        plannedMinutes: (json['planned_minutes'] as num?)?.toInt(),
        plannedStart: json['planned_start'] == null ? null : DateTime.parse(json['planned_start'] as String),
        durationFeedback: json['duration_feedback'] as String?,
        note: json['note'] as String?,
        pendingSync: (json['pending_sync'] as Map?)?.cast<String, dynamic>(),
      );
}
