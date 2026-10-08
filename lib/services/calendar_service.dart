import '../models/calendar_models.dart';
import 'api_service.dart';
import 'timezone_service.dart';

/// Clean service interface for calendar integrations & date-specific schedules
class CalendarService {
  final ApiService _api;
  bool _isConnected = false;

  CalendarService({required ApiService api}) : _api = api;

  bool get isConnected => _isConnected;

  /// Fetches authoritative execution schedule for a specific date (YYYY-MM-DD)
  Future<DayScheduleResponse> getDaySchedule(String dateStr, {String? timezone}) async {
    final queryParams = <String, String>{'date': dateStr};
    // Same IANA zone as Build My Day and Replan (the server falls back to the stored preference if absent).
    timezone ??= await TimezoneService.localIanaName();
    if (timezone != null && timezone.isNotEmpty) {
      queryParams['timezone'] = timezone;
    }
    final res = await _api.get('/api/v1/calendar/day', queryParams: queryParams);
    if (res is Map<String, dynamic>) {
      return DayScheduleResponse.fromJson(res);
    }
    throw const ApiException('Invalid calendar day response format');
  }

  /// Generates a dry-run Replan proposal comparing before vs after schedules.
  /// Calls POST /api/v1/ai/replan (with fallback to /api/v1/calendar/replan).
  /// NEVER mutates the database.
  Future<ReplanResponse> replanDay({
    required String dateStr,
    required String message,
    DateTime? currentLocalTime,
    String? timezone,
    /// A structured new task ("Urgent work arrived"): sent as typed, never parsed from prose.
    Map<String, dynamic>? quickAdd,
    /// Stable per user message: a retry of the same message never costs a second Shield.
    String? idempotencyKey,
  }) async {
    final body = <String, dynamic>{
      if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      'selected_date': dateStr,
      'user_message': message,
      if (quickAdd != null) 'quick_add': quickAdd,
      if (currentLocalTime != null) 'current_local_time': currentLocalTime.toUtc().toIso8601String(),
      if (timezone != null && timezone.isNotEmpty) 'timezone': timezone,
    };

    dynamic res;
    try {
      res = await _api.post('/api/v1/ai/replan', body: body);
    } catch (e) {
      if (e is ApiException && e.statusCode != null && e.statusCode! < 500 && e.statusCode != 404) {
        rethrow;
      }
      // A timeout means the server may still be working on it: never send the same request twice.
      if (e is ApiException && e.isTimeout) rethrow;
      // Fallback to the alias only when /ai/replan is missing or failed outright
      res = await _api.post('/api/v1/calendar/replan', body: body);
    }

    if (res is Map<String, dynamic>) {
      return ReplanResponse.fromJson(res);
    }
    throw const ApiException('Invalid replan response format');
  }

  /// Atomically commits a confirmed PlanDiff to the database.
  /// Calls POST /api/v1/calendar/apply-replan.
  Future<ApplyReplanResponse> applyReplan(ApplyReplanRequest request) async {
    final res = await _api.post('/api/v1/calendar/apply-replan', body: request.toJson());
    if (res is Map<String, dynamic>) {
      return ApplyReplanResponse.fromJson(res);
    }
    throw const ApiException('Invalid apply replan response format');
  }

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
