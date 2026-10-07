import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/calendar_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Replan may now read a message with the language model on the server: the app waits long enough, never sends
/// the same request twice, and Noya's shared thinking state starts at once and always settles.
class _ReplanApi extends ApiService {
  final Object Function(String endpoint) answer;
  final List<String> posts = [];
  _ReplanApi(this.answer);

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    posts.add(endpoint);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final a = answer(endpoint);
    if (a is Exception) throw a;
    return a;
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async =>
      endpoint == '/api/v1/tasks' ? {'items': [], 'total': 0} : <String, dynamic>{};
}

Map<String, dynamic> _diff() => {
      'success': true,
      'plan_diff': {
        'plan_id': 'p1',
        'selected_date': '2026-10-05',
        'before_schedule': [],
        'after_schedule': [],
        'moved_tasks': [],
        'cancelled_tasks': [],
        'conflicts': [],
        'explanation': 'ok',
      },
    };

const _user = AuthUser(id: 'user-rp', email: 'rp@flowstate.local', name: 'R', onboardingCompleted: true);

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  });

  test('replan waits longer than the server\'s model deadline', () {
    expect(ApiService.postTimeoutFor('/api/v1/ai/replan'), const Duration(seconds: 30));
    expect(ApiService.postTimeoutFor('/api/v1/calendar/replan'), const Duration(seconds: 30));
    expect(ApiService.postTimeoutFor('/api/v1/tasks'), const Duration(seconds: 12));
  });

  test('a timed-out replan is never sent a second time', () async {
    final api = _ReplanApi((_) => const ApiException('Request timed out.', isTimeout: true));
    final service = CalendarService(api: api);
    await expectLater(service.replanDay(dateStr: '2026-10-05', message: 'move gym'), throwsA(isA<ApiException>()));
    expect(api.posts, ['/api/v1/ai/replan']);
  });

  test('the alias is used only when the AI route is missing or failed outright', () async {
    final api = _ReplanApi((e) => e == '/api/v1/ai/replan' ? const ApiException('nf', statusCode: 404) : _diff());
    final service = CalendarService(api: api);
    final res = await service.replanDay(dateStr: '2026-10-05', message: 'move gym');
    expect(res.planDiff.planId, 'p1');
    expect(api.posts, ['/api/v1/ai/replan', '/api/v1/calendar/replan']);
  });

  test('a 422 (Noya could not read it) is shown, not retried', () async {
    final api = _ReplanApi((_) => const ApiException("I didn't understand that change.", statusCode: 422));
    await expectLater(CalendarService(api: api).replanDay(dateStr: '2026-10-05', message: 'hmm'),
        throwsA(isA<ApiException>()));
    expect(api.posts.length, 1);
  });

  for (final outcome in ['success', 'error', 'timeout']) {
    test('Noya thinks from the first moment and settles on $outcome', () async {
      final api = _ReplanApi((e) {
        if (!e.contains('replan')) return <String, dynamic>{};
        return switch (outcome) {
          'success' => _diff(),
          'error' => const ApiException('bad', statusCode: 422),
          _ => const ApiException('Request timed out.', isTimeout: true),
        };
      });
      final provider = AppStateProvider(customApi: api, initialUser: _user);
      await Future<void>.delayed(const Duration(milliseconds: 20)); // startup loads settle
      final pending = provider.replanDay(date: DateTime(2026, 10, 5), message: 'move gym to 8');
      expect(provider.busy.isThinking, isTrue, reason: 'thinking starts before any await');
      try {
        await pending;
      } catch (_) {}
      expect(provider.busy.isThinking, isFalse, reason: 'never stuck after $outcome');
    });
  }
}
