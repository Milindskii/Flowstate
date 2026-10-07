import 'task_item.dart';
import 'task_reflection.dart';

/// One finished task as it is remembered: when it was done, how long it took, how it felt.
class HistoryEntry {
  final String taskId;
  final String title;
  final String? category;
  final DateTime completedAt;

  /// Recorded session length when the user reflected, otherwise the planned length.
  final int minutes;
  final int? plannedMinutes;
  final TaskReflection? reflection;

  const HistoryEntry({
    required this.taskId,
    required this.title,
    required this.category,
    required this.completedAt,
    required this.minutes,
    required this.plannedMinutes,
    required this.reflection,
  });
}

/// A day the user finished something, oldest entry first.
class HistoryDay {
  final DateTime date;
  final List<HistoryEntry> entries;

  const HistoryDay({required this.date, required this.entries});

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

  /// Groups finished work by local day, newest day first. A reflection's completion time wins
  /// over the task's; finished tasks without any recorded time cannot be placed and are skipped.
  static List<HistoryDay> from({required List<TaskItem> tasks, required List<TaskReflection> reflections}) {
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
        minutes: r != null && r.actualMinutes > 0 ? r.actualMinutes : (t.durationMinutes > 0 ? t.durationMinutes : 25),
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
          minutes: r.actualMinutes > 0 ? r.actualMinutes : (r.plannedMinutes ?? 0),
          plannedMinutes: r.plannedMinutes,
          reflection: r,
        ),
      );
    }

    final days = <DateTime, List<HistoryEntry>>{};
    for (final e in entries.values) {
      final d = DateTime(e.completedAt.year, e.completedAt.month, e.completedAt.day);
      days.putIfAbsent(d, () => []).add(e);
    }
    return [
      for (final d in days.keys.toList()..sort((a, b) => b.compareTo(a)))
        HistoryDay(date: d, entries: days[d]!..sort((a, b) => a.completedAt.compareTo(b.completedAt))),
    ];
  }
}
