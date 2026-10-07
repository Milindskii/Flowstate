import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/calendar_world.dart';

/// The day's Trophy: the end of the road once the day is complete, claimed once for Noya's XP.
///
/// Completion is the server's verdict on the day (nothing live left open, at least one task done), which the
/// Calendar day carries; the client adds one guard of its own (never a Trophy beside an open task). The claim is
/// idempotent end to end: one in-flight request, none after it is claimed, and the server grants a day once.
final DateTime _day = () {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}();

const _user = AuthUser(id: 'user-trophy', email: 'trophy@flowstate.local', name: 'T', onboardingCompleted: true);

void main() {
  late CalendarWorld world;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    FlowClock.debugNowOverride = () => DateTime(_day.year, _day.month, _day.day, 20);
    SharedPreferences.setMockInitialValues({});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    world = CalendarWorld(_day);
  });
  tearDown(() {
    FlowClock.debugNowOverride = null;
    FlowClock().stopTimer();
  });

  Future<AppStateProvider> pump(WidgetTester tester, {AppStateProvider? reuse}) async {
    final provider = reuse ??
        AppStateProvider(customApi: ApiService(client: MockClient(world.handle)), initialUser: _user)
      ..setOnboardingCompleteForTesting(true);
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider<AppStateProvider>.value(value: provider)],
      child: const MaterialApp(home: CalendarTab()),
    ));
    await tester.pumpAndSettle();
    await provider.loadCalendarDay(provider.selectedCalendarDate);
    await tester.pumpAndSettle();
    return provider;
  }

  Finder trophy() => find.byKey(const Key('path_trophy'));
  Finder claim() => find.byKey(const Key('path_trophy_claim'));

  Future<void> showTrophy(WidgetTester tester) =>
      tester.scrollUntilVisible(trophy(), 200, scrollable: find.byType(Scrollable).first);

  Future<void> openSheet(WidgetTester tester) async {
    await showTrophy(tester);
    await tester.tap(trophy());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('path_trophy_sheet')), findsOneWidget);
  }

  group('when the Trophy appears', () {
    testWidgets('every task done: the Trophy is the last node of the road, below the last stop', (tester) async {
      world
        ..add('A', 9, done: true)
        ..add('B', 10, done: true);
      await pump(tester);
      await showTrophy(tester);
      expect(trophy(), findsOneWidget);
      final geo = (tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter).geometry;
      expect(geo.finish, isNotNull);
      final origin = tester.getTopLeft(find.byKey(const Key('flow_day_path_line')));
      final at = tester.getCenter(trophy()) - origin;
      expect(at.dx, closeTo(geo.finish!.center.dx, 0.5), reason: 'the Trophy sits on the road');
      expect(at.dy, closeTo(geo.finish!.center.dy, 0.5));
      expect(at.dy, greaterThan(tester.getCenter(find.byKey(const Key('path_stop_sched-B'))).dy - origin.dy));
      expect(geo.distanceToRoute(geo.finish!.center), lessThan(0.5));
      expect(find.text('Collect +25 XP'), findsOneWidget);
    });

    testWidgets('a task is still open: no Trophy', (tester) async {
      world
        ..add('A', 9, done: true)
        ..add('B', 10);
      await pump(tester);
      expect(trophy(), findsNothing);
    });

    testWidgets('the server says the day is not complete (eligible false): no Trophy, however the day looks', (tester) async {
      world.add('A', 9, done: true);
      // a future day can never be complete: only a day up to today can be
      world.tasks['A']!.day = 3;
      final provider = await pump(tester);
      await provider.loadCalendarDay(_day.add(const Duration(days: 3)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path_stop_sched-A')), findsOneWidget);
      expect(trophy(), findsNothing);
    });

    testWidgets('a day with nothing completed (only skipped history) gets no Trophy', (tester) async {
      world.add('A', 9);
      world.skippedFrom['A'] = 9;
      world.tasks['A']!.day = 1; // the skip moved it away; today only has its history node
      await pump(tester);
      expect(find.byKey(const Key('path_stop_sched-A')), findsOneWidget);
      expect(trophy(), findsNothing);
    });

    testWidgets('a skipped task moved to another day does not block the Trophy', (tester) async {
      world
        ..add('A', 9, done: true)
        ..add('B', 10);
      world.skippedFrom['B'] = 10;
      world.tasks['B']!.day = 1; // skipped off today
      await pump(tester);
      expect(find.byKey(const Key('path_skipped_sched-B')), findsOneWidget);
      expect(trophy(), findsOneWidget);
    });

    testWidgets('completing the last task from another screen brings the Trophy; before that there is none', (tester) async {
      world
        ..add('A', 9, done: true)
        ..add('B', 10);
      final provider = await pump(tester);
      expect(trophy(), findsNothing);

      provider.toggleTaskCompletion('B');
      await tester.pumpAndSettle();
      await showTrophy(tester);
      expect(trophy(), findsOneWidget);
    });

    testWidgets('adding a task to a finished day takes the Trophy away', (tester) async {
      world.add('A', 9, done: true);
      final provider = await pump(tester);
      expect(trophy(), findsOneWidget);
      world.add('B', 11);
      await provider.loadCalendarDay(provider.selectedCalendarDate, silent: true);
      await tester.pumpAndSettle();
      expect(trophy(), findsNothing);
    });
  });

  group('claiming', () {
    testWidgets('tapping the Trophy opens a compact sheet; claiming gives Noya the XP exactly once', (tester) async {
      world.add('A', 9, done: true);
      final provider = await pump(tester);
      await openSheet(tester);
      expect(find.text('+25 XP for Noya'), findsOneWidget);
      expect(tester.getSize(claim()).height, greaterThanOrEqualTo(48));

      await tester.tap(claim());
      await tester.pumpAndSettle();
      expect(world.claimPosts, 1);
      expect(world.xpAwardedTotal, 25);
      expect(find.text('+25 XP earned for Noya'), findsOneWidget);
      expect(claim(), findsNothing, reason: 'nothing left to claim');
      expect(provider.selectedDateSchedule!.dayComplete.claimed, isTrue);

      await tester.tap(find.byKey(const Key('path_trophy_done')));
      await tester.pumpAndSettle();
      expect(find.text('+25 XP collected'), findsOneWidget, reason: 'the node on the road shows it is collected');
    });

    testWidgets('repeated taps while the claim is out send one request', (tester) async {
      world.add('A', 9, done: true);
      await pump(tester);
      final gate = world.holdNextClaim = Completer<void>();
      await openSheet(tester);

      await tester.tap(claim());
      await tester.pump();
      expect(find.text('Claiming…'), findsOneWidget);
      await tester.tap(claim(), warnIfMissed: false); // the button is off while the request is out
      await tester.tap(claim(), warnIfMissed: false);
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(world.claimPosts, 1);
      expect(world.xpAwardedTotal, 25);
    });

    testWidgets('concurrent and repeated claim calls share one request and never double the XP', (tester) async {
      world.add('A', 9, done: true);
      final provider = await pump(tester);
      final gate = world.holdNextClaim = Completer<void>();
      final calls = [for (var i = 0; i < 3; i++) provider.claimDayComplete(provider.selectedCalendarDate)];
      await tester.pump();
      gate.complete();
      final results = await Future.wait(calls);
      expect(world.claimPosts, 1, reason: 'taps while a claim is in flight share it');
      expect(results.every((r) => r!['xp_awarded'] == 25), isTrue);

      final again = await provider.claimDayComplete(provider.selectedCalendarDate);
      expect(world.claimPosts, 1, reason: 'a day already claimed sends nothing');
      expect(again!['already_claimed'], isTrue);
      expect(again['xp_awarded'], 0);
      expect(world.xpAwardedTotal, 25);
    });

    testWidgets('a failed claim shows a retry; the retry pays once', (tester) async {
      world.add('A', 9, done: true);
      final provider = await pump(tester);
      await openSheet(tester);

      world.failNextClaim = true;
      await tester.tap(claim());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path_trophy_error')), findsOneWidget);
      expect(claim(), findsOneWidget, reason: 'still claimable');
      expect(world.xpAwardedTotal, 0);
      expect(provider.selectedDateSchedule!.dayComplete.claimed, isFalse);

      await tester.tap(claim());
      await tester.pumpAndSettle();
      expect(world.claimPosts, 2);
      expect(world.xpAwardedTotal, 25);
      expect(find.byKey(const Key('path_trophy_error')), findsNothing);
      expect(find.text('+25 XP earned for Noya'), findsOneWidget);
    });

    testWidgets('app restart: the claimed day stays claimed, and even a forced re-claim pays nothing more', (tester) async {
      world.add('A', 9, done: true);
      final first = await pump(tester);
      await openSheet(tester);
      await tester.tap(claim());
      await tester.pumpAndSettle();
      expect(world.xpAwardedTotal, 25);
      first.dispose();

      // a brand-new app session: no memory of the claim except what the server stores
      await tester.pumpWidget(const SizedBox.shrink());
      final restarted = await pump(tester);
      await showTrophy(tester);
      expect(find.text('+25 XP collected'), findsOneWidget);
      expect(restarted.selectedDateSchedule!.dayComplete.claimed, isTrue);
      await tester.tap(trophy());
      await tester.pumpAndSettle();
      expect(claim(), findsNothing, reason: 'the restarted app offers nothing to claim');
      expect(find.byKey(const Key('path_trophy_done')), findsOneWidget);

      final forced = await restarted.claimDayComplete(restarted.selectedCalendarDate);
      expect(forced!['already_claimed'], isTrue);
      expect(world.xpAwardedTotal, 25, reason: 'the server grants a day once');
    });
  });
}
