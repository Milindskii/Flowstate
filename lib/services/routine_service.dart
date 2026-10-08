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

  /// Also tops the 7-day horizon up on the server, so routines keep planning after an app restart.
  Future<List<Routine>> list() async {
    final tz = await TimezoneService.localIanaName();
    final res = await api.get('/api/v1/routines', queryParams: {if (tz != null) 'timezone': tz});
    if (res is List) {
      return res.whereType<Map<String, dynamic>>().map(Routine.fromJson).toList();
    }
    return const [];
  }

  Future<void> update(String id, {String? startHhmm, int? estimatedMinutes, String? title}) async {
    final tz = await TimezoneService.localIanaName();
    await api.patch('/api/v1/routines/$id', body: {
      if (startHhmm != null) 'start_hhmm': startHhmm,
      if (estimatedMinutes != null) 'estimated_minutes': estimatedMinutes,
      if (title != null) 'title': title,
      if (tz != null) 'timezone': tz,
    });
  }

  /// Stops future occurrences; completed and past tasks stay in history.
  Future<void> delete(String id) async {
    final tz = await TimezoneService.localIanaName();
    await api.delete(tz == null ? '/api/v1/routines/$id' : '/api/v1/routines/$id?timezone=${Uri.encodeQueryComponent(tz)}');
  }
}
