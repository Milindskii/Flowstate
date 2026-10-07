// Build My Day — conservative, lossless deterministic fallback (milestone 1).
//
// Mirrors backend/tests/test_conservative_fallback.py for the on-device
// parser that brain_dump_sheet.dart falls back to.
import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/services/task_parse_service.dart';

// Reconstructed from the fragments recorded in
// docs/superpowers/specs/build-my-day-intelligence-v2.md §4.1 / §26.1.
const benchmarkDump = "Tomorrow I have class at 12:40 PM. Leave home by 11:50 AM. "
    "I should finish my machine learning assignment because I need to submit it tomorrow before 11 AM. "
    "It will probably take around 90 minutes. "
    "I also want to fix a backend authentication bug in my project, which may take about 2 hours. "
    "I'd like to do that when I'm mentally fresh. "
    "I want to go to the gym around 6 PM and spend about an hour there. "
    "Review DSA for at least 45 minutes, preferably earlier in the day but it can be moved. "
    "Call my mom sometime in the evening, around 15 minutes. "
    "I also need to clean my room, which will take about 30 minutes, but this is low priority. "
    "Can be skipped if the day gets too full. "
    "Don't schedule tasks on top of each other. "
    "Keep enough travel/preparation time around class and gym. "
    "Prioritize assignment, class, backend bug, gym, and DSA in that order if there isn't enough time for everything.";

const _danglingEnd = {
  'about', 'around', 'for', 'at', 'by', 'take', 'takes', 'least', 'most', 'than',
  'the', 'a', 'an', 'to', 'and', 'or', 'but', 'which', 'is', 'of', 'with', 'sometime',
  'approximately', 'roughly', 'probably', 'spend',
};
final _dependentStart = RegExp(
  r'^(?:which|it|this|that|but|so|because|preferably|around|about|spend\s+about|can\s+be)\b',
  caseSensitive: false,
);
final _instruction = RegExp(
  r"\b(?:don'?t schedule|prioriti[sz]e|keep enough|in that order|on top of each other)\b",
  caseSensitive: false,
);

void expectWellFormed(String title) {
  final t = title.trim();
  expect(t, isNotEmpty);
  expect(RegExp(r'\s[.,;:!?]').hasMatch(t), isFalse, reason: 'broken prose: "$t"');
  expect(RegExp(r'[,;:]$').hasMatch(t), isFalse, reason: 'dangling punctuation: "$t"');
  final words = t.replaceAll(RegExp(r'[.!?]+$'), '').split(RegExp(r'\s+'));
  expect(_danglingEnd.contains(words.last.toLowerCase()), isFalse,
      reason: 'dangling final word: "$t"');
  expect(_dependentStart.hasMatch(t), isFalse, reason: 'orphan fragment: "$t"');
  expect(_instruction.hasMatch(t), isFalse, reason: 'instruction became a task: "$t"');
}

TaskItem find(List<TaskItem> tasks, List<String> words) {
  return tasks.firstWhere(
    (t) => words.every((w) => t.title.toLowerCase().contains(w)),
    orElse: () => throw TestFailure('no task with $words in ${tasks.map((t) => t.title).toList()}'),
  );
}

void main() {
  group('Benchmark brain dump', () {
    test('no fragments, no instruction tasks, no crash', () {
      final tasks = TaskParseService.deterministicFallbackParse(benchmarkDump);
      for (final t in tasks) {
        expectWellFormed(t.title);
      }
    });

    test('entity count is not fragmented (gold 8, fallback <= 1.3x)', () {
      final tasks = TaskParseService.deterministicFallbackParse(benchmarkDump);
      expect(tasks.length, inInclusiveRange(6, 10), reason: tasks.map((t) => t.title).join(' | '));
    });

    test('durations stay attached to their own task', () {
      final tasks = TaskParseService.deterministicFallbackParse(benchmarkDump);
      expect(find(tasks, ['assignment']).durationMinutes, 90);
      expect(find(tasks, ['authentication']).durationMinutes, 120);
      expect(find(tasks, ['gym']).durationMinutes, 60);
      expect(find(tasks, ['dsa']).durationMinutes, 45);
      expect(find(tasks, ['mom']).durationMinutes, 15);
      expect(find(tasks, ['room']).durationMinutes, 30);
    });

    test('attribute sentences attach to their task', () {
      final tasks = TaskParseService.deterministicFallbackParse(benchmarkDump);
      expect(find(tasks, ['room']).priority, TaskPriority.low);
      final gym = find(tasks, ['gym']);
      expect(gym.scheduledStart?.hour, 18);
      expect(gym.timeLocked, isFalse, reason: '"around 6 PM" must not lock gym');
    });

    test('durations are never clock times', () {
      final tasks = TaskParseService.deterministicFallbackParse(benchmarkDump);
      expect(find(tasks, ['mom']).scheduledStart?.hour, isNot(15));
      expect(find(tasks, ['assignment']).scheduledStart, isNull);
    });
  });

  group('Duration phrases', () {
    test('"probably take around 90 minutes" attaches to the previous task', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        'Finish my ML assignment. It will probably take around 90 minutes.',
      );
      expect(tasks.length, 1, reason: tasks.map((t) => t.title).join(' | '));
      expect(tasks.first.durationMinutes, 90);
      expect(tasks.first.scheduledStart, isNull);
      expectWellFormed(tasks.first.title);
      expect(tasks.first.title.toLowerCase(), contains('assignment'));
    });

    test('a lone duration sentence creates no task', () {
      expect(TaskParseService.deterministicFallbackParse('It will probably take around 90 minutes.'), isEmpty);
    });

    test('"around 1.5 hours" is a duration, not 1 o\'clock', () {
      final tasks = TaskParseService.deterministicFallbackParse('Write report around 1.5 hours');
      expect(tasks.single.durationMinutes, 90);
      expect(tasks.single.scheduledStart, isNull);
    });

    test('title keeps meaning when the duration is removed', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        'Review DSA for at least 45 minutes, preferably earlier in the day',
      );
      expect(tasks.single.durationMinutes, 45);
      expectWellFormed(tasks.single.title);
      expect(tasks.single.title.toLowerCase(), contains('dsa'));
    });
  });

  group('One intention -> one task', () {
    test('"and spend about an hour there" stays with the gym', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        'I want to go to the gym around 6 PM and spend about an hour there.',
      );
      expect(tasks.length, 1, reason: tasks.map((t) => t.title).join(' | '));
      expect(tasks.single.durationMinutes, 60);
      expectWellFormed(tasks.single.title);
    });

    test('a "which" clause is not a new task', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        'I also want to fix a backend bug in my project, which may take about 2 hours.',
      );
      expect(tasks.length, 1, reason: tasks.map((t) => t.title).join(' | '));
      expect(tasks.single.durationMinutes, 120);
    });

    test('a preference sentence is not a task', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        "Fix the login bug for 2 hours. I'd like to do that when I'm mentally fresh.",
      );
      expect(tasks.length, 1, reason: tasks.map((t) => t.title).join(' | '));
    });

    test('instruction sentences are not tasks', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        "Call the dentist. Don't schedule tasks on top of each other. Prioritize the dentist in that order.",
      );
      expect(tasks.map((t) => t.title).toList(), ['Call the dentist']);
    });

    test('a clause about other tasks does not raise priority', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        "I should clean my room too, but that's optional and shouldn't interfere with the important stuff.",
      );
      expect(tasks.length, 1, reason: tasks.map((t) => t.title).join(' | '));
      expect(tasks.single.priority, TaskPriority.low);
    });

    test('real lists still split', () {
      expect(TaskParseService.deterministicFallbackParse('gym and study and call dentist').length, 3);
      expect(
        TaskParseService.deterministicFallbackParse('finish my assignment, reply to Rahul and clean my room').length,
        3,
      );
    });

    test('"finish my assignment and submit it" stays one task', () {
      expect(TaskParseService.deterministicFallbackParse('finish my assignment and submit it').length, 1);
    });
  });
}
