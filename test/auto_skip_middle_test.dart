import 'package:flowstate/engines/auto_skip.dart';
import 'package:flowstate/models/history_days.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Auto-skip closes in every open stop between two done stops (A, C done -> B; A, D done -> B and C), kept in place.
/// Mirrors backend/tests/test_complete_skips_bypassed.py.
void main() {
  // tomorrow, so no slot has ended whenever the test runs (an ended slot is missed, never auto-skipped)
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

  TaskItem stop(String id, int hour, {bool done = false, TaskStatus? status, bool commitment = false}) => TaskItem(
        id: id,
        title: id,
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'General',
        isCompleted: done,
        status: status ?? (done ? TaskStatus.completed : TaskStatus.todo),
        isCommitment: commitment,
        scheduledStart: day.add(Duration(hours: hour)),
        scheduledEnd: day.add(Duration(hours: hour, minutes: 30)),
      );

  test('A done, B open, C done -> B is auto-skipped', () {
    final a = stop('A', 9, done: true), b = stop('B', 10), c = stop('C', 11, done: true), d = stop('D', 12);
    expect(autoSkippedMiddleIds([a, b, c, d], c, now), {'B'});
  });

  test('A done, B and C open, D done -> B and C are both auto-skipped', () {
    final a = stop('A', 9, done: true), b = stop('B', 10), c = stop('C', 11), d = stop('D', 12, done: true);
    expect(autoSkippedMiddleIds([a, b, c, d, stop('E', 13)], d, now), {'B', 'C'});
  });

  test('a longer run: A done, B C D open, E done -> B, C and D', () {
    final tasks = [stop('A', 9, done: true), stop('B', 10), stop('C', 11), stop('D', 12), stop('E', 13, done: true)];
    expect(autoSkippedMiddleIds(tasks, tasks.last, now), {'B', 'C', 'D'});
  });

  test('a run with nothing done on the far side is not closed in', () {
    final a = stop('A', 9), b = stop('B', 10), c = stop('C', 11, done: true), d = stop('D', 12);
    expect(autoSkippedMiddleIds([a, b, c, d], c, now), isEmpty);
  });

  test('closing in from the other side: C done first, then A, still leaves B in the middle', () {
    final a = stop('A', 9, done: true), b = stop('B', 10), c = stop('C', 11, done: true);
    expect(autoSkippedMiddleIds([a, b, c], a, now), {'B'});
  });

  test('the completion being stored counts as done even before the list is updated', () {
    final a = stop('A', 9, done: true), b = stop('B', 10), c = stop('C', 11);
    expect(autoSkippedMiddleIds([a, b, c], c, now), {'B'});
  });

  test('the first stop of a day is never in the middle', () {
    final a = stop('A', 9), b = stop('B', 10, done: true), c = stop('C', 11);
    expect(autoSkippedMiddleIds([a, b, c], b, now), isEmpty);
  });

  test('in-progress tasks, commitments and ended slots are never auto-skipped', () {
    final a = stop('A', 9, done: true), c = stop('C', 11, done: true);
    expect(autoSkippedMiddleIds([a, stop('B', 10, status: TaskStatus.inProgress), c], c, now), isEmpty);
    // a commitment is not a stop: A and C are then direct neighbours and nothing is left in between
    expect(autoSkippedMiddleIds([a, stop('M', 10, commitment: true), c], c, now), isEmpty);
    final later = now.add(const Duration(days: 2));
    expect(autoSkippedMiddleIds([a, stop('B', 10), c], c, later), isEmpty, reason: 'B ended: it is missed');
  });

  test('un-completing C restores auto-skipped B to Open; a B still closed in stays auto-skipped', () {
    final a = stop('A', 9, done: true), b = stop('B', 10), c = stop('C', 11, done: true);
    expect(autoSkipsToRestore([a, b, c], c, {'B'}), {'B'});
    // A done, B auto-skipped, C done, D auto-skipped, E done: un-completing E frees D only
    final d = stop('D', 12), e = stop('E', 13, done: true);
    expect(autoSkipsToRestore([a, b, c, d, e], e, {'B', 'D'}), {'D'});
    // a whole run: A done, B C D auto-skipped, E done; un-completing E frees all three
    final run = [a, stop('B', 10), stop('C', 11), stop('D', 12), e];
    expect(autoSkipsToRestore(run, e, {'B', 'C', 'D'}), {'B', 'C', 'D'});
  });

  test('History keeps auto-skipped apart from skipped and missed, and never counts it twice', () {
    final past = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
    TaskItem open(String id, int hour) => TaskItem(
          id: id,
          title: id,
          durationMinutes: 30,
          difficulty: TaskDifficulty.medium,
          deadline: 'Today',
          category: 'General',
          plannedDate: past,
          scheduledStart: past.add(Duration(hours: hour)),
          scheduledEnd: past.add(Duration(hours: hour, minutes: 30)),
        );
    final days = HistoryDay.from(
      tasks: [open('B', 10), open('S', 11), open('M', 12)],
      reflections: const [],
      now: now,
      skippedOn: {'S': past},
      autoSkippedOn: {'B': past},
    );
    final outcomes = {for (final m in days.single.unfinished) m.taskId: m.outcome};
    expect(outcomes['B'], HistoryOutcome.autoSkipped);
    expect(outcomes['M'], HistoryOutcome.missed);
    expect(days.single.unfinished.where((m) => m.taskId == 'B'), hasLength(1));
    expect(days.single.unfinished.firstWhere((m) => m.taskId == 'B').label, 'Auto-skipped');
  });
}
