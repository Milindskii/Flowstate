import '../models/feedback_log.dart';
import 'api_service.dart';

/// Service for logging post-session reflections and focus feedback
class FeedbackService {
  final ApiService _api;

  FeedbackService({required ApiService api}) : _api = api;

  Future<void> submitFeedback(FeedbackLog log) async {
    await _api.post('/api/v1/tasks/${log.taskId}/feedback', body: {
      'completed_at': log.completedAt.toUtc().toIso8601String(),
      'actual_minutes': log.actualMinutes,
      'perceived_focus_score': log.perceivedFocusScore,
      'energy_feeling': log.energyFeeling,
      'notes': log.notes,
    });
  }
}
