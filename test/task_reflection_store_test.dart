import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/task_reflection.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

TaskItem _task(String id, {DateTime? start}) => TaskItem(
      id: id,
      title: 'Gym',
      durationMinutes: 60,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Fitness',
      taskType: TaskType.physical,
      scheduledStart: start,
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  test('recordTaskFeedback keeps every reflection signal the user entered', () async {
    final start = DateTime(2026, 10, 3, 7);
    final state = AppStateProvider()..setTasksForTesting([_task('t1', start: start)]);
    await state.reflectionsReady;

    state.recordTaskFeedback(
      taskId: 't1',
      actualMinutes: 52,
      feeling: 4,
      energyScore: 4,
      focusScore: 5,
      difficultyScore: 3,
      distractionScore: 1,
      durationFeedback: 'shorter',
      blockerNote: 'none',
      completedAt: DateTime(2026, 10, 3, 8, 5),
    );

    final r = state.reflectionFor('t1')!;
    expect(r.feeling, 4);
    expect((r.energy, r.focus, r.difficulty, r.distraction), (4, 5, 3, 1));
    expect(r.durationFeedback, 'shorter');
    expect(r.note, 'none');
    expect(r.actualMinutes, 52);
    expect(r.plannedMinutes, 60);
    expect(r.plannedStart, start);
    expect(r.completedAt, DateTime(2026, 10, 3, 8, 5));
    expect(r.title, 'Gym');

    // Calendar items carry "sched-" / "comp-" ids; lookups resolve to the task.
    expect(state.reflectionFor('sched-t1'), same(r));
    expect(state.reflectionFor('comp-t1'), same(r));

    // The learning engine now receives the real signals instead of defaults.
    final log = state.learningEngine.history.last;
    expect(log.energyScore, 4);
    expect(log.difficultyScore, 3);
    expect(log.distractionScore, 1);
  });

  test('reflections persist on this device across provider instances', () async {
    final first = AppStateProvider()..setTasksForTesting([_task('t1')]);
    await first.reflectionsReady;
    first.recordTaskFeedback(taskId: 't1', actualMinutes: 30, feeling: 2, energyScore: 2, focusScore: 3, difficultyScore: 4, distractionScore: 3);
    await first.reflectionsSaved;

    final second = AppStateProvider();
    await second.reflectionsReady;
    final r = second.reflectionFor('t1');
    expect(r, isNotNull);
    expect((r!.feeling, r.energy, r.focus, r.difficulty, r.distraction), (2, 2, 3, 4, 3));
  });

  test('completing a task stamps its real completion time', () {
    final state = AppStateProvider()..setTasksForTesting([_task('t1')]);
    final before = DateTime.now();
    state.toggleTaskCompletion('t1');
    final done = state.tasks.firstWhere((t) => t.id == 't1');
    expect(done.isCompleted, isTrue);
    expect(done.completedAt, isNotNull);
    expect(done.completedAt!.isBefore(before.subtract(const Duration(seconds: 1))), isFalse);
  });

  test('TaskReflection round-trips through JSON', () {
    final r = TaskReflection(
      taskId: 'a',
      title: 'Study',
      feeling: 3,
      energy: 3,
      focus: 4,
      difficulty: 2,
      distraction: 2,
      completedAt: DateTime(2026, 10, 2, 18, 30),
      actualMinutes: 45,
      plannedMinutes: 40,
      plannedStart: DateTime(2026, 10, 2, 17, 45),
      durationFeedback: 'about_right',
      note: 'Felt good',
    );
    final back = TaskReflection.fromJson(r.toJson());
    expect(back.toJson(), r.toJson());
  });
}
