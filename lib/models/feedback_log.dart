/// Feedback & Performance Data Model
/// Used by the Personal Learning Engine and backend TaskPerformance records
class FeedbackLog {
  final String? id;
  final String? userId;
  final String taskId;
  final DateTime completedAt;
  final int actualMinutes;
  final int perceivedFocusScore; // 1 to 5 stars
  final String energyFeeling; // "Energized", "Steady", "Drained"
  final int? energyScore; // 1 to 5
  final int difficultyScore; // 1 to 5
  final int? distractionScore; // 1 to 5
  final String? notes;

  const FeedbackLog({
    this.id,
    this.userId,
    required this.taskId,
    required this.completedAt,
    required this.actualMinutes,
    required this.perceivedFocusScore,
    required this.energyFeeling,
    this.energyScore,
    this.difficultyScore = 3,
    this.distractionScore,
    this.notes,
  });

  int get focusScore => perceivedFocusScore;

  factory FeedbackLog.fromJson(Map<String, dynamic> json) {
    final focus = (json['focus_score'] ?? json['perceived_focus_score'] as num?)?.toInt() ?? 3;
    final energy = (json['energy_score'] as num?)?.toInt() ?? 3;
    
    String energyStr = json['energy_feeling'] as String? ?? 'Steady';
    if (json['energy_feeling'] == null) {
      if (energy >= 4) {
        energyStr = 'Energized';
      } else if (energy <= 2) {
        energyStr = 'Drained';
      } else {
        energyStr = 'Steady';
      }
    }

    return FeedbackLog(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      taskId: json['task_id'] as String? ?? '',
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      actualMinutes: (json['actual_minutes'] as num?)?.toInt() ?? 0,
      perceivedFocusScore: focus,
      energyFeeling: energyStr,
      energyScore: energy,
      difficultyScore: (json['difficulty_score'] as num?)?.toInt() ?? 3,
      distractionScore: (json['distraction_score'] as num?)?.toInt(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'task_id': taskId,
        'completed_at': completedAt.toUtc().toIso8601String(),
        'actual_minutes': actualMinutes,
        'focus_score': perceivedFocusScore,
        'energy_score': energyScore ?? (energyFeeling.contains('Energ') ? 5 : (energyFeeling.contains('Drain') ? 2 : 3)),
        'difficulty_score': difficultyScore,
        if (distractionScore != null) 'distraction_score': distractionScore,
        if (notes != null) 'notes': notes,
      };
}
