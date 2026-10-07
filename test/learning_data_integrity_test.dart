import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

/// Learning data integrity (2026-10-07): completing a task never posts made-up ratings, a reflection syncs only
/// what the user actually gave, and a failed sync stays queued until the next successful Today refresh.
class _Api extends ApiService {
  final List<(String, Map<String, dynamic>)> posts = [];
  bool failFeedback = false;
  int feedbackDelivered = 0;

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    final b = (body as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    posts.add((endpoint, b));
    if (endpoint.endsWith('/feedback')) {
      if (failFeedback) throw const ApiException('offline');
      feedbackDelivered++;
    }
    if (endpoint.endsWith('/complete')) return {'id': 't1', 'title': 'Write essay', 'status': 'completed'};
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/tasks') {
      return {
        'items': [
          {'id': 't1', 'title': 'Write essay', 'estimated_minutes': 45, 'status': 'todo', 'category': 'Study',
           'difficulty': 'medium', 'priority': 'medium'},
        ],
        'total': 1,
      };
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> bodiesTo(String suffix) =>
      posts.where((p) => p.$1.endsWith(suffix)).map((p) => p.$2).toList();
}

const _user = AuthUser(id: 'user-learn', email: 'l@flowstate.local', name: 'L', onboardingCompleted: true);

Future<(AppStateProvider, _Api)> _signedIn() async {
  final api = _Api();
  final app = AppStateProvider(customApi: api, initialUser: _user);
  if (app.currentUser == null) await app.onUserAuthenticated(_user);
  await app.loadUserTasks();
  api.posts.clear();
  return (app, api);
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  });
  tearDown(() => FlowClock().stopTimer());

  test('completing a task posts no ratings and no planned-as-actual minutes', () async {
    final (app, api) = await _signedIn();
    app.toggleTaskCompletion('t1');
    await Future<void>.delayed(Duration.zero);
    expect(api.bodiesTo('/feedback'), isEmpty, reason: 'no made-up focus 5 / Energized reflection');
    final complete = api.bodiesTo('/complete');
    expect(complete, hasLength(1));
    expect(complete.single.containsKey('actual_minutes'), isFalse);
    expect(api.posts.where((p) => p.$1.contains('readiness/observations')), isEmpty);
  });

  test('a reflection syncs only what the user gave, to the task feedback endpoint', () async {
    final (app, api) = await _signedIn();
    app.recordTaskFeedback(
        taskId: 't1', actualMinutes: 45, feeling: 3, energyScore: 4, focusScore: 4, durationFeedback: 'longer');
    await Future<void>.delayed(Duration.zero);
    final fb = api.bodiesTo('/api/v1/tasks/t1/feedback');
    expect(fb, hasLength(1));
    expect(fb.single['focus_score'], 4);
    expect(fb.single['energy_score'], 4);
    expect(fb.single.containsKey('difficulty_score'), isFalse, reason: 'untouched slider is not a rating');
    expect(fb.single.containsKey('distraction_score'), isFalse);
    expect(fb.single.containsKey('actual_minutes'), isFalse, reason: 'not measured by a focus timer');
    expect(fb.single['notes'], contains('Feeling: Good'));
    expect(api.posts.where((p) => p.$1.contains('readiness/observations')), isEmpty,
        reason: 'the old observation post used an invalid source and a 1-4 scale as energy');
    expect(app.reflectionFor('t1')!.pendingSync, isNull, reason: 'delivered, so nothing is queued');
  });

  test('a measured focus session duration is sent', () async {
    final (app, api) = await _signedIn();
    app.recordTaskFeedback(taskId: 't1', actualMinutes: 52, feeling: 4, focusScore: 5, durationMeasured: true);
    await Future<void>.delayed(Duration.zero);
    expect(api.bodiesTo('/feedback').single['actual_minutes'], 52);
  });

  test('a failed sync stays queued and is delivered after the next successful Today refresh', () async {
    final (app, api) = await _signedIn();
    api.failFeedback = true;
    app.recordTaskFeedback(taskId: 't1', actualMinutes: 45, feeling: 2, focusScore: 2, difficultyScore: 4);
    await Future<void>.delayed(Duration.zero);
    expect(app.reflectionFor('t1')!.pendingSync, isNotNull);

    api.failFeedback = false;
    await app.refreshTodayData();
    await Future<void>.delayed(Duration.zero);
    expect(api.feedbackDelivered, 1, reason: 'delivered exactly once, however many retries failed');
    expect(api.bodiesTo('/feedback').last['difficulty_score'], 4);
    expect(app.reflectionFor('t1')!.pendingSync, isNull);
  });
}
