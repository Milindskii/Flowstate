import '../models/task_item.dart';

/// Which tasks make up TODAY's view, by the device's local date. Pure: the same rule drives the Today page
/// (active list, "Completed today · N", the all-done state) and the provider's lifecycle.
///
/// * completed today: done, and the moment it was done (else its slot, else its own day) falls on [now]'s date;
/// * open today: not done, not cancelled/archived, and it belongs to today (or to no day yet);
/// * a new day starts with an empty view: yesterday's finished tasks are not "today's" any more, but nothing is deleted
///   (History still reads them from the same task list).
class TodayCompletion {
  final List<TaskItem> completedToday; // most recently finished first
  final List<TaskItem> openToday;

  const TodayCompletion._(this.completedToday, this.openToday);

  /// Nothing planned or finished today: the empty day (distinct from a completed one).
  bool get isEmptyDay => completedToday.isEmpty && openToday.isEmpty;

  /// Something was planned today and every bit of it is done.
  bool get allDone => completedToday.isNotEmpty && openToday.isEmpty;

  static bool _sameDay(DateTime a, DateTime b) {
    final l = a.toLocal();
    return l.year == b.year && l.month == b.month && l.day == b.day;
  }

  static bool _inactive(TaskItem t) => t.status == TaskStatus.cancelled || t.status == TaskStatus.archived;

  /// [completedAtOf] supplies a better completion moment when one is known (e.g. the reflection the user saved).
  static TodayCompletion of(
    Iterable<TaskItem> tasks,
    DateTime now, {
    DateTime? Function(TaskItem task)? completedAtOf,
  }) {
    final done = <TaskItem>[];
    final open = <TaskItem>[];
    DateTime? doneAt(TaskItem t) => completedAtOf?.call(t) ?? t.completedAt ?? t.scheduledStart;
    for (final t in tasks) {
      if (_inactive(t)) continue;
      if (t.isCompleted) {
        final at = doneAt(t);
        final owning = t.owningDate;
        final today = at != null ? _sameDay(at, now) : (owning != null && _sameDay(owning, now));
        if (today) done.add(t);
      } else {
        final owning = t.owningDate;
        if (owning == null || _sameDay(owning, now)) open.add(t);
      }
    }
    done.sort((a, b) {
      final x = doneAt(a), y = doneAt(b);
      if (x == null || y == null) return x == null ? 1 : -1;
      return y.compareTo(x);
    });
    return TodayCompletion._(List.unmodifiable(done), List.unmodifiable(open));
  }
}
