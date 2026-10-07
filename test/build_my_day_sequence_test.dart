import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/services/task_parse_service.dart';

/// "after that" / "then" are ordering constraints (manual verification 2026-10-06). The local
/// parser (the path short inputs take) must keep them as `dependsOn`, and the preview scheduler
/// must not place a task before the one it follows.
/// "Title<-[indexes of the tasks it follows]" per task, in order.
List<String> chain(List<TaskItem> tasks) {
  final index = {for (var i = 0; i < tasks.length; i++) tasks[i].id: i};
  return [for (final t in tasks) '${t.title}<-${[for (final d in t.dependsOn) index[d]!]}'];
}

void main() {
  group('sequencing phrases become dependencies', () {
    test('real input: "Do ml observation after that then stick pictures for cn observation"', () {
      final tasks = TaskParseService.deterministicFallbackParse(
          'Do ml observation after that then stick pictures for cn observation');
      expect(tasks.map((t) => t.title).toList(),
          ['Do ml observation', 'Stick pictures for cn observation']);
      expect(tasks[0].dependsOn, isEmpty);
      expect(tasks[1].dependsOn, [tasks[0].id]);
    });

    test('A -> "after that" B -> "then" C is a chain', () {
      final tasks = TaskParseService.deterministicFallbackParse(
          'Write report after that review slides then email professor');
      expect(chain(tasks), [
        'Write report<-[]',
        'Review slides<-[0]',
        'Email professor<-[1]',
      ]);
    });

    for (final text in [
      'Write report. Then review slides. After that email professor',
      'Write report, then review slides, and after that email professor',
      "Write report once that's done review slides following that email professor",
      'Write report and then review slides after that email professor',
    ]) {
      test('variant: $text', () {
        expect(chain(TaskParseService.deterministicFallbackParse(text)), [
          'Write report<-[]',
          'Review slides<-[0]',
          'Email professor<-[1]',
        ]);
      });
    }

    for (final text in [
      'Email professor after I finish the report, write report',
      "Email professor when I'm done with the report, write report",
      'Email professor once the report is done, write report',
      'After I finish the report, email professor. Write report',
    ]) {
      test('named predecessor: $text', () {
        final tasks = {for (final t in TaskParseService.deterministicFallbackParse(text)) t.title: t};
        expect(tasks.keys.toSet(), {'Email professor', 'Write report'});
        expect(tasks['Email professor']!.dependsOn, [tasks['Write report']!.id]);
        expect(tasks['Write report']!.dependsOn, isEmpty);
      });
    }

    test('a named predecessor that matches nothing invents no task and no dependency', () {
      final tasks = TaskParseService.deterministicFallbackParse(
          "Call mom when I'm done with the nonexistent thing");
      expect(tasks.length, 1);
      expect(tasks.single.dependsOn, isEmpty);
    });

    for (final (text, count) in [
      ('gym and work', 2),
      ('After dinner read book', 1),
      ('call mom after 5pm', 1),
      ('Study DBMS, go to the gym', 2),
    ]) {
      test('no sequencing in "$text" -> no dependencies', () {
        final tasks = TaskParseService.deterministicFallbackParse(text);
        expect(tasks.length, count);
        expect(tasks.every((t) => t.dependsOn.isEmpty), isTrue);
      });
    }

    test('titles keep no linker words', () {
      for (final t in TaskParseService.deterministicFallbackParse(
          'Do ml observation after that then stick pictures for cn observation')) {
        expect(t.title.toLowerCase().contains('after that'), isFalse);
        expect(RegExp(r'\bthen\b', caseSensitive: false).hasMatch(t.title), isFalse);
      }
    });
  });

  group('preview scheduling honours the order', () {
    DateTime shown(TaskItem t, DateTime now) {
      // "Today · 10:30 AM" / "Tomorrow · 9:30 AM" / "Oct 7 · 9:30 AM"
      final parts = t.recommendedSlotDisplay!.split(' · ');
      final time = DateFormat('h:mm a').parse(parts[1]);
      final day = parts[0] == 'Today'
          ? now
          : parts[0] == 'Tomorrow'
              ? now.add(const Duration(days: 1))
              : DateFormat('MMM d').parse(parts[0]).copyWith(year: now.year);
      return DateTime(day.year, day.month, day.day, time.hour, time.minute);
    }

    test('A before B before C, even when each would otherwise pick the same slot', () {
      final now = DateTime(2026, 10, 6, 8, 0);
      final parsed = TaskParseService.deterministicFallbackParse(
          'Write report after that review slides then email professor');
      final enriched = const SchedulingEngine().enrichTasksWithOptimalSlots(parsed, nowLocal: now);
      final starts = enriched.map((t) => shown(t, now)).toList();
      final dur = enriched.map((t) => Duration(minutes: t.durationMinutes > 0 ? t.durationMinutes : 45)).toList();
      expect(starts[1].isBefore(starts[0].add(dur[0])), isFalse, reason: '$starts');
      expect(starts[2].isBefore(starts[1].add(dur[1])), isFalse, reason: '$starts');
    });

    test('notBefore moves a slot that would start earlier', () {
      final now = DateTime(2026, 10, 6, 8, 0);
      const engine = SchedulingEngine();
      final task = TaskParseService.deterministicFallbackParse('Review slides').single;
      final free = engine.evaluateCandidateSlot(task, nowLocal: now);
      final gate = free.slotEnd.add(const Duration(hours: 2));
      final held = engine.evaluateCandidateSlot(task, nowLocal: now, notBefore: gate);
      expect(held.slotStart.isBefore(gate), isFalse);
    });
  });
}
