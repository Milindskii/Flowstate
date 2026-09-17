import 'api_service.dart';

/// Clean interface for future Android Health Connect & iOS HealthKit sync
/// Strictly for sleep duration, sleep consistency, and general activity load.
/// NEVER calculates or reads cortisol or clinical measurements.
class HealthService {
  final ApiService _api;
  bool _isConnected = false;

  HealthService({required ApiService api}) : _api = api;

  bool get isConnected => _isConnected;

  Future<bool> checkConnectionStatus() async {
    try {
      final res = await _api.get('/api/v1/health/status');
      _isConnected = res['connected'] as bool? ?? false;
      return _isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<bool> syncHealthData() async {
    // Interface stub for Health Connect sync (sleep & steps only)
    try {
      final res = await _api.post('/api/v1/health/sync');
      return res['success'] as bool? ?? true;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
  }
}
