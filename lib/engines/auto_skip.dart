import '../models/task_item.dart';
import 'task_state.dart';

/// The deviation kind of an auto-skipped stop. Its own state: not an explicit "skipped" (which moves the task), not
/// "missed" (the clock) and not completed.
const String autoSkippedDeviation = 'auto_skipped';

/// The open stops that finishing [done] closes in: every open stop in a run between two done stops, on either side
/// of [done], in planned order on its day. Mirrors `bypassed_open_tasks` on the server.
///
/// A done, B open, C done -> B. A done, B and C open, D done -> B and C. The first and last stops of a day are never
/// closed in. Commitments and unslotted tasks are not stops here. A task being worked on keeps its state, and a slot
/// that already ended is missed and stays missed; either still belongs to the run. Skipped stops keep their slots.
Set<String> autoSkippedMiddleIds(List<TaskItem> tasks, TaskItem done, DateTime now) {
  if (done.isCommitment) return const {};
  final stops = _dayStops(tasks, done);
  final at = stops.indexWhere((t) => t.id == done.id);
  if (at == -1) return const {};
  bool isDone(int i) => stops[i].isCompleted || stops[i].id == done.id;
  bool isOpen(TaskItem t) {
    if (t.isCompleted || (t.status != TaskStatus.todo && t.status != TaskStatus.postponed)) return false;
    final end = t.scheduledEnd ?? t.scheduledStart!.add(Duration(minutes: t.durationMinutes));
    return !slotHasEnded(end, now);
  }

  final ids = <String>{};
  for (final step in const [-1, 1]) {
    final run = <int>[];
    var i = at + step;
    while (i >= 0 && i < stops.length && !isDone(i)) {
      run.add(i);
      i += step;
    }
    if (i < 0 || i >= stops.length) continue; // the run reaches the day's edge: nothing closes it in
    for (final j in run) {
      if (isOpen(stops[j])) ids.add(stops[j].id);
    }
  }
  return ids;
}

/// Un-completing [reopened] can undo auto-skips: the ids in [autoSkipped] on its day that are no longer between two
/// done stops (they go back to Open). Mirrors `restore_auto_skipped` on the server.
Set<String> autoSkipsToRestore(List<TaskItem> tasks, TaskItem reopened, Set<String> autoSkipped) {
  final stops = _dayStops(tasks, reopened);
  bool isDone(int i) => stops[i].isCompleted && stops[i].id != reopened.id;
  bool closedIn(int i) =>
      [for (var j = i - 1; j >= 0; j--) j].any(isDone) && [for (var j = i + 1; j < stops.length; j++) j].any(isDone);
  return {
    for (var i = 0; i < stops.length; i++)
      if (autoSkipped.contains(stops[i].id) && !closedIn(i)) stops[i].id,
  };
}

/// The planned stops (non-commitment, slotted, not cancelled) of [anchor]'s local day, in planned order.
List<TaskItem> _dayStops(List<TaskItem> tasks, TaskItem anchor) {
  final start = anchor.scheduledStart?.toLocal();
  if (start == null) return const [];
  bool sameDay(DateTime d) => d.year == start.year && d.month == start.month && d.day == start.day;
  return [
    for (final t in tasks)
      if (t.scheduledStart != null &&
          !t.isCommitment &&
          t.status != TaskStatus.cancelled &&
          t.status != TaskStatus.archived &&
          sameDay(t.scheduledStart!.toLocal()))
        t,
  ]..sort((a, b) => a.scheduledStart!.compareTo(b.scheduledStart!));
}
