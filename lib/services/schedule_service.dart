import '../models/schedule_item.dart';
import 'api_service.dart';

/// Service managing optimized schedule blocks
class ScheduleService {
  final ApiService _api;

  ScheduleService({required ApiService api}) : _api = api;

  Future<List<ScheduleItem>> getTodaySchedule() async {
    try {
      final res = await _api.get('/api/v1/schedule');
      if (res is List) {
        return res.map((item) => ScheduleItem.fromJson(item as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<List<ScheduleItem>> optimizeSchedule() async {
    final res = await _api.post('/api/v1/schedule/optimize');
    if (res is List) {
      return res.map((item) => ScheduleItem.fromJson(item as Map<String, dynamic>)).toList();
    }
    return [];
  }
}
