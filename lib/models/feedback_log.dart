/// Feedback & Performance Data Model
/// Used by the Personal Learning Engine to adapt future readiness and scheduling.
class FeedbackLog {
  final String taskId;
  final DateTime completedAt;
  final int actualMinutes;
  final int perceivedFocusScore; // 1 to 5 stars
  final String energyFeeling; // "Energized", "Steady", "Drained"
  final String? notes;

  const FeedbackLog({
    required this.taskId,
    required this.completedAt,
    required this.actualMinutes,
    required this.perceivedFocusScore,
    required this.energyFeeling,
    this.notes,
  });
}
