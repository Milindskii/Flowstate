import '../models/task_item.dart';
import 'api_service.dart';

/// Task Management API Client
class TaskService {
  final ApiService _api;

  TaskService({required ApiService api}) : _api = api;

  /// Retrieve user tasks with pagination and optional status filter
  Future<List<TaskItem>> getTasks({
    int limit = 50,
    int offset = 0,
    String? status,
  }) async {
    final queryParams = <String, String>{
      'limit': limit.toString(),
      'offset': offset.toString(),
    };
    if (status != null && status.isNotEmpty) {
      queryParams['status'] = status;
    }

    final res = await _api.get('/api/v1/tasks', queryParams: queryParams);
    if (res is List) {
      return res.map((item) => TaskItem.fromJson(item as Map<String, dynamic>)).toList();
    } else if (res is Map<String, dynamic> && res['items'] is List) {
      return (res['items'] as List)
          .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Retrieve tasks specifically scheduled or due today in user's timezone
  Future<List<TaskItem>> getTodayTasks() async {
    final res = await _api.get('/api/v1/tasks/today');
    if (res is List) {
      return res.map((item) => TaskItem.fromJson(item as Map<String, dynamic>)).toList();
    } else if (res is Map<String, dynamic> && res['items'] is List) {
      return (res['items'] as List)
          .map((item) => TaskItem.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Get single task details by ID
  Future<TaskItem> getTask(String taskId) async {
    final res = await _api.get('/api/v1/tasks/$taskId');
    return TaskItem.fromJson(res as Map<String, dynamic>);
  }

  /// Create a new task
  Future<TaskItem> createTask(TaskItem task) async {
    final res = await _api.post('/api/v1/tasks', body: task.toJson());
    return TaskItem.fromJson(res as Map<String, dynamic>);
  }

  /// Update an existing task
  Future<TaskItem> updateTask(TaskItem task) async {
    try {
      final res = await _api.put('/api/v1/tasks/${task.id}', body: task.toJson());
      return TaskItem.fromJson(res as Map<String, dynamic>);
    } catch (_) {
      return task;
    }
  }

  /// Partially update task attributes
  Future<TaskItem> patchTask(String taskId, Map<String, dynamic> fields) async {
    final res = await _api.patch('/api/v1/tasks/$taskId', body: fields);
    return TaskItem.fromJson(res as Map<String, dynamic>);
  }

  /// Mark task as in-progress
  Future<void> startTask(String taskId) async {
    await _api.post('/api/v1/tasks/$taskId/start');
  }

  /// Mark task as completed with optional reflection
  Future<void> completeTask(
    String taskId, {
    int? actualMinutes,
    DateTime? completedAt,
    int? perceivedFocusScore,
    String? energyFeeling,
  }) async {
    await _api.post('/api/v1/tasks/$taskId/complete', body: {
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
      if (completedAt != null) 'completed_at': completedAt.toUtc().toIso8601String(),
    });

    if (perceivedFocusScore != null || energyFeeling != null) {
      await submitFeedback(
        taskId,
        actualMinutes: actualMinutes,
        focusScore: perceivedFocusScore,
        energyScore: energyFeeling != null && energyFeeling.contains('Energ') ? 5 : 3,
      ).catchError((_) {});
    }
  }

  /// Submit performance reflection / feedback for a completed task
  Future<void> submitFeedback(
    String taskId, {
    int? actualMinutes,
    int? focusScore,
    int? energyScore,
    int? difficultyScore,
    int? distractionScore,
    String? notes,
  }) async {
    await _api.post('/api/v1/tasks/$taskId/feedback', body: {
      if (actualMinutes != null) 'actual_minutes': actualMinutes,
      'focus_score': focusScore ?? 3,
      'energy_score': energyScore ?? 3,
      'difficulty_score': difficultyScore ?? 3,
      if (distractionScore != null) 'distraction_score': distractionScore,
      if (notes != null) 'notes': notes,
    });
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    await _api.delete('/api/v1/tasks/$taskId');
  }

  /// Natural language task parser candidate generation ("What's on your plate?")
  /// Returns parsed task candidates requiring user confirmation before saving
  Future<List<TaskItem>> parseTasks(String rawText, {String? timezone}) async {
    final res = await _api.post('/api/v1/tasks/parse', body: {
      'text': rawText,
      if (timezone != null) 'timezone': timezone,
    });

    if (res is List) {
      return res.map((item) => TaskItem.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
