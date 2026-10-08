import '../engines/task_state.dart';
import 'task_item.dart';
import 'task_reflection.dart';

/// Whether a task was finished on the day it belonged to.
enum HistoryTiming { onTime, early, late }

/// One finished task as it is remembered: when it was done, how long it took, how it felt.
class HistoryEntry {
  final String taskId;
  final String title;
  final String? category;
  final DateTime completedAt;

  /// The day the task BELONGED TO (planned day, else its slot's day, else the day it was completed): the day History
  /// files it under. [completedAt] is when it was actually ticked off and may fall on another day.
  final DateTime day;

  /// Recorded session length when the user reflected, otherwise the task's planned length; 0 when neither is known
  /// (nothing is invented). This is the length of the TASK, not Focus time: Focus time is only real Focus sessions.
  final int minutes;
  final int? plannedMinutes;
  final TaskReflection? reflection;

  const HistoryEntry({
    required this.taskId,
    required this.title,
    required this.category,
    required this.completedAt,
    required this.day,
    required this.minutes,
    required this.plannedMinutes,
    required this.reflection,
  });

  /// Done before (early) or after (late) the day it belonged to, by calendar day.
  HistoryTiming get timing {
    final done = DateTime(completedAt.year, completedAt.month, completedAt.day);
    if (done.isBefore(day)) return HistoryTiming.early;
    if (done.isAfter(day)) return HistoryTiming.late;
    return HistoryTiming.onTime;
  }
}

/// What happened to a planned task that was NOT finished: the user chose to skip it, or its slot passed without it.
enum HistoryOutcome { skipped, missed }

/// One planned task that was not done on its day. [dayOver] separates a slot that passed while the day is still open
/// (recoverable, "Missed") from one the day ended on ("Not done").
class HistoryMiss {
  final String taskId;
  final String title;
  final String? category;
  final DateTime day;
  final DateTime? plannedStart;
  final int plannedMinutes;
  final HistoryOutcome outcome;
  final bool dayOver;

  const HistoryMiss({
    required this.taskId,
    required this.title,
    required this.category,
    required this.day,
    required this.plannedStart,
    required this.plannedMinutes,
    required this.outcome,
    required this.dayOver,
  });

  String get label => outcome == HistoryOutcome.skipped ? 'Skipped' : (dayOver ? 'Not done' : 'Missed');
}

/// A day the user finished something (or planned something and did not), oldest entry first.
class HistoryDay {
  final DateTime date;
  final List<HistoryEntry> entries;

  /// Planned work that was skipped on purpose or missed, in planned order. Never counted as finished.
  final List<HistoryMiss> unfinished;

  const HistoryDay({required this.date, required this.entries, this.unfinished = const []});

  int get skippedCount => unfinished.where((m) => m.outcome == HistoryOutcome.skipped).length;
  int get missedCount => unfinished.where((m) => m.outcome == HistoryOutcome.missed).length;

  int get totalMinutes => entries.fold(0, (sum, e) => sum + e.minutes);

  List<TaskReflection> get reflections => [for (final e in entries) if (e.reflection != null) e.reflection!];

  /// Mean feeling (1–4) across the day's reflections, or null when nobody reflected.
  double? get averageFeeling {
    final r = reflections;
    if (r.isEmpty) return null;
    return r.fold<int>(0, (sum, x) => sum + x.feeling) / r.length;
  }

  /// Minutes over (+) or under (−) plan across reflections that recorded both lengths.
  int? get minutesVersusPlan {
    final pairs = [
      for (final r in reflections)
        if ((r.plannedMinutes ?? 0) > 0 && r.actualMinutes > 0) r.actualMinutes - r.plannedMinutes!,
    ];
    if (pairs.isEmpty) return null;
    return pairs.fold<int>(0, (a, b) => a + b);
  }

  /// Groups finished work by the day it BELONGED TO, newest day first (the planned day, like Calendar and Today: a
  /// task done early is not today's history, and one done late is not tomorrow's). A reflection's completion time
  /// wins over the task's for the time shown; finished tasks without any recorded time cannot be placed and are skipped.
  ///
  /// With [now] the days also carry what was planned and not done: a task the user skipped ([skippedOn]: task id ->
  /// the day it was skipped on) and a task whose slot ended unfinished (derived from the clock and [bedtimeHours] with
  /// the same rule as Calendar, so the two always agree). Missed work stays on its planned day; it is never moved or
  /// counted as finished.
  static List<HistoryDay> from({
    required List<TaskItem> tasks,
    required List<TaskReflection> reflections,
    DateTime? now,
    double bedtimeHours = 23.0,
    Map<String, DateTime> skippedOn = const {},
  }) {
    final byTask = {for (final r in reflections) r.taskId: r};
    final entries = <String, HistoryEntry>{};
    for (final t in tasks.where((t) => t.isCompleted)) {
      final r = byTask[t.id];
      final at = r?.completedAt ?? t.completedAt ?? t.scheduledStart;
      if (at == null) continue;
      entries[t.id] = HistoryEntry(
        taskId: t.id,
        title: t.title,
        category: t.category.isEmpty || t.category.toLowerCase() == 'general' ? null : t.category,
        completedAt: at,
        day: t.owningDate ?? DateTime(at.year, at.month, at.day),
        minutes: r != null && r.actualMinutes > 0 ? r.actualMinutes : (t.durationMinutes > 0 ? t.durationMinutes : 0),
        plannedMinutes: r?.plannedMinutes ?? t.durationMinutes,
        reflection: r,
      );
    }
    // Reflections whose task is no longer in the list (deleted, or another device's cache).
    for (final r in reflections) {
      entries.putIfAbsent(
        r.taskId,
        () => HistoryEntry(
          taskId: r.taskId,
          title: r.title,
          category: null,
          completedAt: r.completedAt,
          day: DateTime(r.completedAt.year, r.completedAt.month, r.completedAt.day), // the task is gone: nothing else is known
          minutes: r.actualMinutes > 0 ? r.actualMinutes : (r.plannedMinutes ?? 0),
          plannedMinutes: r.plannedMinutes,
          reflection: r,
        ),
      );
    }

    final days = <DateTime, List<HistoryEntry>>{};
    for (final e in entries.values) {
      days.putIfAbsent(e.day, () => []).add(e);
    }

    final misses = <DateTime, List<HistoryMiss>>{};
    if (now != null) {
      HistoryMiss miss(TaskItem t, DateTime day, HistoryOutcome outcome, bool dayOver) => HistoryMiss(
            taskId: t.id,
            title: t.title,
            category: t.category.isEmpty || t.category.toLowerCase() == 'general' ? null : t.category,
            day: day,
            plannedStart: t.scheduledStart,
            plannedMinutes: t.durationMinutes,
            outcome: outcome,
            dayOver: dayOver,
          );
      for (final t in tasks) {
        if (t.isCompleted || t.isCommitment) continue;
        if (t.status == TaskStatus.cancelled || t.status == TaskStatus.archived) continue;
        final skipDay = skippedOn[t.id];
        if (skipDay != null) {
          final d = DateTime(skipDay.year, skipDay.month, skipDay.day);
          misses.putIfAbsent(d, () => []).add(miss(t, d, HistoryOutcome.skipped, true));
        }
        final start = t.scheduledStart;
        final owning = t.owningDate;
        if (start == null || owning == null) continue;
        final state = deriveSlotState(
          completed: false,
          cancelled: false,
          active: t.isActive,
          start: start,
          end: t.scheduledEnd ?? start.add(Duration(minutes: t.durationMinutes)),
          now: now,
          bedtimeHours: bedtimeHours,
        );
        if (state == TaskState.missed || state == TaskState.failed) {
          misses.putIfAbsent(owning, () => []).add(miss(t, owning, HistoryOutcome.missed, state == TaskState.failed));
        }
      }
    }

    final dates = {...days.keys, ...misses.keys}.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final d in dates)
        HistoryDay(
          date: d,
          entries: (days[d] ?? <HistoryEntry>[])..sort((a, b) => a.completedAt.compareTo(b.completedAt)),
          unfinished: (misses[d] ?? <HistoryMiss>[])
            ..sort((a, b) => (a.plannedStart ?? d).compareTo(b.plannedStart ?? d)),
        ),
    ];
  }
}
