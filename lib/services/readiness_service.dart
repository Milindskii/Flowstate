import '../models/readiness_model.dart';
import 'api_service.dart';

/// Service managing non-medical readiness scores and daily energy check-ins
class ReadinessService {
  final ApiService _api;

  ReadinessService({required ApiService api}) : _api = api;

  Future<ReadinessModel> getTodayReadiness() async {
    try {
      final res = await _api.get('/api/v1/readiness/today');
      if (res is Map<String, dynamic>) {
        return ReadinessModel.fromJson(res);
      }
      return ReadinessModel.uncalibrated();
    } catch (_) {
      return ReadinessModel.uncalibrated();
    }
  }

  Future<void> submitEnergyCheckin({
    required int energyScore, // 1 to 10
    required String notes,
  }) async {
    await _api.post('/api/v1/energy/checkin', body: {
      'energy_score': energyScore,
      'notes': notes,
      'recorded_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
