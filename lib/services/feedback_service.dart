import '../models/feedback_log.dart';
import 'api_service.dart';

/// Service for logging post-session reflections and focus feedback
class FeedbackService {
  final ApiService _api;

  FeedbackService({required ApiService api}) : _api = api;

  Future<void> submitFeedback(FeedbackLog log) async {
    int energyNum = log.energyScore ?? 3;
    if (log.energyScore == null) {
      if (log.energyFeeling.toLowerCase().contains('energ')) {
        energyNum = 5;
      } else if (log.energyFeeling.toLowerCase().contains('drain')) {
        energyNum = 2;
      }
    }

    await _api.post('/api/v1/tasks/${log.taskId}/feedback', body: {
      'actual_minutes': log.actualMinutes,
      'focus_score': log.perceivedFocusScore,
      'energy_score': energyNum,
      'difficulty_score': log.difficultyScore,
      if (log.distractionScore != null) 'distraction_score': log.distractionScore,
      if (log.notes != null && log.notes!.isNotEmpty) 'notes': log.notes,
    });
  }
}
