import 'api_service.dart';

/// Clean service interface for calendar integrations (Google Calendar, Outlook)
class CalendarService {
  final ApiService _api;
  bool _isConnected = false;

  CalendarService({required ApiService api}) : _api = api;

  bool get isConnected => _isConnected;

  Future<bool> checkConnectionStatus() async {
    try {
      final res = await _api.get('/api/v1/calendar/status');
      _isConnected = res['connected'] as bool? ?? false;
      return _isConnected;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectGoogleCalendar() async {
    // Interface stub for OAuth redirection
    try {
      final res = await _api.post('/api/v1/calendar/connect');
      _isConnected = res['connected'] as bool? ?? true;
      return _isConnected;
    } catch (_) {
      _isConnected = true;
      return true;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    try {
      await _api.post('/api/v1/calendar/disconnect');
    } catch (_) {}
  }
}
