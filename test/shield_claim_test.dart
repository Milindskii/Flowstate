import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/shield_recovery_dialog.dart';
import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/models/flow_profile.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_service.dart';

/// A fake server that behaves like the real one: the streak Shield can be activated once per day per account.
class _Server extends ApiService {
  int shields;
  bool activeToday = false;
  int usePosts = 0;
  DateTime? refillAt;
  DateTime serverNow = DateTime.utc(2026, 10, 8, 12);
  Completer<void>? hold;

  _Server({this.shields = 2});

  @override
  bool get isAuthenticated => true;

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    final json = FlowOverview.defaultInitial(userId: 'acct-a').toJson();
    final p = json['profile'] as Map<String, dynamic>;
    p['shields_available'] = shields;
    p['shield_active_today'] = activeToday;
    p['shield_max'] = 3;
    p['shield_refill_at'] = refillAt?.toIso8601String();
    p['server_now'] = serverNow.toIso8601String();
    return json;
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint.endsWith('/flow/shields/use')) {
      usePosts++;
      if (hold != null) await hold!.future;
      if (activeToday || shields <= 0) throw const ApiException('Flow Shield already active for today.');
      activeToday = true;
      shields -= 1;
      return {'success': true, 'shields_available': shields, 'current_streak': 4, 'shield_active_today': true};
    }
    return <String, dynamic>{};
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FlowProvider> loaded(_Server server) async {
    final p = FlowProvider(service: FlowService(api: server, currentUserId: () => 'acct-a'), api: server);
    await p.loadOverview();
    return p;
  }

  Future<void> openDialog(WidgetTester tester, FlowProvider flow) async {
    await tester.pumpWidget(ChangeNotifierProvider<FlowProvider>.value(
      value: flow,
      child: MaterialApp(
        home: Builder(builder: (context) {
          return Scaffold(
            body: Center(
              child: TextButton(onPressed: () => ShieldRecoveryDialog.show(context), child: const Text('open')),
            ),
          );
        }),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('repeated taps on Activate send ONE request; the action is then unavailable', (tester) async {
    final server = _Server()..hold = Completer<void>();
    final flow = await loaded(server);
    await openDialog(tester, flow);
    expect(find.byKey(const Key('shield_activate_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('shield_activate_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('shield_activate_button')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('shield_activate_button')), warnIfMissed: false);
    server.hold!.complete();
    await tester.pumpAndSettle();

    expect(server.usePosts, 1);
    expect(flow.profile.shieldActiveToday, isTrue);
    expect(flow.profile.shieldsAvailable, 1, reason: 'the balance is the server\'s answer');

    // the action is gone: opening again shows it as active, and a direct call sends nothing
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('shield_active_today')), findsOneWidget);
    expect(find.byKey(const Key('shield_activate_button')), findsNothing);
    expect(await flow.useStreakShield(), isFalse);
    expect(server.usePosts, 1);
  });

  testWidgets('after a restart the server still says active: no second activation is offered', (tester) async {
    final server = _Server()..activeToday = true;
    final flow = await loaded(server); // a fresh provider: an app restart or another device
    await openDialog(tester, flow);
    expect(find.byKey(const Key('shield_active_today')), findsOneWidget);
    expect(find.byKey(const Key('shield_activate_button')), findsNothing);
  });

  testWidgets('a refusal (already active elsewhere) re-reads the account and grants nothing', (tester) async {
    final server = _Server();
    final flow = await loaded(server);
    server.activeToday = true; // activated from another device meanwhile
    expect(await flow.useStreakShield(), isFalse);
    await tester.pump();
    await flow.loadOverview();
    expect(flow.profile.shieldActiveToday, isTrue);
    expect(flow.profile.shieldsAvailable, 2, reason: 'nothing was spent or created');
  });

  testWidgets('balance, maximum and the next free Shield come from the server clock', (tester) async {
    final server = _Server(shields: 1)
      ..refillAt = DateTime.utc(2026, 10, 11, 2, 5)
      ..serverNow = DateTime.utc(2026, 10, 8, 12);
    final flow = await loaded(server);
    await openDialog(tester, flow);
    expect(find.text('🛡️ 1 / 3 Shields'), findsOneWidget);
    expect(find.textContaining('Next Shield in 2d 14h'), findsOneWidget);
  });

  test('a wrong device clock cannot shorten the countdown', () {
    final p = FlowProfile.fromJson({
      'user_id': 'a',
      'shields_available': 1,
      'shield_refill_at': '2026-10-11T12:00:00Z',
      'server_now': '2026-10-08T12:00:00Z',
    });
    // the device thinks it is a year later: the wait is still measured from the server's own instant
    expect(p.untilNextShieldAt(p.readAt!.add(const Duration(seconds: 1)))!.inHours, 71);
    expect(p.untilNextShieldAt(DateTime(2027))!, Duration.zero, reason: 'never negative, never a new Shield');
  });
}
