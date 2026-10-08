import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_service.dart';

/// The app may DISPLAY what the server said, but it never makes up a balance and never shows one account's progression
/// (Shields, Flow, streak) to another. The server stays the source of truth on every read.
class _FlowApi extends ApiService {
  Map<String, dynamic>? body;
  Object? failure;
  int reads = 0;

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    reads++;
    if (failure != null) throw failure!;
    return body;
  }
}

Map<String, dynamic> _overview(String userId, int shields) {
  final base = FlowOverview.defaultInitial(userId: userId);
  final json = base.toJson();
  (json['profile'] as Map<String, dynamic>)['shields_available'] = shields;
  return json;
}

const _cacheKey = 'flowstate_flow_overview_cache';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the offline copy belongs to one account', () {
    test('a read caches what the server said, and it is shown back only to that account', () async {
      final api = _FlowApi()..body = _overview('acct-a', 2);
      String? me = 'acct-a';
      final service = FlowService(api: api, currentUserId: () => me);
      expect((await service.getOverview()).profile.shieldsAvailable, 2);

      api.failure = const ApiException('offline');
      expect((await service.getOverview()).profile.shieldsAvailable, 2, reason: 'A offline: A\'s own last copy');

      me = 'acct-b'; // another account signs in on the same device, still offline
      await expectLater(service.getOverview(), throwsA(isA<ApiException>()), reason: 'never A\'s Shields on B');
      me = null; // nobody signed in
      await expectLater(service.getOverview(), throwsA(isA<ApiException>()));
    });

    test('with no copy and no server the failure is reported, not a blank (zero) overview', () async {
      final api = _FlowApi()..failure = const ApiException('offline');
      final service = FlowService(api: api, currentUserId: () => 'acct-a');
      await expectLater(service.getOverview(), throwsA(isA<ApiException>()));
    });

    test('a fresh server read always replaces the copy: cached state cannot overwrite newer server state', () async {
      final api = _FlowApi()..body = _overview('acct-a', 0);
      final service = FlowService(api: api, currentUserId: () => 'acct-a');
      await service.getOverview();
      api.body = _overview('acct-a', 3);
      expect((await service.getOverview()).profile.shieldsAvailable, 3);
      final prefs = await SharedPreferences.getInstance();
      final cached = jsonDecode(prefs.getString(_cacheKey)!) as Map<String, dynamic>;
      expect((cached['profile'] as Map)['shields_available'], 3);
    });
  });

  group('signing out', () {
    test('wipes the progression state and the offline copy, and the next account starts from the server', () async {
      final api = _FlowApi()..body = _overview('acct-a', 2);
      final flow = FlowProvider(api: api, currentUserId: () => 'acct-a');
      SharedPreferences.setMockInitialValues({_cacheKey: jsonEncode(_overview('acct-a', 2))});
      flow.setOverviewForTesting(FlowOverview.fromJson(_overview('acct-a', 2)));
      expect(flow.profile.shieldsAvailable, 2);

      flow.reset();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(flow.profile.shieldsAvailable, 0, reason: 'nothing of A\'s balance is left in memory');
      expect((await SharedPreferences.getInstance()).getString(_cacheKey), isNull);
    });

    test('AppStateProvider.logout clears account state and tells the Flow provider to reset', () async {
      SharedPreferences.setMockInitialValues({
        'flowstate_skipped_task_ids': ['t1'],
        'flowstate_completed_after_deviation_task_ids': ['t2'],
        _cacheKey: jsonEncode(_overview('acct-a', 2)),
      });
      final app = AppStateProvider(
          customApi: _FlowApi(), initialUser: const AuthUser(id: 'acct-a', email: 'a@x.dev', name: 'A', onboardingCompleted: true));
      await app.routeStatesReady;
      var cleared = 0;
      app.onAccountCleared = () => cleared++;

      await app.logout();

      expect(cleared, 1);
      expect(app.currentUser, isNull);
      expect(app.completedAfterDeviationTaskIds, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('flowstate_skipped_task_ids'), isNull);
      expect(prefs.getStringList('flowstate_completed_after_deviation_task_ids'), isNull);
    });
  });
}
