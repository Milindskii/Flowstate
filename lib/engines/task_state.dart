/// Derived task state: the Flutter half of the one rule shared with the backend
/// (backend/app/services/task_state.py). "Missed" and "failed" are never stored; they follow from the
/// stored slot, the clock and the user's sleep boundary, so a restart or a date change recomputes them.
///
/// shared/task_state_vectors.json pins both implementations: change a rule there and both suites must follow.
library;

/// A task is missed the moment its slot ends unstarted.
const int kMissedGraceMinutes = 0;

/// A bedtime earlier than 06:00 means after midnight (the next calendar day).
const double kBedtimeAfterMidnightBelowHours = 6.0;

enum TaskState { scheduled, missed, failed, active, completed, cancelled, unscheduled, commitment }

/// The one "slot ended" predicate (grace included), mirrored by the backend's `slot_has_ended`.
bool slotHasEnded(DateTime? end, DateTime now) =>
    end != null && !now.isBefore(end.add(const Duration(minutes: kMissedGraceMinutes)));

/// End of the allowed recovery window for the local day of [day]: the user's bedtime.
DateTime dayBoundary(DateTime day, double bedtimeHours) {
  final hours = bedtimeHours < kBedtimeAfterMidnightBelowHours ? bedtimeHours + 24.0 : bedtimeHours;
  return DateTime(day.year, day.month, day.day).add(Duration(minutes: (hours * 60).round()));
}

/// scheduled: not started and its slot has not ended (before, or inside, its time).
/// missed:    the slot ended unstarted and the recovery window is still open: recoverable.
/// failed:    the recovery window (the slot day's bedtime) is over.
TaskState deriveTaskState({
  required bool completed,
  required bool cancelled,
  required bool active,
  required DateTime? start,
  required DateTime? end,
  required DateTime now,
  required DateTime dayBoundary,
  bool commitment = false,
}) {
  // A fixed block (going out) is never work: never missed or failed, whatever the clock says.
  if (commitment) return TaskState.commitment;
  if (completed) return TaskState.completed;
  if (cancelled) return TaskState.cancelled;
  if (active) return TaskState.active;
  if (start == null || end == null) return TaskState.unscheduled;
  if (!slotHasEnded(end, now)) return TaskState.scheduled;
  return now.isBefore(dayBoundary) ? TaskState.missed : TaskState.failed;
}

/// Convenience for a task slot: the state of an unfinished/unstarted task at [now] for a user whose
/// bedtime is [bedtimeHours] (hours since midnight, e.g. 23.0).
TaskState deriveSlotState({
  required bool completed,
  required bool cancelled,
  required bool active,
  required DateTime? start,
  required DateTime? end,
  required DateTime now,
  required double bedtimeHours,
  bool commitment = false,
}) {
  final reference = start ?? now;
  return deriveTaskState(
    commitment: commitment,
    completed: completed,
    cancelled: cancelled,
    active: active,
    start: start,
    end: end,
    now: now,
    dayBoundary: dayBoundary(reference, bedtimeHours),
  );
}
