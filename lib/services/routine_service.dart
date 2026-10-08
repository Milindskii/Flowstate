import '../models/routine.dart';
import 'api_service.dart';
import 'timezone_service.dart';

/// Routines API: the backend owns recurrence, the 7-day horizon and history safety; this only calls it.
class RoutineService {
  final ApiService api;

  const RoutineService({required this.api});

  /// Saves the routine (after the user's explicit confirmation) and plans the next 7 days.
  /// The same [idempotencyKey] never creates it twice, so a double tap or retry is safe.
  Future<int> confirm(RoutineProposal proposal, {required String idempotencyKey, DateTime? now}) async {
    final tz = await TimezoneService.localIanaName();
    final res = await api.post(
      '/api/v1/routines',
      body: proposal.toCreateJson(idempotencyKey: idempotencyKey, timezone: tz, now: now),
    );
    if (res is Map<String, dynamic>) return (res['created_count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  /// Also brings the confirmed week up to date on the server (never past what the user confirmed).
  Future<List<Routine>> list() async {
    final tz = await TimezoneService.localIanaName();
    final res = await api.get('/api/v1/routines', queryParams: {if (tz != null) 'timezone': tz});
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().map(Routine.fromJson).toList();
    }
    return const [];
  }

  /// A weekly routine the user sets up by hand (Insights > Routines): plans this week's occurrences on the server.
  /// The same [idempotencyKey] never creates it twice. Never an AI call, never a Shield.
  Future<int> create({
    required String title,
    required List<int> weekdays,
    required String startHhmm,
    required int estimatedMinutes,
    required String idempotencyKey,
    String category = 'General',
    String taskType = 'personal',
  }) async {
    final tz = await TimezoneService.localIanaName();
    final everyDay = weekdays.length == 7;
    final res = await api.post('/api/v1/routines', body: {
      'title': title,
      'task_type': taskType,
      'category': category,
      'estimated_minutes': estimatedMinutes,
      'kind': 'fixed',
      'recurrence': everyDay ? 'daily' : 'weekly',
      if (!everyDay) 'weekdays': weekdays,
      'start_hhmm': startHhmm,
      'idempotency_key': idempotencyKey,
      if (tz != null) 'timezone': tz,
    });
    if (res is Map<String, dynamic>) return (res['created_count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  Future<void> update(String id,
      {String? startHhmm, int? estimatedMinutes, String? title, List<int>? weekdays}) async {
    final tz = await TimezoneService.localIanaName();
    await api.patch('/api/v1/routines/$id', body: {
      if (startHhmm != null) 'start_hhmm': startHhmm,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (title != null) 'title': title,
      if (weekdays != null) ...{
        'recurrence': weekdays.length == 7 ? 'daily' : 'weekly',
        if (weekdays.length != 7) 'weekdays': weekdays,
      },
      if (tz != null) 'timezone': tz,
    });
  }

  /// The answer to "Continue your routine next week?": [proceed] plans next week once (a retry plans nothing more);
  /// otherwise "Not now" keeps the routine without planning. Returns how many occurrences were planned. Free.
  Future<int> answerContinuation(Routine routine, {required bool proceed}) async {
    final end = routine.cycleEndParam;
    if (end == null) return 0;
    final tz = await TimezoneService.localIanaName();
    final res = await api.post('/api/v1/routines/${routine.id}/continuation', body: {
      'decision': proceed ? 'continue' : 'not_now',
      'cycle_end': end,
      if (tz != null) 'timezone': tz,
    });
    if (res is Map<String, dynamic>) return (res['created_count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  /// Stops future occurrences; completed and past tasks stay in history.
  Future<void> delete(String id) async {
    final tz = await TimezoneService.localIanaName();
    await api.delete(tz == null ? '/api/v1/routines/$id' : '/api/v1/routines/$id?timezone=${Uri.encodeQueryComponent(tz)}');
  }
}
