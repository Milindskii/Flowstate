import 'package:flutter_test/flutter_test.dart';

import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/models/insights_snapshot.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/task_reflection.dart';

// Saturday 3 October 2026, 18:00. The week starts Monday 28 September.
final _now = DateTime(2026, 10, 3, 18);

TaskItem _done(String id, DateTime? at, {TaskType type = TaskType.deepWork}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isCompleted: true,
      completedAt: at,
      taskType: type,
    );

TaskReflection _r(String id, DateTime at, {int feeling = 3, int energy = 3, int focus = 3, int difficulty = 3, int distraction = 1, int actual = 60, int? planned = 60}) =>
    TaskReflection(
      taskId: id,
      title: id,
      feeling: feeling,
      energy: energy,
      focus: focus,
      difficulty: difficulty,
      distraction: distraction,
      completedAt: at,
      actualMinutes: actual,
      plannedMinutes: planned,
    );

void main() {
  test('no history: nothing is invented, Noya is still getting to know you', () {
    final s = InsightsSnapshot.compute(tasks: const [], reflections: const [], now: _now);
    expect(s.hasAnyHistory, isFalse);
    expect(s.completionsThisWeek, 0);
    expect(s.bestWindow, isNull);
    expect(s.averages, isNull);
    expect(s.plannedVsActual, isNull);
    expect(s.noyaState, NoyaState.thinking);
  });

  test('week consistency counts only completions with a recorded time, per day of this week', () {
    final s = InsightsSnapshot.compute(
      tasks: [
        _done('a', DateTime(2026, 9, 28, 9)), // Mon
        _done('b', DateTime(2026, 9, 28, 14)), // Mon
        _done('c', DateTime(2026, 10, 1, 10)), // Thu
        _done('d', DateTime(2026, 10, 3, 8)), // Sat (today)
        _done('e', DateTime(2026, 9, 22, 9)), // last week
        _done('f', null), // no time recorded
      ],
      reflections: const [],
      now: _now,
    );
    expect(s.weekCounts, [2, 0, 0, 1, 0, 1, 0]);
    expect(s.completionsThisWeek, 4);
    expect(s.activeDaysThisWeek, 3);
    expect(s.completionsLastWeek, 1);
    expect(s.completionsWithoutTime, 1);
    expect(s.headline, '4 tasks finished across 3 days this week');
    expect(s.noyaState, NoyaState.proud);
  });

  test('a reflection time wins over the task time, and a task is counted once', () {
    final s = InsightsSnapshot.compute(
      tasks: [_done('a', DateTime(2026, 9, 28, 9))],
      reflections: [_r('a', DateTime(2026, 9, 29, 20))],
      now: _now,
    );
    expect(s.weekCounts, [0, 1, 0, 0, 0, 0, 0]);
    expect(s.completionsThisWeek, 1);
  });

  test('time-of-day pattern needs 3 timed completions and a clear leader', () {
    final few = InsightsSnapshot.compute(
      tasks: [_done('a', DateTime(2026, 10, 1, 9)), _done('b', DateTime(2026, 10, 2, 10))],
      reflections: const [],
      now: _now,
    );
    expect(few.bestWindow, isNull);

    final s = InsightsSnapshot.compute(
      tasks: [
        _done('a', DateTime(2026, 10, 1, 9)),
        _done('b', DateTime(2026, 10, 2, 10)),
        _done('c', DateTime(2026, 10, 2, 19)),
      ],
      reflections: const [],
      now: _now,
    );
    expect(s.windowCounts[DayWindow.morning], 2);
    expect(s.windowCounts[DayWindow.evening], 1);
    expect(s.bestWindow, DayWindow.morning);

    final tie = InsightsSnapshot.compute(
      tasks: [
        _done('a', DateTime(2026, 10, 1, 9)),
        _done('b', DateTime(2026, 10, 2, 19)),
        _done('c', DateTime(2026, 10, 2, 13)),
      ],
      reflections: const [],
      now: _now,
    );
    expect(tie.bestWindow, isNull);
  });

  test('reflection averages and planned-vs-actual appear only with 3+ reflections', () {
    final two = InsightsSnapshot.compute(
      tasks: const [],
      reflections: [_r('a', DateTime(2026, 10, 1, 9)), _r('b', DateTime(2026, 10, 1, 11))],
      now: _now,
    );
    expect(two.averages, isNull);
    expect(two.plannedVsActual, isNull);
    expect(two.reflectionsNeeded, 1);

    final s = InsightsSnapshot.compute(
      tasks: const [],
      reflections: [
        _r('a', DateTime(2026, 10, 1, 9), energy: 4, focus: 5, difficulty: 2, distraction: 1, actual: 50, planned: 40),
        _r('b', DateTime(2026, 10, 1, 10), energy: 4, focus: 4, difficulty: 3, distraction: 2, actual: 75, planned: 60),
        _r('c', DateTime(2026, 10, 2, 20), energy: 1, focus: 3, difficulty: 4, distraction: 3, actual: 30, planned: 30),
      ],
      now: _now,
    );
    expect(s.averages!.energy, closeTo(3.0, 0.01));
    expect(s.averages!.focus, closeTo(4.0, 0.01));
    expect(s.averages!.difficulty, closeTo(3.0, 0.01));
    expect(s.averages!.distraction, closeTo(2.0, 0.01));
    // Ratios 1.25, 1.25, 1.0 → median 1.25.
    expect(s.plannedVsActual, closeTo(1.25, 0.001));
    expect(s.plannedVsActualLabel, 'Tasks usually take about 25% longer than planned');
    // Focus averages 4.5 in the morning (2 reflections) vs 3 in the evening.
    expect(s.mostFocusedWindow, DayWindow.morning);
  });

  test('planned-vs-actual reads "about as planned" within ±10%', () {
    final s = InsightsSnapshot.compute(
      tasks: const [],
      reflections: [
        for (var i = 0; i < 3; i++) _r('r$i', DateTime(2026, 10, 1, 9 + i), actual: 62, planned: 60),
      ],
      now: _now,
    );
    expect(s.plannedVsActualLabel, 'Tasks usually take about as long as planned');
  });

  test('a quieter week than the last gets an encouraging Noya, not a proud one', () {
    final s = InsightsSnapshot.compute(
      tasks: [
        _done('a', DateTime(2026, 9, 22, 9)),
        _done('b', DateTime(2026, 9, 23, 9)),
        _done('c', DateTime(2026, 10, 1, 9)),
      ],
      reflections: const [],
      now: _now,
    );
    expect(s.noyaState, NoyaState.encouraging);
  });

  group('chart series', () {
    test('two-week columns and hour-of-day counts come from timed completions only', () {
      final s = InsightsSnapshot.compute(
        tasks: [
          _done('a', DateTime(2026, 9, 21, 9, 30)), // Monday last week
          _done('b', DateTime(2026, 10, 3, 9, 10)), // Saturday this week
          _done('c', DateTime(2026, 10, 3, 21)),
          _done('old', DateTime(2026, 9, 1, 9)), // outside the two weeks: hours only
          _done('untimed', null),
        ],
        reflections: const [],
        now: _now,
      );
      expect(s.fortnightCounts, [1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 0]);
      expect(s.hourCounts[9], 3);
      expect(s.hourCounts[21], 1);
      expect(s.timedCompletions, 4);
    });

    test('duration pairs are the newest reflections with both times; series is chronological', () {
      final s = InsightsSnapshot.compute(
        tasks: const [],
        reflections: [
          _r('late', DateTime(2026, 10, 3, 9), actual: 90, planned: 60),
          _r('early', DateTime(2026, 10, 1, 9), actual: 30, planned: 45),
          _r('noplan', DateTime(2026, 10, 2, 9), planned: null),
        ],
        now: _now,
      );
      expect(s.durationPairs.map((p) => p.title), ['late', 'early']);
      expect(s.durationPairs.first.actual, 90);
      expect(s.series.map((r) => r.taskId), ['early', 'noplan', 'late']);
    });

    test('follow-through counts only planned slots that have already ended', () {
      TaskItem planned(String id, DateTime start, bool done) => TaskItem(
            id: id, title: id, durationMinutes: 60, difficulty: TaskDifficulty.medium, deadline: 'Today',
            category: 'Work', isCompleted: done, scheduledStart: start,
          );
      final tasks = [
        for (var i = 0; i < 4; i++) planned('d$i', DateTime(2026, 10, 1, 9 + i), true),
        planned('open', DateTime(2026, 10, 2, 9), false),
        planned('later', DateTime(2026, 10, 3, 17, 30), false), // still running at 18:00
        planned('ancient', DateTime(2026, 9, 1, 9), false),
      ];
      final s = InsightsSnapshot.compute(tasks: tasks, reflections: const [], now: _now);
      expect(s.plannedRecently, 5);
      expect(s.plannedRecentlyDone, 4);
      expect(s.hasFollowThrough, isTrue);
      expect(s.learnings.map((l) => l.id), contains('follow_through'));
      expect(s.learnings.firstWhere((l) => l.id == 'follow_through').evidence, '4 of 5 tasks planned in the last two weeks are finished.');
    });
  });

  group('what Flowstate learned', () {
    test('nothing is claimed without data', () {
      final s = InsightsSnapshot.compute(tasks: [_done('a', _now)], reflections: const [], now: _now);
      expect(s.learnings, isEmpty);
    });

    test('focus window is claimed only as a real comparison between parts of the day', () {
      final oneWindow = InsightsSnapshot.compute(
        tasks: const [],
        reflections: [for (var i = 0; i < 4; i++) _r('m$i', DateTime(2026, 10, 1 + i, 9), focus: 5)],
        now: _now,
      );
      expect(oneWindow.learnings.map((l) => l.id), isNot(contains('focus_window')));

      final s = InsightsSnapshot.compute(
        tasks: const [],
        reflections: [
          _r('m1', DateTime(2026, 10, 1, 9), focus: 5),
          _r('m2', DateTime(2026, 10, 2, 9), focus: 4),
          _r('e1', DateTime(2026, 10, 1, 19), focus: 2),
          _r('e2', DateTime(2026, 10, 2, 19), focus: 3),
        ],
        now: _now,
      );
      final l = s.learnings.firstWhere((l) => l.id == 'focus_window');
      expect(l.text, 'Your focus is sharpest in the morning.');
      expect(l.evidence, 'Focus 4.5/5 there vs 2.5/5 at other times.');
    });

    test('difficulty, energy→focus and distraction patterns need enough reflections', () {
      final s = InsightsSnapshot.compute(
        tasks: const [],
        reflections: [
          _r('h1', DateTime(2026, 10, 1, 9), difficulty: 5, feeling: 1, energy: 2, focus: 2),
          _r('h2', DateTime(2026, 10, 1, 11), difficulty: 4, feeling: 2, energy: 2, focus: 1),
          _r('e1', DateTime(2026, 10, 2, 9), difficulty: 2, feeling: 4, energy: 5, focus: 5),
          _r('e2', DateTime(2026, 10, 2, 11), difficulty: 2, feeling: 3, energy: 4, focus: 4),
          _r('e3', DateTime(2026, 10, 2, 14), difficulty: 1, feeling: 4, energy: 4, focus: 5),
        ],
        now: _now,
      );
      final ids = s.learnings.map((l) => l.id).toList();
      expect(ids, containsAll(['difficulty', 'energy_focus', 'distraction']));
      expect(s.learnings.firstWhere((l) => l.id == 'difficulty').text, 'Harder tasks tend to leave you drained.');
      expect(s.learnings.firstWhere((l) => l.id == 'distraction').text, 'Once you start, you rarely get distracted.');

      final few = InsightsSnapshot.compute(tasks: const [], reflections: s.series.take(4).toList(), now: _now);
      expect(few.learnings.map((l) => l.id), isNot(contains('energy_focus')));
    });
  });
}
