import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/shield_popups.dart';
import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/flow_service.dart';
import 'package:flowstate/services/shield_earning.dart';

/// Shields on screen are always the server's: the pill, Noya's zero-Shield popup (ads, pack, dismiss) and the streak
/// restore popup (cost shown first, one request per confirmation, balance from the reply).
class _Server extends ApiService {
  int shields;
  bool adsEnabled;
  bool eligible;
  int adProgress = 0;
  int restorePosts = 0;
  int adSessionPosts = 0;
  int statusGets = 0;
  final List<Map<String, dynamic>> restoreBodies = [];
  Completer<void>? holdRestore;
  bool googleVerifies = true;

  _Server({this.shields = 0, this.adsEnabled = false, this.eligible = false});

  @override
  bool get isAuthenticated => true;

  Map<String, dynamic> wallet() => {
        'balance': shields,
        'maximum': 3,
        'server_now': DateTime.utc(2026, 10, 9, 10).toIso8601String(),
        'next_refill_at': shields < 3 ? DateTime.utc(2026, 10, 11, 10).toIso8601String() : null,
        'costs': {'build_my_day': 1, 'replan': 1, 'streak_restore': 1},
        'ads': {
          'enabled': adsEnabled,
          'ad_unit_id': adsEnabled ? 'ca-app-pub-test/123' : null,
          'ads_per_reward': 5,
          'shields_per_reward': 1,
          'progress': adProgress,
          'ads_today': adProgress,
          'daily_limit': 10,
          'daily_remaining': 10 - adProgress,
        },
        'pack': {
          'enabled': false,
          'store': 'google_play',
          'product_id': 'flowstate_shield_pack_20',
          'price_inr': 20,
          'price_display': '₹20',
          'units': 5,
          'account_ref': 'ref',
        },
      };

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/shields') return wallet();
    if (endpoint.startsWith('/api/v1/shields/ads/sessions/')) {
      statusGets++;
      if (googleVerifies) {
        adProgress += 1;
        final granted = adProgress >= 5 ? 1 : 0;
        if (granted > 0) {
          shields += 1;
          adProgress = 0;
        }
        return {'session_id': 's1', 'status': 'verified', 'shields_granted': granted, 'wallet': wallet()};
      }
      return {'session_id': 's1', 'status': 'pending', 'shields_granted': 0, 'wallet': wallet()};
    }
    final json = FlowOverview.defaultInitial(userId: 'acct').toJson();
    (json['profile'] as Map<String, dynamic>)['shields_available'] = shields;
    (json['profile'] as Map<String, dynamic>)['current_streak'] = 6;
    json['streak_recovery'] = {
      'eligible': eligible,
      'streak': 6,
      'missed_days': 2,
      'cost': 1,
      'shields_available': shields,
      'can_afford': shields >= 1,
    };
    return json;
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/flow/streak/restore') {
      restorePosts++;
      restoreBodies.add(Map<String, dynamic>.from(body as Map));
      if (holdRestore != null) await holdRestore!.future;
      shields -= 1;
      eligible = false;
      return {'restored': true, 'replayed': false, 'current_streak': 6, 'shields_spent': 1,
              'shields_available': shields, 'message': 'Your 6-day streak is back. Keep it going today.'};
    }
    if (endpoint == '/api/v1/shields/ads/sessions') {
      adSessionPosts++;
      return {'session_id': 's1', 'ssv_user_id': 'acct', 'ad_unit_id': 'ca-app-pub-test/123',
              'expires_at': DateTime.utc(2026, 10, 9, 11).toIso8601String()};
    }
    return <String, dynamic>{};
  }
}

class _FakeAds implements RewardedAdGateway {
  final RewardedAdOutcome outcome;
  final List<String> shownWith = [];
  _FakeAds(this.outcome);

  @override
  bool get isAvailable => true;

  @override
  Future<RewardedAdOutcome> show({required String adUnitId, required String ssvUserId, required String customData}) async {
    shownWith.add('$ssvUserId/$customData');
    return outcome;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlowClock.enableAutoTick = false;
    FlowProvider.adPollInterval = Duration.zero;
  });
  tearDown(() {
    ShieldEarning.ads = const UnconfiguredRewardedAds();
    ShieldEarning.store = const UnconfiguredShieldPackStore();
  });

  Future<FlowProvider> loaded(_Server server) async {
    final p = FlowProvider(service: FlowService(api: server, currentUserId: () => 'acct'), api: server);
    await p.loadOverview();
    await p.loadWallet();
    return p;
  }

  Future<void> host(WidgetTester tester, FlowProvider flow, {Widget? child}) async {
    await tester.pumpWidget(ChangeNotifierProvider<FlowProvider>.value(
      value: flow,
      child: MaterialApp(home: Scaffold(body: Center(child: child ?? const ShieldBalancePill()))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the pill hides until the server answered, then shows its balance and follows every update',
      (tester) async {
    final unloaded = FlowProvider(service: FlowService(api: _Server(), currentUserId: () => 'acct'));
    await host(tester, unloaded);
    expect(find.byKey(const Key('shield_balance_pill')), findsNothing, reason: 'never a placeholder 0');

    final flow = await loaded(_Server(shields: 2));
    await host(tester, flow);
    expect(find.text('2'), findsOneWidget);
    flow.applyServerShieldBalance(1); // e.g. Build My Day's usage status after a plan
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('zero Shields: Noya sleeps, shows the balance, ads and the ₹20 pack (coming soon), and dismisses',
      (tester) async {
    final flow = await loaded(_Server(shields: 0));
    await host(tester, flow);
    await tester.tap(find.byKey(const Key('shield_balance_pill')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('shield_wallet_popup')), findsOneWidget);
    expect(find.text("Oh no, you're out of Shields!"), findsOneWidget);
    expect(find.text('0 Shields'), findsOneWidget);
    expect(find.text('Watch 5 Ads'), findsOneWidget);
    expect(find.text('Get Shields for ₹20'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(2), reason: 'never claims ads or billing work before they do');

    await tester.tap(find.byKey(const Key('shield_popup_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shield_wallet_popup')), findsNothing);
  });

  testWidgets('watching ads: the server grants (after Google verifies), the app only reads the result',
      (tester) async {
    final server = _Server(shields: 0, adsEnabled: true)..adProgress = 4;
    final flow = await loaded(server);
    final ads = _FakeAds(RewardedAdOutcome.earned);
    ShieldEarning.ads = ads;
    await host(tester, flow);
    await tester.tap(find.byKey(const Key('shield_balance_pill')));
    await tester.pumpAndSettle();
    expect(find.text('4/5 ads watched · earns 1 Shield'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shield_popup_watch_ads')));
    await tester.pumpAndSettle();
    expect(ads.shownWith, ['acct/s1'], reason: 'SSV user id + session id go to the ad');
    expect(find.text('+1 Shield added.'), findsWidgets);
    expect(flow.shieldBalance, 1);
  });

  test('a dismissed ad grants nothing and never asks the server for a reward', () async {
    final server = _Server(shields: 0, adsEnabled: true);
    final flow = await loaded(server);
    ShieldEarning.ads = _FakeAds(RewardedAdOutcome.dismissed);
    final out = await flow.watchRewardedAd();
    expect(out.status, ShieldEarnStatus.notEarned);
    expect(server.statusGets, 0);
    expect(flow.shieldBalance, 0);
  });

  test('ads and pack report unavailable while unconfigured: no request is sent', () async {
    final server = _Server(shields: 0, adsEnabled: false);
    final flow = await loaded(server);
    expect((await flow.watchRewardedAd()).status, ShieldEarnStatus.unavailable);
    expect((await flow.buyShieldPack()).status, ShieldEarnStatus.unavailable);
    expect(server.adSessionPosts, 0);
  });

  testWidgets('streak restore: the cost is shown first, a double tap sends one request, the balance is the reply',
      (tester) async {
    final server = _Server(shields: 2, eligible: true)..holdRestore = Completer<void>();
    final flow = await loaded(server);
    await host(tester, flow, child: Builder(builder: (context) {
      return TextButton(onPressed: () => StreakRestorePopup.maybeShow(context), child: const Text('open'));
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Restore your streak'), findsOneWidget);
    expect(find.text('Restore with 1 Shield'), findsOneWidget);
    expect(find.byKey(const Key('shield_balance_pill')), findsOneWidget);

    await tester.tap(find.byKey(const Key('streak_restore_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('streak_restore_button')), warnIfMissed: false);
    server.holdRestore!.complete();
    await tester.pumpAndSettle();

    expect(server.restorePosts, 1);
    expect(server.restoreBodies.single['expected_cost'], 1);
    expect(flow.shieldBalance, 1);
    expect(find.byKey(const Key('streak_restore_popup')), findsNothing);

    // shown once a day: asking again does not reopen it
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak_restore_popup')), findsNothing);
  });

  testWidgets('streak restore: Dismiss spends nothing; without Shields Restore becomes Get Shields', (tester) async {
    final server = _Server(shields: 0, eligible: true);
    final flow = await loaded(server);
    await host(tester, flow, child: Builder(builder: (context) {
      return TextButton(
          onPressed: () => StreakRestorePopup.show(context, flow.streakRecovery), child: const Text('open'));
    }));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Get Shields'), findsOneWidget);
    await tester.tap(find.byKey(const Key('streak_restore_dismiss')));
    await tester.pumpAndSettle();
    expect(server.restorePosts, 0);
    expect(flow.shieldBalance, 0);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('streak_restore_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shield_wallet_popup')), findsOneWidget, reason: 'out of Shields: the earn popup');
    expect(server.restorePosts, 0);
  });
}
