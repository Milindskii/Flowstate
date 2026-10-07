import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/timezone_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _PatchApi extends ApiService {
  Map<String, dynamic>? patchBody;
  String? patchEndpoint;
  bool failPatch = false;

  @override
  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    patchEndpoint = endpoint;
    patchBody = Map<String, dynamic>.from(body as Map);
    if (failPatch) throw const ApiException('boom', statusCode: 500);
    return {
      'id': 't1',
      'title': 'Report',
      'estimated_minutes': 60,
      'status': 'todo',
    };
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async => {};

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams}) async {
    throw const ApiException('offline');
  }
}

TaskItem _task() => TaskItem(
      id: 't1',
      title: 'Report',
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      scheduledStart: DateTime(2026, 10, 5, 14),
      scheduledEnd: DateTime(2026, 10, 5, 15),
      deadlineAt: DateTime(2026, 10, 9, 17),
    );

void main() {
  late _PatchApi api;
  late AppStateProvider app;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    api = _PatchApi();
    app = AppStateProvider(customApi: api);
    app.setCurrentUserForTesting(const AuthUser(
        id: 'u1', email: 'u@x.local', name: 'U', onboardingCompleted: true));
    app.setTasksForTesting([_task()]);
  });

  tearDown(() {
    TimezoneService.overrideForTesting = null;
    TimezoneService.resetCache();
  });

  test(
      'date-only reschedule: planned_date set, old slot CLEARED with explicit nulls, deadline untouched (finding 10)',
      () async {
    final ok =
        await app.rescheduleTask('t1', targetDate: DateTime(2026, 10, 7));
    expect(ok, isTrue);
    final body = api.patchBody!;
    expect(api.patchEndpoint, '/api/v1/tasks/t1');
    expect(body.containsKey('deadline_at'), isFalse,
        reason: 'a reschedule must never write a deadline');
    expect(body.containsKey('scheduled_start'), isTrue);
    expect(body['scheduled_start'], isNull);
    expect(body['scheduled_end'], isNull);
    expect(body['planned_date'], '2026-10-07');
    expect(body['time_locked'], false);
    final local = app.tasks.single;
    expect(local.scheduledStart, isNull);
    expect(local.plannedDate, DateTime(2026, 10, 7));
    expect(local.deadlineAt, DateTime(2026, 10, 9, 17),
        reason: 'the real deadline is preserved');
  });

  test(
      'reschedule with a time: the user fixed it => locked, full instant, no planned_date',
      () async {
    final ok = await app.rescheduleTask('t1',
        targetDate: DateTime(2026, 10, 7),
        targetTime: const TimeOfDay(hour: 16, minute: 30));
    expect(ok, isTrue);
    final body = api.patchBody!;
    expect(body['scheduled_start'],
        DateTime(2026, 10, 7, 16, 30).toUtc().toIso8601String());
    expect(body['time_locked'], true);
    expect(body['planned_date'], isNull);
    expect(body.containsKey('deadline_at'), isFalse);
    expect(app.tasks.single.timeLocked, isTrue);
  });

  test(
      'a rejected save is reverted and reported, never shown as success (finding 12)',
      () async {
    api.failPatch = true;
    final ok =
        await app.rescheduleTask('t1', targetDate: DateTime(2026, 10, 7));
    expect(ok, isFalse);
    expect(app.tasks.single.scheduledStart, DateTime(2026, 10, 5, 14),
        reason: 'local state reverted');
    expect(app.lastSyncError, isNotNull);
    app.clearSyncError();
    expect(app.lastSyncError, isNull);
  });
}
