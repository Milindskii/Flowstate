import '../models/task_item.dart';
import 'api_service.dart';

/// Task Management API Client
class TaskService {
  final ApiService _api;

  TaskService({required ApiService api}) : _api = api;

  Future<List<TaskItem>> getTasks() async {
    final res = await _api.get('/api/v1/tasks');
    if (res is List) {
      return res.map((item) => TaskItem.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<TaskItem>> getTodayTasks() async {
    final res = await _api.get('/api/v1/tasks/today');
    if (res is List) {
      return res.map((item) => TaskItem.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<TaskItem> createTask(TaskItem task) async {
    final res = await _api.post('/api/v1/tasks', body: task.toJson());
    return TaskItem.fromJson(res as Map<String, dynamic>);
  }

  Future<void> startTask(String taskId) async {
    await _api.post('/api/v1/tasks/$taskId/start');
  }

  Future<void> completeTask(
    String taskId, {
    int? actualMinutes,
    int? perceivedFocusScore,
    String? energyFeeling,
  }) async {
    await _api.post('/api/v1/tasks/$taskId/complete', body: {
      'actual_minutes': actualMinutes,
      'perceived_focus_score': perceivedFocusScore,
      'energy_feeling': energyFeeling,
    });
  }

  Future<void> deleteTask(String taskId) async {
    await _api.delete('/api/v1/tasks/$taskId');
  }
}
