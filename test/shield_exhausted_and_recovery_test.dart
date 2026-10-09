import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/shield_popups.dart';
import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/models/shield_wallet.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/profile_settings_tab.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/flow_service.dart';
import 'package:flowstate/services/shield_earning.dart';

class _MockApi extends ApiService {
  int shields;
  bool returnInsufficientShieldsOnReplan;

  _MockApi({this.shields = 0, this.returnInsufficientShieldsOnReplan = false});

  @override
  bool get isAuthenticated => true;

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/shields') {
      return {
        'balance': shields,
        'maximum': 3,
        'server_now': DateTime.utc(2026, 10, 9, 10).toIso8601String(),
        'next_refill_at': DateTime.utc(2026, 10, 11, 10).toIso8601String(),
        'costs': {'build_my_day': 1, 'replan': 1, 'streak_restore': 1},
        'ads': {
          'enabled': false,
          'ad_unit_id': null,
          'ads_per_reward': 5,
          'shields_per_reward': 1,
          'progress': 0,
          'ads_today': 0,
          'daily_limit': 10,
          'daily_remaining': 10,
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
    }
    final json = FlowOverview.defaultInitial(userId: 'u1').toJson();
    (json['profile'] as Map<String, dynamic>)['shields_available'] = shields;
    return json;
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint.contains('/replan') && returnInsufficientShieldsOnReplan) {
      throw const ApiException(
        'Replan requires 1 Shield. You have 0 Shields.',
        statusCode: 403,
        data: {'detail': {'error': 'insufficient_shields', 'failure_code': 'insufficient_shields'}},
      );
    }
    return <String, dynamic>{};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlowClock.enableAutoTick = false;
  });

  tearDown(() {
    ShieldEarning.ads = const UnconfiguredRewardedAds();
    ShieldEarning.store = const UnconfiguredShieldPackStore();
  });

  testWidgets('ShieldWalletPopup renders exhausted-Shields experience with exact copy and actions', (tester) async {
    final api = _MockApi(shields: 0);
    final provider = FlowProvider(service: FlowService(api: api, currentUserId: () => 'u1'), api: api);
    await provider.loadOverview();
    await provider.loadWallet();

    await tester.pumpWidget(
      ChangeNotifierProvider<FlowProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ShieldWalletPopup.show(context),
                child: const Text('Open Popup'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Popup'));
    await tester.pumpAndSettle();

    // Verify modal elements
    expect(find.byKey(const Key('shield_wallet_popup')), findsOneWidget);
    expect(find.text("Oh no, you're out of Shields!"), findsOneWidget);
    expect(find.text('0 Shields'), findsOneWidget);
    expect(find.text('Shields are needed for AI-powered planning, like Build My Day and Replan.'), findsOneWidget);
    expect(find.text('Watch 5 Ads'), findsOneWidget);
    expect(find.text('Get Shields for ₹20'), findsOneWidget);
    expect(find.text('Coming soon'), findsNWidgets(2));
    expect(find.text('Not Now'), findsOneWidget);

    // Dismiss modal
    await tester.tap(find.byKey(const Key('shield_popup_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shield_wallet_popup')), findsNothing);
  });

  testWidgets('StreakRestorePopup renders active 7-hour recovery with countdown and options', (tester) async {
    final api = _MockApi(shields: 1);
    final provider = FlowProvider(service: FlowService(api: api, currentUserId: () => 'u1'), api: api);
    await provider.loadOverview();

    const recovery = StreakRecovery(
      eligible: true,
      streak: 5,
      missedDays: 1,
      cost: 1,
      shieldsAvailable: 1,
      canAfford: true,
      expired: false,
      secondsRemaining: 6 * 3600 + 42 * 60, // 6h 42m
      adsRequired: 5,
      adsProgress: 2,
      canRestoreWithAds: false,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<FlowProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => StreakRestorePopup.show(context, recovery),
                child: const Text('Open Restore'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Restore'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('streak_restore_popup')), findsOneWidget);
    expect(find.text('Restore your streak'), findsOneWidget);
    expect(find.text('Your 5-day streak has ended and can still be recovered.'), findsOneWidget);
    expect(find.text('6h 42m left'), findsOneWidget);
    expect(find.text('Restore with 1 Shield'), findsOneWidget);
    expect(find.text('Restore by watching 5 ads'), findsOneWidget);
    expect(find.text('Not Now'), findsOneWidget);

    await tester.tap(find.byKey(const Key('streak_restore_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak_restore_popup')), findsNothing);
  });

  testWidgets('StreakRestorePopup renders expired state when 7-hour window has passed', (tester) async {
    final api = _MockApi(shields: 1);
    final provider = FlowProvider(service: FlowService(api: api, currentUserId: () => 'u1'), api: api);
    await provider.loadOverview();

    const expiredRecovery = StreakRecovery(
      eligible: false,
      streak: 0,
      missedDays: 1,
      cost: 1,
      shieldsAvailable: 1,
      canAfford: true,
      expired: true,
      reason: 'recovery_expired',
      secondsRemaining: 0,
      adsRequired: 5,
      adsProgress: 0,
      canRestoreWithAds: false,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<FlowProvider>.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => StreakRestorePopup.show(context, expiredRecovery),
                child: const Text('Open Expired'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Expired'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('streak_restore_popup')), findsOneWidget);
    expect(find.text('Streak recovery expired'), findsOneWidget);
    expect(find.text('The 7-hour recovery window has expired. Complete a task today to start a fresh streak!'), findsOneWidget);
    expect(find.byKey(const Key('streak_restore_countdown')), findsNothing);
    expect(find.byKey(const Key('streak_restore_button')), findsNothing);
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.byKey(const Key('streak_restore_dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('streak_restore_popup')), findsNothing);
  });

  testWidgets('Profile tab displays Shield balance and Get More Shields opens wallet popup', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final api = _MockApi(shields: 2);
    final provider = FlowProvider(service: FlowService(api: api, currentUserId: () => 'u1'), api: api);
    await provider.loadOverview();
    await provider.loadWallet();

    final appState = AppStateProvider();
    appState.setCurrentUserForTesting(const AuthUser(
      id: 'u1',
      email: 'tester@flowstate.local',
      name: 'Tester',
      onboardingCompleted: true,
    ));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<FlowProvider>.value(value: provider),
        ],
        child: const MaterialApp(
          home: ProfileSettingsTab(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify profile section
    expect(find.byKey(const Key('profile_shields_section')), findsOneWidget);
    expect(find.text('2 Shields Available'), findsOneWidget);
    expect(find.byKey(const Key('profile_get_shields_button')), findsOneWidget);

    // Tap Get More Shields
    await tester.tap(find.byKey(const Key('profile_get_shields_button')));
    await tester.pumpAndSettle();

    // Popup opens
    expect(find.byKey(const Key('shield_wallet_popup')), findsOneWidget);
    expect(find.text('Your Shields'), findsOneWidget);
  });

  testWidgets('Replan with 0 Shields triggers insufficient_shields error and opens ShieldWalletPopup', (tester) async {
    final api = _MockApi(shields: 0, returnInsufficientShieldsOnReplan: true);
    final appState = AppStateProvider(customApi: api);
    final flowProvider = FlowProvider(service: FlowService(api: api, currentUserId: () => 'u1'), api: api);
    await flowProvider.loadOverview();
    await flowProvider.loadWallet();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<FlowProvider>.value(value: flowProvider),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showReplanDaySheet(context, selectedDate: DateTime(2026, 10, 9)),
                child: const Text('Open Replan'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Replan'));
    await tester.pumpAndSettle();

    final input = find.byKey(const Key('replan_composer'));
    expect(input, findsOneWidget);
    await tester.enterText(input, 'Move my morning meetings to 2pm');
    await tester.pumpAndSettle();

    final send = find.byKey(const Key('replan_send'));
    expect(send, findsOneWidget);
    await tester.tap(send);
    await tester.pumpAndSettle();

    // ShieldWalletPopup should be opened immediately
    expect(find.byKey(const Key('shield_wallet_popup')), findsOneWidget);
    expect(find.text("Oh no, you're out of Shields!"), findsOneWidget);
    expect(find.text('0 Shields'), findsOneWidget);
  });
}
