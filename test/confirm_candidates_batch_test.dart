import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/plan_confirm_exception.dart';
import 'package:flowstate/services/timezone_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BatchApi extends ApiService {
  final List<Map<String, dynamic>> batchBodies = [];
  bool failNetwork = false;
  Map<String, dynamic>? validationDetail;

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/tasks/batch-create-and-schedule') {
      batchBodies.add(Map<String, dynamic>.from(body as Map));
      if (failNetwork) throw const ApiException('offline');
      if (validationDetail != null) {
        throw ApiException('Unprocessable',
            statusCode: 422, data: {'detail': validationDetail});
      }
      final items = (body['tasks'] as List).cast<Map>();
      return {
        'created_count': items.length,
        'client_refs': items.map((i) => i['client_ref']).toList(),
        'tasks': [
          for (var i = 0; i < items.length; i++)
            {
              ...Map<String, dynamic>.from(items[i]),
              'id': 'srv-$i',
              'status': 'todo',
              'created_at': '2026-10-05T03:00:00Z',
              'updated_at': '2026-10-05T03:00:00Z',
            }
        ],
      };
    }
    return {};
  }

  @override
  Future<dynamic> get(String endpoint,
      {Map<String, String>? queryParams}) async {
    throw const ApiException(
        'offline'); // Today/Calendar refreshes are best-effort
  }
}

TaskItem _candidate(String id, String title,
        {DateTime? start, bool locked = false}) =>
    TaskItem(
      id: id,
      title: title,
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      scheduledStart: start,
      timeLocked: locked,
    );

void main() {
  late _BatchApi api;
  late AppStateProvider app;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    api = _BatchApi();
    app = AppStateProvider(customApi: api);
    app.setCurrentUserForTesting(const AuthUser(
        id: 'u1', email: 'u@x.local', name: 'U', onboardingCompleted: true));
    app.setTasksForTesting([]);
  });

  tearDown(() {
    TimezoneService.overrideForTesting = null;
    TimezoneService.resetCache();
  });

  test(
      'confirm sends ONE request with plan_id, IANA zone, full instants and honest lock flags',
      () async {
    final tomorrow = DateTime(2026, 10, 6, 9, 30);
    await app.confirmCandidates([
      _candidate('tmp-1', 'Study', start: tomorrow),
      _candidate('tmp-2', 'Dentist',
          start: DateTime(2026, 10, 5, 18), locked: true),
      _candidate('tmp-3', 'Email'),
    ], planId: 'plan-A');

    expect(api.batchBodies.length, 1);
    final body = api.batchBodies.single;
    expect(body['plan_id'], 'plan-A');
    expect(body['timezone'], 'Asia/Kolkata');
    final tasks = (body['tasks'] as List).cast<Map>();
    expect(tasks[0]['scheduled_start'], tomorrow.toUtc().toIso8601String(),
        reason: 'tomorrow stays tomorrow');
    expect((tasks[0]['scheduled_start'] as String).endsWith('Z'), isTrue);
    expect(tasks[0]['time_locked'], false,
        reason: 'a recommendation is not a lock');
    expect(tasks[1]['time_locked'], true);
    expect(tasks[2].containsKey('scheduled_start'), isFalse,
        reason: 'no start => the server places it');
    expect(tasks.map((t) => t['client_ref']).toList(),
        ['tmp-1', 'tmp-2', 'tmp-3']);
  });

  test(
      'on success local state is the rows the server stored (real ids), nothing optimistic',
      () async {
    await app.confirmCandidates(
        [_candidate('tmp-1', 'A'), _candidate('tmp-2', 'B')],
        planId: 'plan-B');
    expect(app.tasks.map((t) => t.id).toSet(), {'srv-0', 'srv-1'});
    expect(app.tasks.any((t) => t.id.startsWith('tmp-')), isFalse);
  });

  test(
      'a failed confirm throws, leaves NO phantom tasks, and a retry reuses the same plan_id',
      () async {
    api.failNetwork = true;
    await expectLater(
      app.confirmCandidates([_candidate('tmp-1', 'A')], planId: 'plan-C'),
      throwsA(isA<PlanConfirmException>()
          .having((e) => e.isValidation, 'isValidation', false)),
    );
    expect(app.tasks, isEmpty,
        reason: 'nothing may look saved when it was not');

    api.failNetwork = false;
    await app.confirmCandidates([_candidate('tmp-1', 'A')], planId: 'plan-C');
    expect(api.batchBodies.map((b) => b['plan_id']).toSet(), {'plan-C'},
        reason: 'idempotent retry');
    expect(app.tasks.length, 1);
  });

  test(
      'a 422 surfaces the server message per item so the user can pick another time',
      () async {
    api.validationDetail = {
      'code': 'validation_failed',
      'errors': [
        {
          'index': 1,
          'client_ref': 'tmp-2',
          'field': 'scheduled_start',
          'code': 'explicit_time_in_past',
          'message':
              '\u201cCall mom\u201d is set for 7:00 AM, which has already passed. Choose a new time.',
          'title': 'Call mom',
        }
      ],
    };
    try {
      await app.confirmCandidates(
          [_candidate('tmp-1', 'Fine'), _candidate('tmp-2', 'Call mom')],
          planId: 'plan-D');
      fail('expected PlanConfirmException');
    } on PlanConfirmException catch (e) {
      expect(e.isValidation, isTrue);
      expect(e.errorFor('tmp-2')!.message, contains('already passed'));
      expect(e.errorFor('tmp-2')!.needsNewTime, isTrue);
      expect(e.errorFor('tmp-1'), isNull);
    }
    expect(app.tasks, isEmpty);
  });
}
