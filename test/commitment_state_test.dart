import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/engines/task_state.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

// A commitment ("Going out 6:30-8:30") is a fixed block: visible everywhere, never work. Mirrors the backend
// rules in backend/tests/test_commitments.py.
TaskItem task(String id, {DateTime? start, DateTime? planned, bool commitment = false, int minutes = 30}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: minutes,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'General',
      status: TaskStatus.todo,
      scheduledStart: start,
      scheduledEnd: start?.add(Duration(minutes: minutes)),
      plannedDate: planned,
      timeLocked: commitment,
      isCommitment: commitment,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  test('a commitment is never missed or failed, whatever the clock says', () {
    final start = DateTime(2026, 10, 5, 18, 30), end = DateTime(2026, 10, 5, 20, 30);
    final boundary = DateTime(2026, 10, 5, 23);
    TaskState at(DateTime now, {bool commitment = true}) => deriveTaskState(
        completed: false, cancelled: false, active: false, start: start, end: end, now: now,
        dayBoundary: boundary, commitment: commitment);
    expect(at(DateTime(2026, 10, 5, 17)), TaskState.commitment);
    expect(at(DateTime(2026, 10, 5, 21)), TaskState.commitment);
    expect(at(DateTime(2026, 10, 5, 23, 30)), TaskState.commitment);
    expect(at(DateTime(2026, 10, 5, 21), commitment: false), TaskState.missed); // a normal task still is
  });

  test('is_commitment survives parse and round trip on the day view and the task', () {
    final r = DayScheduleResponse.fromJson({
      'date': '2026-10-05',
      'timeline': [
        {
          'id': 'sched-c', 'task_id': 'c', 'title': 'Going out', 'time': '6:30', 'period': 'PM',
          'start_time': '2026-10-05T18:30:00+05:30', 'end_time': '2026-10-05T20:30:00+05:30',
          'duration_minutes': 120, 'type': 'personal', 'tag_text': 'FIXED', 'is_fixed': true,
          'time_locked': true, 'is_commitment': true, 'state': 'commitment',
        }
      ],
    });
    final it = r.timeline.single;
    expect(it.isCommitment, isTrue);
    expect(it.state, 'commitment');
    expect(ScheduleItem.fromJson(it.toJson()).isCommitment, isTrue);
    // re-deriving never turns it into missed
    final later = it.withDerivedState(now: DateTime(2026, 10, 5, 22), bedtimeHours: 23);
    expect(later.state, 'commitment');
    expect(later.isMissed, isFalse);
    expect(later.isFailed, isFalse);
    expect(ScheduleItem.fromJson({'id': 'x', 'title': 'x', 'time': '1:00', 'period': 'PM', 'type': 'a', 'tag_text': 'A'}).isCommitment, isFalse);
  });

  test('the preview candidate carries the flag to the task and the confirm payload', () {
    final c = ExtractedTaskItem.fromJson({
      'title': 'Going out', 'task_type': 'personal', 'estimated_minutes': 120, 'priority': 'medium',
      'scheduled_start': '2026-10-05T18:30:00+05:30', 'scheduled_end': '2026-10-05T20:30:00+05:30',
      'time_locked': true, 'is_commitment': true, 'candidate_id': 'c_1',
    });
    final t = c.toTaskItem();
    expect(t.isCommitment, isTrue);
    expect(t.timeLocked, isTrue);
    expect(TaskItem.fromJson(t.toJson()).isCommitment, isTrue);
  });

  test('a commitment is not remaining work, not missed work, and never leads do-this-now', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = task('out', start: now.subtract(const Duration(minutes: 10)), planned: today, commitment: true, minutes: 120);
    final work = task('work', planned: today, minutes: 45);
    final state = AppStateProvider()..setTasksForTesting([out, work]);
    expect(state.recommendedTask?.id, 'work');
    expect(state.workloadSummary.plannedMinutes, 45);
    expect(state.workloadSummary.missedMinutes, 0);
    state.setTasksForTesting([out]);
    expect(state.recommendedTask?.id, isNot('out'));
    expect(state.workloadSummary.plannedMinutes, 0);
  });

  test('a passed commitment is not missed in the calendar schedule', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = task('out', start: now.subtract(const Duration(hours: 5)), planned: today, commitment: true, minutes: 120);
    final state = AppStateProvider()..setTasksForTesting([out]);
    final items = state.buildLocalScheduleForTesting(today);
    final it = items.firstWhere((i) => i.taskId == 'out');
    expect(it.isCommitment, isTrue);
    expect(it.isMissed, isFalse);
    expect(it.isFailed, isFalse);
    expect(it.state, 'commitment');
  });

  test('complete, skip and do-this-now ignore a commitment', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final out = task('out', start: now.add(const Duration(hours: 1)), planned: today, commitment: true, minutes: 120);
    final work = task('work', planned: today);
    final state = AppStateProvider()..setTasksForTesting([out, work]);
    state.toggleTaskCompletion('out');
    expect(state.tasks.firstWhere((t) => t.id == 'out').isCompleted, isFalse);
    state.toggleTaskCompletion('sched-out');
    state.skipTask('out');
    state.setPreferredActiveTask('out');
    expect(state.tasks.firstWhere((t) => t.id == 'out').isCompleted, isFalse);
    expect(state.skippedTaskIds.contains('out'), isFalse);
    expect(state.recommendedTask?.id, 'work');
  });
}
