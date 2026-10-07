import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/components/companion/flow_companion_animation_controller.dart';

void main() {
  late DateTime now;
  late NoyaReactionController c;

  void advance(int ms) => now = now.add(Duration(milliseconds: ms));

  setUp(() {
    now = DateTime(2026, 10, 2, 9, 0);
    c = NoyaReactionController(clock: () => now);
  });

  tearDown(() => c.dispose());

  group('priority (spec §5.3)', () {
    test('higher priority interrupts lower', () {
      expect(c.react(NoyaReaction.taskDone)?.reaction, NoyaReaction.taskDone);
      advance(200);
      expect(c.react(NoyaReaction.celebrate)?.reaction, NoyaReaction.celebrate);
      expect(c.value?.reaction, NoyaReaction.celebrate);
    });

    test('lower priority dropped during higher active window', () {
      c.react(NoyaReaction.celebrate);
      advance(500);
      expect(c.react(NoyaReaction.greet), isNull);
      expect(c.value?.reaction, NoyaReaction.celebrate);
    });

    test('lower priority allowed after the higher window ends (celebrate 3100 ms)', () {
      c.react(NoyaReaction.celebrate);
      advance(3200);
      expect(c.react(NoyaReaction.greet)?.reaction, NoyaReaction.greet);
    });

    test('recover outranks greet; greet cannot interrupt planReady', () {
      c.react(NoyaReaction.planReady);
      advance(100);
      expect(c.react(NoyaReaction.greet), isNull);
      expect(c.react(NoyaReaction.recover), isNull);
      advance(1400);
      expect(c.react(NoyaReaction.recover)?.reaction, NoyaReaction.recover);
    });
  });

  group('coalescing and caps', () {
    test('taskDone coalesces within 1.5 s', () {
      final emitted = <NoyaReactionEvent?>[];
      for (var i = 0; i < 5; i++) {
        emitted.add(c.react(NoyaReaction.taskDone));
        advance(200);
      }
      expect(emitted.whereType<NoyaReactionEvent>().length, 1);
    });

    test('taskDone after 1.5 s is a new event', () {
      final first = c.react(NoyaReaction.taskDone)!;
      advance(1600);
      final second = c.react(NoyaReaction.taskDone);
      expect(second, isNotNull);
      expect(second!.id, greaterThan(first.id));
    });

    test('4th celebrate in a day downgrades to taskDone', () {
      for (var i = 0; i < 3; i++) {
        expect(c.react(NoyaReaction.celebrate)?.reaction, NoyaReaction.celebrate);
        advance(4000);
      }
      expect(c.react(NoyaReaction.celebrate)?.reaction, NoyaReaction.taskDone);
    });

    test('celebrate count resets on next local day', () {
      for (var i = 0; i < 3; i++) {
        c.react(NoyaReaction.celebrate);
        advance(4000);
      }
      now = DateTime(2026, 10, 3, 9, 0);
      expect(c.react(NoyaReaction.celebrate)?.reaction, NoyaReaction.celebrate);
    });

    test('reactToTap limited to one per 2 s', () {
      expect(c.reactToTap()?.reaction, NoyaReaction.greet);
      advance(1900);
      expect(c.reactToTap(), isNull);
      advance(200);
      expect(c.reactToTap()?.reaction, NoyaReaction.greet);
    });
  });

  group('greetOnce', () {
    test('per screen per session', () {
      expect(c.greetOnce('flow_hub'), isTrue);
      expect(c.greetOnce('flow_hub'), isFalse);
      expect(c.greetOnce('calendar_empty'), isTrue);
    });

    test('perDay resets next day', () {
      expect(c.greetOnce('today_plate', perDay: true), isTrue);
      advance(60 * 60 * 1000);
      expect(c.greetOnce('today_plate', perDay: true), isFalse);
      now = DateTime(2026, 10, 3, 8, 0);
      expect(c.greetOnce('today_plate', perDay: true), isTrue);
    });
  });

  test('event ids strictly increase and listeners are notified per emitted event', () {
    var notified = 0;
    c.addListener(() => notified++);
    final a = c.react(NoyaReaction.greet)!;
    advance(2000);
    final b = c.react(NoyaReaction.recover)!;
    advance(1000);
    final d = c.react(NoyaReaction.taskDone)!;
    expect(a.id < b.id && b.id < d.id, isTrue);
    expect(notified, 3);
    expect(d.at, now);
  });

  test('FlowCompanionAnimationController owns a reactions controller and disposes it', () {
    final controller = FlowCompanionAnimationController();
    expect(controller.reactions, isA<NoyaReactionController>());
    controller.reactions.react(NoyaReaction.greet);
    controller.dispose();
    expect(() => controller.reactions.addListener(() {}), throwsFlutterError);
  });
}
