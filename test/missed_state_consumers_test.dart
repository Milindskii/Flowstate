import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/engines/task_state.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

/// Today, the Calendar and "do this now" must agree on what is missed (shared/task_state_vectors.json).
/// FlowClock follows the device clock, so every slot here is placed relative to now.
TaskItem _task(String id, DateTime start, int minutes, {bool priority = false, bool done = false}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: minutes,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isPriority: priority,
      isCompleted: done,
      scheduledStart: start,
      scheduledEnd: start.add(Duration(minutes: minutes)),
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
  });
  tearDown(() => FlowClock().stopTimer());

  test('the local day schedule marks a task missed the moment its slot ends (not 15 min after it starts)', () async {
    final now = FlowClock().now;
    // starts 10 min ago, lasts 5: it ended 5 minutes ago. The old start+15 rule said "not missed yet".
    final start = now.subtract(const Duration(minutes: 10));
    final app = AppStateProvider()..setDemoMode(true);
    app.setTasksForTesting([_task('ended', start, 5)]);
    await app.loadCalendarDay(DateTime(start.year, start.month, start.day));
    final item = app.selectedDateSchedule!.timeline.singleWhere((i) => i.taskId == 'ended');
    final boundary = dayBoundary(start, app.personalData.bedtimeHour);
    final expected = now.isBefore(boundary) ? 'missed' : 'failed';
    expect(item.state, expected);
    expect(item.isMissed, expected == 'missed');
    expect(item.isFailed, expected == 'failed');
  });

  test('a task still inside its slot is neither missed nor failed', () async {
    final now = FlowClock().now;
    final start = now.subtract(const Duration(minutes: 5));
    final app = AppStateProvider()..setDemoMode(true);
    app.setTasksForTesting([_task('running-slot', start, 60)]);
    await app.loadCalendarDay(DateTime(start.year, start.month, start.day));
    final item = app.selectedDateSchedule!.timeline.singleWhere((i) => i.taskId == 'running-slot');
    expect(item.state, 'scheduled');
    expect(item.isMissed || item.isFailed, false);
  });

  test('"do this now" never recommends a task whose slot ended, even the most urgent one', () {
    final now = FlowClock().now;
    final app = AppStateProvider();
    app.setTasksForTesting([
      _task('ended-urgent', now.subtract(const Duration(minutes: 40)), 20, priority: true),
      _task('upcoming', now.add(const Duration(minutes: 5)), 30),
    ]);
    expect(app.recommendedTask?.id, 'upcoming');
  });

  test('only missed tasks means no recommendation', () {
    final now = FlowClock().now;
    final app = AppStateProvider();
    app.setTasksForTesting([_task('ended', now.subtract(const Duration(minutes: 40)), 20)]);
    expect(app.recommendedTask, isNull);
  });

  group('local workload (offline/demo fallback) = what can still be done', () {
    AppStateProvider seeded(List<TaskItem> tasks) => AppStateProvider()..setTasksForTesting(tasks);

    test('a task inside its slot counts as remaining', () {
      final now = FlowClock().now;
      final w = seeded([_task('in-slot', now.subtract(const Duration(minutes: 10)), 60)]).workloadSummary;
      expect((w.plannedMinutes, w.missedMinutes, w.missedCount), (60, 0, 0));
    });

    test('a completed task does not count', () {
      final now = FlowClock().now;
      final w = seeded([_task('done', now.subtract(const Duration(hours: 3)), 45, done: true)]).workloadSummary;
      expect((w.plannedMinutes, w.missedMinutes), (0, 0));
    });

    test('a missed task leaves remaining workload but its minutes are kept apart', () {
      final now = FlowClock().now;
      final w = seeded([_task('slipped', now.subtract(const Duration(hours: 3)), 45)]).workloadSummary;
      expect(w.plannedMinutes, 0);
      expect((w.missedMinutes, w.missedCount), (45, 1));
      expect(w.message, isNot("Let's build your day."));
    });

    test('a future task counts', () {
      final now = FlowClock().now;
      final w = seeded([_task('later', now.add(const Duration(hours: 3)), 30)]).workloadSummary;
      expect((w.plannedMinutes, w.missedMinutes), (30, 0));
    });

    test('a rescheduled/recovered task counts again at its new occurrence', () {
      final now = FlowClock().now;
      final app = seeded([_task('recovered', now.subtract(const Duration(hours: 3)), 45)]);
      expect((app.workloadSummary.plannedMinutes, app.workloadSummary.missedMinutes), (0, 45));
      app.setTasksForTesting([_task('recovered', now.add(const Duration(hours: 2)), 45)]); // Replan moved its slot
      expect((app.workloadSummary.plannedMinutes, app.workloadSummary.missedMinutes), (45, 0));
    });
  });
}
