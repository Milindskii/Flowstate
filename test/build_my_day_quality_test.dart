import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/ai_plan_service.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Build My Day quality pass (spec 2026-10-03): the candidate contract survives
/// /ai/plan JSON -> ExtractedTaskItem -> TaskItem -> confirm payload, and failures carry a code.
Map<String, dynamic> candidate([Map<String, dynamic> extra = const {}]) => {
      'candidate_id': 'c_send',
      'title': 'Send assignment to professor',
      'estimated_minutes': 10,
      'task_type': 'admin',
      'difficulty': 'light',
      'priority': 'high',
      'priority_source': 'inferred',
      'duration_source': 'inferred',
      'focus_level': 'low',
      'focus_source': 'inferred',
      'deadline_at': '2026-10-06T00:00:00+05:30',
      'deadline_kind': 'hard',
      'depends_on': ['c_dbms'],
      'preferred_start': null,
      'preferred_window_start': '2026-10-05T17:00:00+05:30',
      'preferred_window_end': '2026-10-05T21:00:00+05:30',
      'recommended_slot_start': '2026-10-05T17:30:00+05:30',
      'recommended_slot_end': '2026-10-05T17:40:00+05:30',
      'planned_date': '2026-10-05',
      ...extra,
    };

class _FailingApi extends ApiService {
  final int status;
  final Map<String, dynamic> data;
  _FailingApi(this.status, this.data);

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async =>
      throw ApiException(data['detail'] as String? ?? 'error', statusCode: status, data: data);
}

class _ThrowingApi extends ApiService {
  final ApiException error;
  _ThrowingApi(this.error);

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async => throw error;
}

/// Fake backend for the Build My Day sheet. `/ai/plan` fails with [failCode] until it is null.
class _PlanApi extends ApiService {
  String? failCode;
  int planCalls = 0;
  int statusCalls = 0;
  final List<String?> requestIds = [];
  final List<Map<String, dynamic>> reports = [];
  _PlanApi({this.failCode});

  static Map<String, dynamic> task(String id, String title, Map<String, dynamic> extra) => {
        'candidate_id': id,
        'title': title,
        'estimated_minutes': 60,
        'task_type': 'deep_work',
        'difficulty': 'medium',
        'duration_source': 'explicit',
        'focus_source': 'inferred',
        'recommended_slot_start': '2026-10-05T14:00:00+05:30',
        'recommended_slot_end': '2026-10-05T15:00:00+05:30',
        'planned_date': '2026-10-05',
        ...extra,
      };

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/ai/plan') {
      planCalls++;
      requestIds.add((body as Map)['idempotency_key'] as String?);
      if (failCode != null) {
        throw ApiException('AI task structuring failed.',
            statusCode: 502, data: {'detail': 'AI task structuring failed.', 'failure_code': failCode});
      }
      return {
        'tasks': [
          task('c_a', 'Finish DBMS assignment', {
            'priority': 'high',
            'priority_source': 'explicit',
            'focus_level': 'high',
            'focus_source': 'explicit',
            'recommended_slot_display': 'Mon · 2:00 PM',
          }),
          task('c_b', 'Send it to the professor', {
            'priority': 'medium',
            'priority_source': 'inferred',
            'focus_level': 'low',
            'depends_on': ['c_a'],
            'recommended_slot_start': '2026-10-05T15:15:00+05:30',
            'recommended_slot_end': '2026-10-05T15:25:00+05:30',
            'recommended_slot_display': 'Mon · 3:15 PM',
          }),
        ],
        'ambiguities': [],
        'needs_confirmation': false,
      };
    }
    if (endpoint == '/api/v1/ai/planning-attempts') {
      reports.add(Map<String, dynamic>.from(body as Map));
      return null;
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/ai/status') {
      statusCalls++;
      return {
        'is_pro': false,
        'subscription_tier': 'free',
        'free_use_available': true,
        'free_uses_consumed': 0,
        'shields_available': 2,
        'shield_funded_uses': 0,
        'can_use_ai': true,
        'requires_shield': false,
        'hourly_requests_remaining': 5,
      };
    }
    if (endpoint == '/api/v1/tasks') return {'items': [], 'total': 0};
    return <String, dynamic>{};
  }
}

const _ambiguous = 'I need to get that project thing done sometime before my meeting, then send it';

const _guest = AuthUser(id: 'guest_demo', email: 'demo@flowstate.local', name: 'Demo', onboardingCompleted: true);

Future<void> _openAndBuild(WidgetTester tester, _PlanApi api, {AuthUser? as}) async {
  const signedIn = AuthUser(id: 'user-bmdq', email: 'q@flowstate.local', name: 'Q', onboardingCompleted: true);
  final user = as ?? signedIn;
  final appState = AppStateProvider(customApi: api, initialUser: user);
  if (appState.currentUser == null) appState.onUserAuthenticated(user);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStateProvider>.value(value: appState),
      ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
      ChangeNotifierProvider<FlowProvider>.value(value: FlowProvider(api: api)),
    ],
    child: MaterialApp(
      theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(onPressed: () => showBrainDumpSheet(ctx), child: const Text('Open')),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('brain_dump_text_field')), _ambiguous);
  await tester.pump();
  await tester.tap(find.byKey(const Key('brain_dump_build_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('Plan Result (sheet)', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({kGeminiPrivacyAcceptedKey: true});
      TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    });
    tearDown(() => FlowClock().stopTimer());

    testWidgets('AI failure keeps dump and shows Retry with AI + Use basic planner', (tester) async {
      final api = _PlanApi(failCode: 'gemini_error');
      await _openAndBuild(tester, api);
      expect(find.textContaining('AI planning failed'), findsOneWidget);
      expect(find.text('Retry with AI'), findsOneWidget);
      expect(find.text('Use basic planner'), findsOneWidget);
      expect(find.text(_ambiguous), findsOneWidget); // raw dump preserved
      expect(find.text('YOUR PLAN'), findsNothing); // never silently replaced by a local plan
    });

    testWidgets('signed out: AI is never called, a clean sign-in prompt replaces any provider error', (tester) async {
      final api = _PlanApi();
      await _openAndBuild(tester, api, as: _guest);
      expect(api.planCalls, 0, reason: 'no AI call for a signed-out user');
      expect(api.statusCalls, 0);
      expect(api.reports, isEmpty, reason: 'nothing is sent to the server either');
      expect(find.text('Sign in to use AI planning'), findsOneWidget);
      expect(find.byKey(const Key('sign_in_for_ai_button')), findsOneWidget);
      expect(find.text('Use basic planner'), findsOneWidget);
      expect(find.text('Retry with AI'), findsNothing);
      expect(find.textContaining('AI planning failed'), findsNothing, reason: 'signing in is not a failure');
      expect(find.textContaining('Gemini'), findsNothing);
      expect(find.text(_ambiguous), findsOneWidget); // dump preserved
      expect(find.text('YOUR PLAN'), findsNothing); // never silently replaced by a local plan
    });

    testWidgets('signed out: basic planner is explicit, labelled, and still makes no AI call', (tester) async {
      final api = _PlanApi();
      await _openAndBuild(tester, api, as: _guest);
      await tester.tap(find.text('Use basic planner'));
      await tester.pumpAndSettle();
      expect(find.text('Basic plan (not AI)'), findsOneWidget);
      expect(find.text('Enhanced with AI'), findsNothing);
      expect(api.planCalls, 0);
      expect(api.statusCalls, 0);
    });

    testWidgets('each failure code explains itself and never claims Gemini was unreachable', (tester) async {
      const expected = {
        'provider_unavailable': 'busy',
        'provider_quota': 'capacity',
        'model_not_found': 'temporarily unavailable',
        'provider_auth': 'temporarily unavailable',
        'timeout': 'too long',
        'network': 'unreachable',
        'ai_busy': 'busy',
        'rate_limited': 'planning limit',
        'request_in_progress': 'still working',
        'pro_cap_day': "today's fair-use",
        'pro_cap_month': "month's fair-use",
        'offline': "couldn't connect",
        'server_error': 'having trouble',
      };
      for (final entry in expected.entries) {
        final api = _PlanApi(failCode: entry.key);
        await _openAndBuild(tester, api);
        expect(find.textContaining('AI planning failed'), findsOneWidget, reason: entry.key);
        expect(find.textContaining(entry.value), findsOneWidget, reason: entry.key);
        expect(find.textContaining("couldn't be reached"), findsNothing, reason: entry.key);
        expect(find.textContaining('Gemini'), findsNothing, reason: '${entry.key}: provider names never reach the user');
        expect(find.textContaining('HTTP'), findsNothing, reason: entry.key);
        for (final banned in ['AI service', 'provider', 'quota', 'misconfigured', 'model', 'Google', 'server error']) {
          expect(find.textContaining(banned), findsNothing, reason: '${entry.key}: "$banned" is internal terminology');
        }
        expect(find.text(_ambiguous), findsOneWidget, reason: '${entry.key}: dump preserved');
        expect(find.text('Retry with AI'), findsOneWidget, reason: entry.key);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Use basic planner labels plan "Basic plan (not AI)" and makes no AI call', (tester) async {
      final api = _PlanApi(failCode: 'malformed');
      await _openAndBuild(tester, api);
      final plansBefore = api.planCalls;
      final statusBefore = api.statusCalls;
      await tester.tap(find.text('Use basic planner'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Basic plan (not AI)'), findsOneWidget);
      expect(find.text('Enhanced with AI'), findsNothing);
      expect(api.planCalls, plansBefore);
      expect(api.statusCalls, statusBefore);
    });

    testWidgets('Retry with AI reuses the same requestId', (tester) async {
      final api = _PlanApi(failCode: 'gemini_error');
      await _openAndBuild(tester, api);
      api.failCode = null;
      await tester.tap(find.text('Retry with AI'));
      await tester.pumpAndSettle();
      expect(api.planCalls, 2);
      expect(api.requestIds[0], isNotNull);
      expect(api.requestIds[1], api.requestIds[0]);
      expect(find.text('Enhanced with AI'), findsOneWidget);
    });

    testWidgets('AI plan slots are rendered unchanged', (tester) async {
      final api = _PlanApi();
      await _openAndBuild(tester, api);
      expect(find.text('Mon · 2:00 PM'), findsOneWidget);
      expect(find.text('Mon · 3:15 PM'), findsOneWidget);
    });

    testWidgets('explicit vs inferred priority labels; no "Priority not specified"; high focus chip', (tester) async {
      final api = _PlanApi();
      await _openAndBuild(tester, api);
      expect(find.text('High priority'), findsOneWidget);
      expect(find.text('Suggested: Medium'), findsOneWidget);
      expect(find.text('Priority not specified'), findsNothing);
      expect(find.text('High focus'), findsOneWidget);
    });
  });

  group('contract fields', () {
    test('task_type from the backend is read (it was always deep_work)', () {
      final t = ExtractedTaskItem.fromJson(candidate()).toTaskItem();
      expect(t.taskType, TaskType.admin);
    });

    test('fromJson -> TaskItem carries every new field; candidate_id becomes the item id', () {
      final t = ExtractedTaskItem.fromJson(candidate()).toTaskItem();
      expect(t.id, 'c_send');
      expect(t.candidateId, 'c_send');
      expect(t.prioritySource, 'inferred');
      expect(t.durationSource, 'inferred');
      expect(t.focusLevel, 'low');
      expect(t.focusSource, 'inferred');
      expect(t.deadlineKind, 'hard');
      expect(t.dependsOn, ['c_dbms']);
      expect(t.preferredWindowStart!.toUtc(), DateTime.utc(2026, 10, 5, 11, 30));
      expect(t.preferredWindowEnd!.toUtc(), DateTime.utc(2026, 10, 5, 15, 30));
    });

    test('batch payload sends the contract', () {
      final t = ExtractedTaskItem.fromJson(candidate()).toTaskItem();
      final b = AppStateProvider.candidateToBatchItem(t);
      expect(b['candidate_id'], 'c_send');
      expect(b['client_ref'], 'c_send');
      expect(b['depends_on'], ['c_dbms']);
      expect(b['priority'], 'high');
      expect(b['priority_source'], 'inferred');
      expect(b['duration_source'], 'inferred');
      expect(b['focus_level'], 'low');
      expect(b['focus_source'], 'inferred');
      expect(b['deadline_kind'], 'hard');
      expect(DateTime.parse(b['preferred_window_start'] as String).toUtc(), DateTime.utc(2026, 10, 5, 11, 30));
      expect(b['task_type'], 'admin');
    });

    test('inferred preferred window is not sent (only top-level, explicit windows exist)', () {
      final json = candidate({
        'preferred_window_start': null,
        'preferred_window_end': null,
        'temporal': {'preferred_window_start': '2026-10-05T08:00:00+05:30'},
      });
      final b = AppStateProvider.candidateToBatchItem(ExtractedTaskItem.fromJson(json).toTaskItem());
      expect(b.containsKey('preferred_window_start'), isFalse);
      expect(b.containsKey('preferred_start'), isFalse);
    });

    test('edited field becomes explicit in batch payload', () {
      final original = ExtractedTaskItem.fromJson(candidate()).toTaskItem();
      final newStart = DateTime(2026, 10, 5, 19, 0);
      final edited = applyPreviewEdit(
        original,
        original.copyWith(durationMinutes: 25, priority: TaskPriority.low, scheduledStart: newStart),
      );
      final b = AppStateProvider.candidateToBatchItem(edited);
      expect(b['duration_source'], 'explicit');
      expect(b['priority_source'], 'explicit');
      expect(b['time_locked'], isTrue);
      expect(b['focus_source'], 'inferred'); // untouched field keeps its source
    });
  });

  group('failures carry a code', () {
    setUp(() => TimezoneService.overrideForTesting = () async => 'Asia/Kolkata');

    test('generatePlan maps failure_code to AIPlanFailure', () async {
      final api = _FailingApi(502, {'detail': 'AI task structuring failed.', 'failure_code': 'malformed'});
      await expectLater(
        AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
        throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'malformed')),
      );
    });

    test('quota (402) is a quota_exhausted AIPlanFailure', () async {
      final api = _FailingApi(402, {'detail': 'requires 1 Flow Shield', 'failure_code': 'quota_exhausted'});
      await expectLater(
        AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
        throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'quota_exhausted')),
      );
    });

    test('Flowstate server unreachable is offline, never an AI-provider error', () async {
      for (final api in [_FailingApi(0, {'detail': 'offline'}), _ThrowingApi(const ApiException('Connection refused'))]) {
        await expectLater(
          AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
          throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'offline')),
        );
      }
    });

    test('a 5xx with no failure_code is server_error, not an AI-provider error', () async {
      final api = _FailingApi(500, {'detail': 'Internal Server Error'});
      await expectLater(
        AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
        throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'server_error')),
      );
    });

    test('AI gateway codes pass through unchanged', () async {
      for (final entry in {503: 'ai_busy', 429: 'rate_limited', 409: 'request_in_progress', 402: 'pro_cap_day'}.entries) {
        final api = _FailingApi(entry.key, {'detail': 'x', 'failure_code': entry.value});
        await expectLater(
          AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
          throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', entry.value)),
          reason: '${entry.key}',
        );
      }
    });

    test('a bare 401/403 from the server is auth_required, never a provider error', () async {
      for (final status in [401, 403]) {
        final api = _FailingApi(status, {'detail': 'Not authenticated'});
        await expectLater(
          AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
          throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'auth_required')),
          reason: '$status',
        );
      }
    });

    test('a 403 that carries a failure_code keeps that code (quota is not a sign-in problem)', () async {
      final api = _FailingApi(403, {'detail': 'quota', 'failure_code': 'quota_exhausted'});
      await expectLater(
        AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
        throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'quota_exhausted')),
      );
    });

    test('a client-side timeout is its own code, not the generic gemini_error', () async {
      final api = _ThrowingApi(const ApiException('Request timed out. Please try again.', isTimeout: true));
      await expectLater(
        AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
        throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', 'timeout')),
      );
    });

    test('provider failure codes from the server pass through unchanged', () async {
      for (final code in ['provider_unavailable', 'provider_quota', 'model_not_found', 'provider_auth', 'network']) {
        final api = _FailingApi(502, {'detail': 'AI task structuring failed.', 'failure_code': code});
        await expectLater(
          AIPlanService(api: api).generatePlan(rawText: 'messy dump', requestId: 'req-1'),
          throwsA(isA<AIPlanFailure>().having((f) => f.code, 'code', code)),
        );
      }
    });

    test('the AI plan call outlives the backend fallback chain; ordinary calls keep 12s', () {
      expect(ApiService.postTimeoutFor('/api/v1/ai/plan'), greaterThanOrEqualTo(const Duration(seconds: 40)));
      expect(ApiService.postTimeoutFor('/api/v1/tasks'), const Duration(seconds: 12));
    });
  });
}
