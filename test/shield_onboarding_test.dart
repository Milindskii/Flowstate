import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/noya_notice.dart';
import 'package:flowstate/components/shield_welcome_card.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/services/ai_plan_service.dart';
import 'package:flowstate/services/api_service.dart';

AIUsageStatus _status({bool pending = true, int shields = 2}) => AIUsageStatus.fromJson({
      'is_pro': false,
      'shields_available': shields,
      'shield_cost': 1,
      'shield_welcome_pending': pending,
    });

class _RecordingApi extends ApiService {
  final List<String> posts = [];
  bool fail = false;

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    posts.add(endpoint);
    if (fail) throw const ApiException('offline');
    return null;
  }
}

void main() {
  group('AIUsageStatus: Shields pay for AI, one simple rule', () {
    test('a bare answer means "no free plan, 1 Shield", never a hidden free trial', () {
      final s = AIUsageStatus.fromJson(const {});
      expect(s.freeUseAvailable, isFalse);
      expect(s.shieldCost, 1);
      expect(s.requiresShield, isTrue);
      expect(s.shieldWelcomePending, isFalse);
    });

    test('the server owns the price and the welcome flag', () {
      final s = AIUsageStatus.fromJson({'shield_cost': 1, 'shields_available': 2, 'shield_welcome_pending': true});
      expect((s.shieldCost, s.shieldsAvailable, s.shieldWelcomePending), (1, 2, true));
      expect(s.canAffordShieldPlan, isTrue);
      expect(AIUsageStatus.fromJson({'shields_available': 0}).canAffordShieldPlan, isFalse);
    });

    test('a plan result remembers that a Shield paid for it', () {
      expect(AIPlanResult.fromJson({'tasks': [], 'shield_consumed': true}).shieldConsumed, isTrue);
      expect(AIPlanResult.fromJson({'tasks': []}).shieldConsumed, isFalse);
    });
  });

  group('ShieldWelcomeCard (once per account)', () {
    Widget host(ShieldWelcomeCard card) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: card)));

    testWidgets('a brand-new account sees "2 Shields added", what a Shield does, two shields and a pointer', (tester) async {
      var seen = 0;
      await tester.pumpWidget(host(ShieldWelcomeCard(
        loadStatus: () async => _status(),
        markSeen: () async => seen++,
      )));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('shield_welcome_card')), findsOneWidget);
      expect(find.text("You're ready! 🛡️🛡️"), findsOneWidget);
      expect(find.text('2 Shields added.'), findsOneWidget);
      expect(find.text('Use 1 Shield when Noya builds your day for you.'), findsOneWidget);
      expect(find.byKey(const Key('shield_welcome_icon_0')), findsOneWidget);
      expect(find.byKey(const Key('shield_welcome_icon_1')), findsOneWidget);
      expect(find.byKey(const Key('shield_welcome_icon_2')), findsNothing);
      expect(find.byKey(const Key('shield_welcome_pointer')), findsOneWidget);
      expect(find.text('Noya can build your day here'), findsOneWidget);
      expect(seen, 1, reason: 'the server is told the moment it is shown, so a restart never shows it again');
    });

    testWidgets('it is told to the server exactly once, however often the screen rebuilds', (tester) async {
      var seen = 0;
      final card = ShieldWelcomeCard(loadStatus: () async => _status(), markSeen: () async => seen++);
      await tester.pumpWidget(host(card));
      await tester.pumpAndSettle();
      await tester.pumpWidget(host(card));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(seen, 1);
    });

    testWidgets('restart / login / another device: the server says it is no longer pending, so nothing shows', (tester) async {
      var seen = 0;
      await tester.pumpWidget(host(ShieldWelcomeCard(
        loadStatus: () async => _status(pending: false),
        markSeen: () async => seen++,
      )));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shield_welcome_card')), findsNothing);
      expect(seen, 0);
    });

    testWidgets('an unreachable server shows nothing and invents nothing', (tester) async {
      await tester.pumpWidget(host(ShieldWelcomeCard(loadStatus: () async => null, markSeen: () async {})));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shield_welcome_card')), findsNothing);
    });

    testWidgets('it can be dismissed, and it never blocks the screen', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            ShieldWelcomeCard(loadStatus: () async => _status(), markSeen: () async {}),
            TextButton(onPressed: () => tapped++, child: const Text('Build my day')),
          ]),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Build my day'));
      expect(tapped, 1, reason: 'the card does not sit over the app');

      await tester.tap(find.byKey(const Key('shield_welcome_dismiss')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shield_welcome_card')), findsNothing);
    });

    testWidgets('pressing Build my day (what it points at) dismisses it', (tester) async {
      final key = GlobalKey<ShieldWelcomeCardState>();
      await tester.pumpWidget(host(ShieldWelcomeCard(key: key, loadStatus: () async => _status(), markSeen: () async {})));
      await tester.pumpAndSettle();
      key.currentState!.dismiss();
      await tester.pump();
      expect(find.byKey(const Key('shield_welcome_card')), findsNothing);
    });

    testWidgets('the pointer nudges briefly and then rests (no endless animation)', (tester) async {
      await tester.pumpWidget(host(ShieldWelcomeCard(loadStatus: () async => _status(), markSeen: () async {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle(); // would time out if the arrow bounced forever
      expect(find.byKey(const Key('shield_welcome_pointer')), findsOneWidget);
    });

    testWidgets('reduced motion: the pointer simply rests', (tester) async {
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: host(ShieldWelcomeCard(loadStatus: () async => _status(), markSeen: () async {})),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('shield_welcome_pointer')), findsOneWidget);
    });
  });

  group('AIPlanService.markShieldWelcomeSeen', () {
    test('posts only to the dismiss route (it carries no balance) and never throws', () async {
      final api = _RecordingApi();
      await AIPlanService(api: api).markShieldWelcomeSeen();
      expect(api.posts, ['/api/v1/ai/shield-welcome/seen']);
      api.fail = true;
      await AIPlanService(api: api).markShieldWelcomeSeen(); // offline: silent
    });
  });

  group('Noya feedback does not repeat itself', () {
    test('the same notice from rapid taps or retries is shown once', () {
      var now = DateTime(2026, 10, 9, 9);
      final center = NoyaNoticeCenter(clock: () => now);
      const plan = NoyaNotice(NoticeKind.success, '1 Shield used.', title: 'Plan ready');
      expect(center.admit(plan), isTrue);
      now = now.add(const Duration(milliseconds: 300));
      expect(center.admit(plan), isFalse, reason: 'a double tap');
      now = now.add(const Duration(milliseconds: 900));
      expect(center.admit(plan), isFalse, reason: 'a retry inside the window');
      now = now.add(const Duration(seconds: 5));
      expect(center.admit(plan), isTrue, reason: 'a genuinely new event later');
      expect(center.shown.length, 2);
    });

    test('a small notice never pushes a reward off the screen right after it appeared', () {
      var now = DateTime(2026, 10, 9, 9);
      final center = NoyaNoticeCenter(clock: () => now);
      expect(center.admit(const NoyaNotice(NoticeKind.reward, 'Shield claimed! +1 🛡️')), isTrue);
      now = now.add(const Duration(milliseconds: 400));
      expect(center.admit(const NoyaNotice(NoticeKind.success, 'Plan created!')), isFalse);
    });

    test('the standard sentences', () {
      final center = NoyaNoticeCenter(clock: DateTime.now);
      center.success('1 Shield used.', title: 'Plan ready');
      expect(center.shown.single.message, '1 Shield used.');
    });
  });
}
