import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/insights_snapshot.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/task_reflection.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

/// Insights only says what the history supports: a pattern needs enough finished tasks, on enough different days,
/// with a clear leader. A single busy morning is not "you get the most done in the morning". And a duration is only
/// a duration when something measured it.
// Saturday 3 October 2026, 18:00. The week starts Monday 28 September.
final _now = DateTime(2026, 10, 3, 18);

TaskItem done(String id, DateTime at, {DateTime? planned}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isCompleted: true,
      completedAt: at,
      plannedDate: planned,
      taskType: TaskType.deepWork,
    );

TaskReflection reflection(String id, DateTime at, int focus) => TaskReflection(
      taskId: id,
      title: id,
      feeling: 3,
      energy: 3,
      focus: focus,
      difficulty: 3,
      distraction: 1,
      completedAt: at,
      actualMinutes: 60,
      plannedMinutes: 60,
    );

List<String> claims(List<TaskItem> tasks) =>
    InsightsSnapshot.compute(tasks: tasks, reflections: const [], now: _now).learnings.map((l) => l.id).toList();

void main() {
  group('"you get the most done in the morning"', () {
    test('6 of 6 tasks ticked off in ONE morning is not a pattern', () {
      final tasks = [for (var i = 0; i < 6; i++) done('t$i', DateTime(2026, 10, 3, 9, i * 10))];
      final s = InsightsSnapshot.compute(tasks: tasks, reflections: const [], now: _now);
      expect(s.windowCounts[DayWindow.morning], 6);
      expect(s.bestWindow, isNull);
      expect(s.learnings.map((l) => l.id), isNot(contains('best_window')));
    });

    test('8 morning finishes across only 2 days is still not enough days', () {
      final tasks = [
        for (var i = 0; i < 4; i++) done('a$i', DateTime(2026, 10, 1, 9, i * 10)),
        for (var i = 0; i < 4; i++) done('b$i', DateTime(2026, 10, 2, 9, i * 10)),
      ];
      expect(claims(tasks), isNot(contains('best_window')));
    });

    test('7 finishes across 3 days is below the minimum count', () {
      final tasks = [
        for (var i = 0; i < 3; i++) done('a$i', DateTime(2026, 9, 29, 9, i * 10)),
        for (var i = 0; i < 2; i++) done('b$i', DateTime(2026, 9, 30, 9, i * 10)),
        for (var i = 0; i < 2; i++) done('c$i', DateTime(2026, 10, 1, 9, i * 10)),
      ];
      expect(claims(tasks), isNot(contains('best_window')));
    });

    test('8 finishes over 3 days, morning clearly ahead: reported, with the days behind it', () {
      final tasks = [
        for (var i = 0; i < 3; i++) done('a$i', DateTime(2026, 9, 29, 9, i * 10)),
        for (var i = 0; i < 3; i++) done('b$i', DateTime(2026, 9, 30, 10, i * 10)),
        done('c0', DateTime(2026, 10, 1, 9)),
        done('c1', DateTime(2026, 10, 1, 19)),
      ];
      final s = InsightsSnapshot.compute(tasks: tasks, reflections: const [], now: _now);
      expect(s.bestWindow, DayWindow.morning);
      final l = s.learnings.firstWhere((l) => l.id == 'best_window');
      expect(l.text, 'You get the most done in the morning.');
      expect(l.evidence, '7 of 8 finished tasks over 3 days landed between 5 AM – 12 PM.');
    });

    test('a leader with less than half of the finishes is not a pattern', () {
      final tasks = [
        for (var i = 0; i < 3; i++) done('m$i', DateTime(2026, 9, 29 + i, 9)), // 3 morning
        for (var i = 0; i < 2; i++) done('a$i', DateTime(2026, 9, 29 + i, 14)), // 2 afternoon
        for (var i = 0; i < 2; i++) done('e$i', DateTime(2026, 9, 29 + i, 19)), // 2 evening
        done('n0', DateTime(2026, 10, 1, 23)), // 1 night
      ];
      expect(claims(tasks), isNot(contains('best_window')));
    });

    test('a narrow lead (1 task) over the runner-up is not a pattern', () {
      final tasks = [
        for (var i = 0; i < 4; i++) done('m$i', DateTime(2026, 9, 28 + i, 9)),
        for (var i = 0; i < 3; i++) done('e$i', DateTime(2026, 9, 28 + i, 19)),
        done('a0', DateTime(2026, 10, 1, 14)),
      ];
      expect(claims(tasks), isNot(contains('best_window')));
    });

    test('with too little history there is no claim at all', () {
      expect(claims([done('a', DateTime(2026, 10, 3, 9))]), isEmpty);
      expect(claims(const []), isEmpty);
    });
  });

  group('days follow the planned day, like History', () {
    test('work planned for tomorrow and done today does not make today\'s bar taller', () {
      final s = InsightsSnapshot.compute(
        tasks: [done('a', DateTime(2026, 10, 3, 11), planned: DateTime(2026, 10, 4))],
        reflections: const [],
        now: _now,
      );
      expect(s.weekCounts[5], 0, reason: 'Saturday (today) did not own it');
      expect(s.weekCounts[6], 1, reason: 'Sunday (planned) did');
    });
  });

  group('completing a task feeds the numbers', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => FlowClock().stopTimer());

    test('totals move as soon as a task is completed', () async {
      const open = TaskItem(
        id: 'a',
        title: 'a',
        durationMinutes: 60,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        taskType: TaskType.deepWork,
      );
      final state = AppStateProvider()..setTasksForTesting([open]);
      await state.reflectionsReady;
      final before = InsightsSnapshot.compute(tasks: state.tasks, reflections: state.reflections, now: DateTime.now());
      expect(before.totalCompletions, 0);
      state.toggleTaskCompletion('a');
      final after = InsightsSnapshot.compute(tasks: state.tasks, reflections: state.reflections, now: DateTime.now());
      expect(after.totalCompletions, 1);
    });
  });

  group('a duration counts only when it was measured', () {
    setUp(() {
      FlowClock.enableAutoTick = false;
      FlowClock().stopTimer();
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => FlowClock().stopTimer());

    Future<AppStateProvider> reflect({required bool measured}) async {
      final tasks = [for (var i = 0; i < 4; i++) done('t$i', DateTime(2026, 10, 1 + i % 3, 9 + i))];
      final state = AppStateProvider()..setTasksForTesting(tasks);
      await state.reflectionsReady;
      for (var i = 0; i < 4; i++) {
        state.recordTaskFeedback(
          taskId: 't$i',
          actualMinutes: 60, // what a screen passes: here, simply the planned 60 minutes
          feeling: 3,
          energyScore: 3,
          focusScore: 3,
          difficultyScore: 3,
          distractionScore: 1,
          completedAt: DateTime(2026, 10, 1 + i % 3, 9 + i),
          durationMeasured: measured,
        );
      }
      return state;
    }

    test('feedback without a measured duration stores no duration (it would only echo the plan)', () async {
      final state = await reflect(measured: false);
      expect(state.reflections.every((r) => r.actualMinutes == 0), isTrue);
      final s = InsightsSnapshot.compute(tasks: state.tasks, reflections: state.reflections, now: _now);
      expect(s.plannedVsActual, isNull);
      expect(s.learnings.map((l) => l.id), isNot(contains('estimates')));
      expect(s.durationPairs, isEmpty);
    });

    test('a duration the Focus timer measured is kept and can support the estimates claim', () async {
      final state = await reflect(measured: true);
      expect(state.reflections.every((r) => r.actualMinutes == 60), isTrue);
      final s = InsightsSnapshot.compute(tasks: state.tasks, reflections: state.reflections, now: _now);
      expect(s.plannedVsActual, isNotNull);
    });
  });

  group('focus by part of day needs several days', () {
    test('reflections from a single day are not a "your focus is sharpest" claim', () {
      final reflections = [
        reflection('m1', DateTime(2026, 10, 1, 9), 5),
        reflection('m2', DateTime(2026, 10, 1, 10), 5),
        reflection('e1', DateTime(2026, 10, 1, 19), 2),
        reflection('e2', DateTime(2026, 10, 1, 20), 2),
      ];
      final s = InsightsSnapshot.compute(tasks: const [], reflections: reflections, now: _now);
      expect(s.learnings.map((l) => l.id), isNot(contains('focus_window')));
      expect(s.mostFocusedWindow, isNull);
    });
  });
}
