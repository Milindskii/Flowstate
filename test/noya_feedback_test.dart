import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_notice.dart';

/// The one app-wide feedback channel: success, failure, reward, milestone, info; toast vs card; no spam.
void main() {
  late DateTime now;
  late NoyaNoticeCenter center;

  setUp(() {
    now = DateTime(2026, 10, 8, 12);
    center = NoyaNoticeCenter(clock: () => now);
  });

  Future<void> host(WidgetTester tester) => tester.pumpWidget(MaterialApp(
        scaffoldMessengerKey: center.messengerKey,
        home: const Scaffold(body: SizedBox()),
      ));

  Future<void> show(WidgetTester tester, void Function() f) async {
    f();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('success: a small toast', (tester) async {
    await host(tester);
    await show(tester, () => center.success('Task completed!'));
    expect(find.text('Task completed!'), findsOneWidget);
    expect(find.byKey(const Key('noya_notice')), findsOneWidget);
    expect(find.byKey(const Key('noya_notice_card')), findsNothing);
  });

  testWidgets('failure: plain words and a clear icon, never Noya\'s celebration', (tester) async {
    await host(tester);
    await show(tester, () => center.failure("Couldn't complete that action. Try again."));
    expect(find.text("Couldn't complete that action. Try again."), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsNothing);
  });

  testWidgets('reward: the larger Noya card, with Noya', (tester) async {
    await host(tester);
    await show(tester, () => center.reward('+1 🛡️', title: 'Shield claimed!'));
    expect(find.text('Shield claimed!'), findsOneWidget);
    expect(find.byKey(const Key('noya_notice_card')), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsOneWidget);
  });

  testWidgets('info: a plain toast without Noya', (tester) async {
    await host(tester);
    await show(tester, () => center.info('Your day was replanned.'));
    expect(find.text('Your day was replanned.'), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsNothing);
  });

  test('identical messages collapse; the same words again after the window show again', () {
    const n = NoyaNotice(NoticeKind.success, 'Task completed!');
    expect(center.admit(n), isTrue);
    now = now.add(const Duration(seconds: 1));
    expect(center.admit(n), isFalse, reason: 'a rapid repeat');
    expect(center.admit(n), isFalse);
    now = now.add(const Duration(seconds: 5));
    expect(center.admit(n), isTrue);
    expect(center.shown, hasLength(2));
  });

  test('a trivial notice right after an important one does not push it away; a milestone always shows', () {
    expect(center.admit(const NoyaNotice(NoticeKind.reward, '+1 🛡️', title: 'Shield claimed!')), isTrue);
    now = now.add(const Duration(milliseconds: 300));
    expect(center.admit(const NoyaNotice(NoticeKind.success, 'Saved')), isFalse);
    expect(center.admit(const NoyaNotice(NoticeKind.milestone, 'Noya reached level 5.', title: 'Level up')), isTrue);
    now = now.add(const Duration(seconds: 2));
    expect(center.admit(const NoyaNotice(NoticeKind.success, 'Saved')), isTrue);
  });

  testWidgets('a burst of different small events shows one at a time and never blocks the screen', (tester) async {
    await host(tester);
    for (var i = 0; i < 5; i++) {
      center.success('Saved $i');
      now = now.add(const Duration(milliseconds: 100));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SnackBar), findsOneWidget, reason: 'newest replaces older, never a pile');
    expect(find.text('Saved 4'), findsOneWidget);
    // the screen under it stays interactive (a snack bar is not a modal)
    expect(find.byType(ModalBarrier).evaluate().where((e) => (e.widget as ModalBarrier).dismissible).isEmpty, isTrue);
  });

  testWidgets('quest reward is reported once however often the claim is tapped', (tester) async {
    await host(tester);
    for (var i = 0; i < 4; i++) {
      center.reward('+20 XP 🎉', title: 'Quest complete!');
      now = now.add(const Duration(milliseconds: 200));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Quest complete!'), findsOneWidget);
    expect(center.shown.where((n) => n.title == 'Quest complete!'), hasLength(1));
  });
}
