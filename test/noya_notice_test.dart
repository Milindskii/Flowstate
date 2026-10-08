import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_notice.dart';

void main() {
  group('policy: Noya is used sparingly', () {
    test('a burst of small successes shows Noya once, then plain text', () {
      final p = NoyaNoticePolicy();
      final t0 = DateTime(2026, 10, 8, 12);
      expect(p.useNoya(NoticeKind.success, t0), isTrue);
      expect(p.useNoya(NoticeKind.success, t0.add(const Duration(seconds: 5))), isFalse);
      expect(p.useNoya(NoticeKind.questComplete, t0.add(const Duration(seconds: 30))), isFalse);
      expect(p.useNoya(NoticeKind.success, t0.add(const Duration(seconds: 50))), isTrue);
    });

    test('milestones always get Noya', () {
      final p = NoyaNoticePolicy();
      final t0 = DateTime(2026, 10, 8, 12);
      expect(p.useNoya(NoticeKind.success, t0), isTrue);
      expect(p.useNoya(NoticeKind.milestone, t0.add(const Duration(seconds: 1))), isTrue);
    });

    test('each kind has its own mood', () {
      expect(const NoyaNotice(NoticeKind.milestone, 'x').noya, NoyaState.cheering);
      expect(const NoyaNotice(NoticeKind.questComplete, 'x').noya, NoyaState.goodJob);
      expect(const NoyaNotice(NoticeKind.success, 'x').noya, NoyaState.proud);
      expect(const NoyaNotice(NoticeKind.reminder, 'x').noya, NoyaState.encouraging);
    });
  });

  group('milestoneFromSession announces one thing, only when it matters', () {
    test('nothing special -> no notice', () {
      expect(milestoneFromSession({'leveled_up': false, 'streak_incremented': false, 'current_streak': 2}), isNull);
    });
    test('level up', () {
      final n = milestoneFromSession({'leveled_up': true, 'new_level': 7})!;
      expect(n.kind, NoticeKind.milestone);
      expect(n.message, contains('7'));
    });
    test('evolution beats level up beats shield beats streak', () {
      final all = {'leveled_up': true, 'evolution_ready': true, 'new_level': 5, 'shield_awarded': true,
        'streak_incremented': true, 'current_streak': 7};
      expect(milestoneFromSession(all)!.message, contains('evolve'));
      expect(milestoneFromSession({...all, 'evolution_ready': false})!.title, 'Level up');
      expect(milestoneFromSession({...all, 'evolution_ready': false, 'leveled_up': false})!.title, 'Shield earned');
      expect(milestoneFromSession({...all, 'evolution_ready': false, 'leveled_up': false, 'shield_awarded': false})!.title, 'Streak');
    });
    test('an ordinary streak day is not announced', () {
      expect(milestoneFromSession({'streak_incremented': true, 'current_streak': 4}), isNull);
    });
  });

  testWidgets('center shows Noya for the first notice and plain text inside the cooldown', (tester) async {
    var now = DateTime(2026, 10, 8, 12);
    final center = NoyaNoticeCenter(clock: () => now);
    await tester.pumpWidget(MaterialApp(
      scaffoldMessengerKey: center.messengerKey,
      home: const Scaffold(body: SizedBox()),
    ));
    center.show(const NoyaNotice(NoticeKind.success, 'Saved', title: 'Routine saved'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Routine saved'), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsOneWidget);

    now = now.add(const Duration(seconds: 3));
    center.show(const NoyaNotice(NoticeKind.success, 'Also saved', title: 'Plan confirmed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Plan confirmed'), findsOneWidget);
    expect(find.byType(NoyaCompanionView), findsNothing);
  });
}
