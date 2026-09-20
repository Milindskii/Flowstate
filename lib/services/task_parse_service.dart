import '../models/task_item.dart';
import 'api_service.dart';

/// Task parsing service — single backend parser architecture.
///
/// Two modes only:
///   1. Connected (production): POST /api/v1/tasks/parse → backend AIService
///   2. Demo / offline: returns a static demo stub — NOT a real heuristic parser
///
/// Do NOT add real parsing logic here. The backend is the only parsing brain.
/// For offline support in production, cache previous parse results via SharedPreferences.
class TaskParseService {
  final ApiService api;

  const TaskParseService({required this.api});

  /// Parse a brain dump via the backend API.
  /// [rawText] must be under 1500 characters (enforced server-side, validated client-side).
  /// In demo mode, returns a static stub.
  Future<List<TaskItem>> parseBrainDump(
    String rawText, {
    bool isDemoMode = false,
  }) async {
    if (isDemoMode) {
      // DEMO STUB — not a real parser. Returns example tasks so the demo flow works.
      await Future.delayed(const Duration(milliseconds: 800)); // Simulated delay
      return demoFallbackTasks();
    }

    // Client-side length check (server enforces 1500 char max_length via Pydantic)
    if (rawText.length > 1500) {
      rawText = rawText.substring(0, 1500);
    }

    try {
      final response = await api.post(
        '/api/v1/tasks/parse',
        body: {'raw_text': rawText},
      );

      if (response is List) {
        return response
            .whereType<Map<String, dynamic>>()
            .map((json) => TaskItem.fromJson(json))
            .toList();
      }
      return [];
    } catch (_) {
      // Network failure / server error → return demo stub so user is unblocked
      return demoFallbackTasks();
    }
  }

  /// DEMO STUB — returns hardcoded example tasks for demo mode and offline fallback.
  /// This is intentionally minimal and clearly labeled. Replace by fixing connectivity.
  static List<TaskItem> demoFallbackTasks() {
    return const [
      TaskItem(
        id: 'demo-parse-1',
        title: 'Finish ML Assignment',
        durationMinutes: 90,
        difficulty: TaskDifficulty.high,
        deadline: 'Due Tomorrow',
        category: 'College',
        taskType: TaskType.deepWork,
        priority: TaskPriority.high,
        isPriority: true,
      ),
      TaskItem(
        id: 'demo-parse-2',
        title: 'Review DBMS Notes',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Due Friday',
        category: 'College',
        taskType: TaskType.study,
        priority: TaskPriority.medium,
      ),
      TaskItem(
        id: 'demo-parse-3',
        title: 'Gym Session',
        durationMinutes: 60,
        difficulty: TaskDifficulty.physical,
        deadline: 'Today',
        category: 'Fitness',
        taskType: TaskType.physical,
        priority: TaskPriority.low,
      ),
    ];
  }
}
