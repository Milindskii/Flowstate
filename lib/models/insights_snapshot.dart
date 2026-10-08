import 'dart:math' as math;

import '../components/noya_companion_view.dart';
import 'task_item.dart';
import 'task_reflection.dart';

/// Parts of the day used to describe when the user finishes things.
enum DayWindow { morning, afternoon, evening, night }

extension DayWindowLabel on DayWindow {
  String get label {
    switch (this) {
      case DayWindow.morning:
        return 'Morning';
      case DayWindow.afternoon:
        return 'Afternoon';
      case DayWindow.evening:
        return 'Evening';
      case DayWindow.night:
        return 'Late night';
    }
  }

  String get range {
    switch (this) {
      case DayWindow.morning:
        return '5 AM – 12 PM';
      case DayWindow.afternoon:
        return '12 – 5 PM';
      case DayWindow.evening:
        return '5 – 10 PM';
      case DayWindow.night:
        return '10 PM – 5 AM';
    }
  }

  static DayWindow of(DateTime t) {
    final h = t.hour;
    if (h >= 5 && h < 12) return DayWindow.morning;
    if (h >= 12 && h < 17) return DayWindow.afternoon;
    if (h >= 17 && h < 22) return DayWindow.evening;
    return DayWindow.night;
  }
}

class ReflectionAverages {
  final double energy;
  final double focus;
  final double difficulty;
  final double distraction;

  const ReflectionAverages({required this.energy, required this.focus, required this.difficulty, required this.distraction});
}

/// One planned-vs-actual pair from a reflection.
class DurationPair {
  final String title;
  final int planned;
  final int actual;

  const DurationPair({required this.title, required this.planned, required this.actual});
}

/// Something Flowstate noticed, with the data behind it. Only produced when the data supports it.
class Learning {
  final String id;
  final String text;
  final String evidence;

  const Learning({required this.id, required this.text, required this.evidence});
}

/// Everything the Insights screen says, computed only from data the app really has:
/// completions with a recorded time and the reflections stored on this device. A pattern is
/// reported only when there is enough data behind it; otherwise its field is null.
class InsightsSnapshot {
  static const int minReflections = 3;
  static const int minTimedCompletions = 3;

  /// "You get the most done in the morning" is a claim about a habit, so it needs a habit's worth of evidence: enough
  /// finished tasks, on enough different days, a leader that holds at least half of them, and a clear lead. (Six
  /// tasks ticked off in one sitting is one busy morning, not a pattern.)
  static const int minWindowCompletions = 8;
  static const int minWindowDays = 3;
  static const double minWindowShare = 0.5;
  static const int minWindowLead = 2;

  /// "Your focus is sharpest in..." compares parts of the day, so its reflections must span several days too.
  static const int minFocusDays = 3;
  static const int minPlannedForFollowThrough = 5;
  static const int maxSeries = 12;

  /// Completions per day for last week and this week (14 values, Monday of last week first).
  final List<int> fortnightCounts;

  /// Timed completions per hour of the day (24 values).
  final List<int> hourCounts;

  /// Reflections oldest → newest (at most the latest [maxSeries]).
  final List<TaskReflection> series;

  /// Latest reflections with both a planned and an actual duration, newest first (at most 6).
  final List<DurationPair> durationPairs;

  /// 'shorter' / 'about_right' / 'longer' answers from the reflection sheet.
  final Map<String, int> durationFeedbackCounts;

  /// Tasks whose planned slot ended in the last 14 days, and how many of them are finished.
  final int plannedRecently;
  final int plannedRecentlyDone;

  /// Interpretations of the patterns above, strongest first.
  final List<Learning> learnings;

  /// Completions per day of the current week, Monday first.
  final List<int> weekCounts;
  final int completionsThisWeek;
  final int completionsLastWeek;
  final int activeDaysThisWeek;
  final int totalCompletions;
  final int completionsWithoutTime;
  final Map<DayWindow, int> windowCounts;
  final DayWindow? bestWindow;
  final int reflectionCount;
  final ReflectionAverages? averages;
  final DayWindow? mostFocusedWindow;

  /// Median of actual ÷ planned minutes across reflections, or null with too little data.
  final double? plannedVsActual;
  final Map<int, int> feelingCounts;

  const InsightsSnapshot._({
    required this.weekCounts,
    required this.completionsThisWeek,
    required this.completionsLastWeek,
    required this.activeDaysThisWeek,
    required this.totalCompletions,
    required this.completionsWithoutTime,
    required this.windowCounts,
    required this.bestWindow,
    required this.reflectionCount,
    required this.averages,
    required this.mostFocusedWindow,
    required this.plannedVsActual,
    required this.feelingCounts,
    required this.fortnightCounts,
    required this.hourCounts,
    required this.series,
    required this.durationPairs,
    required this.durationFeedbackCounts,
    required this.plannedRecently,
    required this.plannedRecentlyDone,
    required this.learnings,
  });

  bool get hasFollowThrough => plannedRecently >= minPlannedForFollowThrough;
  int get timedCompletions => hourCounts.fold(0, (a, b) => a + b);

  bool get hasAnyHistory => totalCompletions > 0 || reflectionCount > 0;

  int get reflectionsNeeded => (minReflections - reflectionCount).clamp(0, minReflections);

  String get headline {
    if (completionsThisWeek == 0) {
      return hasAnyHistory ? 'A quiet week so far' : 'Your story starts with one finished task';
    }
    final tasks = completionsThisWeek == 1 ? 'task' : 'tasks';
    final days = activeDaysThisWeek == 1 ? 'day' : 'days';
    return '$completionsThisWeek $tasks finished across $activeDaysThisWeek $days this week';
  }

  String? get plannedVsActualLabel {
    final r = plannedVsActual;
    if (r == null) return null;
    if (r >= 0.9 && r <= 1.1) return 'Tasks usually take about as long as planned';
    final pct = ((r - 1).abs() * 100).round();
    return r > 1
        ? 'Tasks usually take about $pct% longer than planned'
        : 'Tasks usually take about $pct% less time than planned';
  }

  /// Noya's pose for the week: still learning, proud of a steady week, or encouraging.
  NoyaState get noyaState {
    if (!hasAnyHistory) return NoyaState.thinking;
    if (completionsThisWeek > 0 && completionsThisWeek >= completionsLastWeek) return NoyaState.proud;
    return NoyaState.encouraging;
  }

  static DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

  static double _median(List<double> xs) {
    final s = [...xs]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  static InsightsSnapshot compute({
    required List<TaskItem> tasks,
    required List<TaskReflection> reflections,
    required DateTime now,
  }) {
    // One completion per task: the reflection's time wins over the task's. `times` is WHEN it was finished (used for
    // "when do you finish things"); `owned` is the day it BELONGED TO (planned day, like Calendar, Today and History),
    // used for the per-day counts, so a task planned for tomorrow and done early is not today's finish.
    final byTask = {for (final r in reflections) r.taskId: r};
    final times = <String, DateTime>{};
    final owned = <String, DateTime>{};
    var withoutTime = 0;
    for (final t in tasks.where((t) => t.isCompleted)) {
      final at = byTask[t.id]?.completedAt ?? t.completedAt;
      if (at == null) {
        withoutTime++;
      } else {
        times[t.id] = at;
        owned[t.id] = t.owningDate ?? _day(at);
      }
    }
    for (final r in reflections) {
      if (!times.containsKey(r.taskId)) {
        times[r.taskId] = r.completedAt;
        owned[r.taskId] = _day(r.completedAt);
      }
    }

    final today = _day(now);
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final lastWeekStart = weekStart.subtract(const Duration(days: 7));
    final weekCounts = List<int>.filled(7, 0);
    var lastWeek = 0;
    final windowCounts = {for (final w in DayWindow.values) w: 0};
    for (final id in times.keys) {
      final at = times[id]!;
      final d = owned[id]!;
      final offset = d.difference(weekStart).inDays;
      if (offset >= 0 && offset < 7) weekCounts[offset]++;
      if (!d.isBefore(lastWeekStart) && d.isBefore(weekStart)) lastWeek++;
      windowCounts[DayWindowLabel.of(at)] = windowCounts[DayWindowLabel.of(at)]! + 1;
    }

    // A time-of-day pattern: enough finishes, on enough different days, a leader with a real share and a clear lead.
    final finishDays = {for (final at in times.values) _day(at)}.length;
    DayWindow? best;
    if (times.length >= minWindowCompletions && finishDays >= minWindowDays) {
      final ranked = windowCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      final top = ranked.first.value;
      if (top / times.length >= minWindowShare && top - ranked[1].value >= minWindowLead) best = ranked.first.key;
    }
    final reflectionDays = {for (final r in reflections) _day(r.completedAt)}.length;

    ReflectionAverages? averages;
    DayWindow? mostFocused;
    double? ratio;
    if (reflections.length >= minReflections) {
      double avg(int Function(TaskReflection r) f) => reflections.map(f).reduce((a, b) => a + b) / reflections.length;
      averages = ReflectionAverages(
        energy: avg((r) => r.energy),
        focus: avg((r) => r.focus),
        difficulty: avg((r) => r.difficulty),
        distraction: avg((r) => r.distraction),
      );

      final focusByWindow = <DayWindow, List<int>>{};
      for (final r in reflections) {
        focusByWindow.putIfAbsent(DayWindowLabel.of(r.completedAt), () => []).add(r.focus);
      }
      final candidates = focusByWindow.entries.where((e) => e.value.length >= 2).toList()
        ..sort((a, b) {
          double mean(List<int> xs) => xs.reduce((x, y) => x + y) / xs.length;
          return mean(b.value).compareTo(mean(a.value));
        });
      if (candidates.isNotEmpty && reflectionDays >= minFocusDays) mostFocused = candidates.first.key;

      final ratios = [
        for (final r in reflections)
          if ((r.plannedMinutes ?? 0) > 0 && r.actualMinutes > 0) r.actualMinutes / r.plannedMinutes!,
      ];
      if (ratios.length >= minReflections) ratio = _median(ratios);
    }

    final feelings = <int, int>{};
    for (final r in reflections) {
      feelings[r.feeling] = (feelings[r.feeling] ?? 0) + 1;
    }

    final fortnight = List<int>.filled(14, 0);
    final hours = List<int>.filled(24, 0);
    for (final id in times.keys) {
      final at = times[id]!;
      final offset = owned[id]!.difference(lastWeekStart).inDays;
      if (offset >= 0 && offset < 14) fortnight[offset]++;
      hours[at.hour]++;
    }

    final chronological = [...reflections]..sort((a, b) => a.completedAt.compareTo(b.completedAt));
    final series = chronological.length > maxSeries ? chronological.sublist(chronological.length - maxSeries) : chronological;

    final pairs = [
      for (final r in chronological.reversed)
        if ((r.plannedMinutes ?? 0) > 0 && r.actualMinutes > 0)
          DurationPair(title: r.title, planned: r.plannedMinutes!, actual: r.actualMinutes),
    ].take(6).toList();

    final feedback = <String, int>{};
    for (final r in reflections) {
      final f = r.durationFeedback;
      if (f != null) feedback[f] = (feedback[f] ?? 0) + 1;
    }

    // Follow-through: planned slots that fully ended within the last 14 days.
    final since = today.subtract(const Duration(days: 13));
    var planned = 0;
    var plannedDone = 0;
    for (final t in tasks) {
      final start = t.scheduledStart;
      if (start == null || start.isBefore(since)) continue;
      final end = t.scheduledEnd ?? start.add(Duration(minutes: t.durationMinutes));
      if (end.isAfter(now)) continue;
      planned++;
      if (t.isCompleted) plannedDone++;
    }

    final learnings = _learn(
      reflections: reflections,
      windowCounts: windowCounts,
      best: best,
      timed: times.length,
      finishDays: finishDays,
      reflectionDays: reflectionDays,
      ratio: ratio,
      ratioCount: reflections.where((r) => (r.plannedMinutes ?? 0) > 0 && r.actualMinutes > 0).length,
      planned: planned,
      plannedDone: plannedDone,
    );

    return InsightsSnapshot._(
      weekCounts: weekCounts,
      completionsThisWeek: weekCounts.fold(0, (a, b) => a + b),
      completionsLastWeek: lastWeek,
      activeDaysThisWeek: weekCounts.where((c) => c > 0).length,
      totalCompletions: times.length + withoutTime,
      completionsWithoutTime: withoutTime,
      windowCounts: windowCounts,
      bestWindow: best,
      reflectionCount: reflections.length,
      averages: averages,
      mostFocusedWindow: mostFocused,
      plannedVsActual: ratio,
      feelingCounts: feelings,
      fortnightCounts: fortnight,
      hourCounts: hours,
      series: series,
      durationPairs: pairs,
      durationFeedbackCounts: feedback,
      plannedRecently: planned,
      plannedRecentlyDone: plannedDone,
      learnings: learnings,
    );
  }

  static String _one(double v) => v.toStringAsFixed(1);

  static double _mean(Iterable<num> xs) => xs.fold<double>(0, (a, b) => a + b) / xs.length;

  /// Pearson correlation, or null when either side has no spread.
  static double? _correlation(List<num> xs, List<num> ys) {
    final mx = _mean(xs), my = _mean(ys);
    var sxy = 0.0, sxx = 0.0, syy = 0.0;
    for (var i = 0; i < xs.length; i++) {
      sxy += (xs[i] - mx) * (ys[i] - my);
      sxx += (xs[i] - mx) * (xs[i] - mx);
      syy += (ys[i] - my) * (ys[i] - my);
    }
    if (sxx == 0 || syy == 0) return null;
    return sxy / math.sqrt(sxx * syy);
  }

  static List<Learning> _learn({
    required List<TaskReflection> reflections,
    required Map<DayWindow, int> windowCounts,
    required DayWindow? best,
    required int timed,
    required int finishDays,
    required int reflectionDays,
    required double? ratio,
    required int ratioCount,
    required int planned,
    required int plannedDone,
  }) {
    final out = <Learning>[];

    if (best != null) {
      out.add(Learning(
        id: 'best_window',
        text: 'You get the most done in the ${best.label.toLowerCase()}.',
        evidence: '${windowCounts[best]} of $timed finished tasks over $finishDays days landed between ${best.range}.',
      ));
    }

    // Focus by part of day, only as a comparison: two parts of the day with 2+ reflections each.
    if (reflections.length >= minReflections && reflectionDays >= minFocusDays) {
      final byWindow = <DayWindow, List<int>>{};
      for (final r in reflections) {
        byWindow.putIfAbsent(DayWindowLabel.of(r.completedAt), () => []).add(r.focus);
      }
      final solid = byWindow.entries.where((e) => e.value.length >= 2).toList()
        ..sort((a, b) => _mean(b.value).compareTo(_mean(a.value)));
      if (solid.length >= 2 && _mean(solid.first.value) - _mean(solid.last.value) >= 0.5) {
        final top = solid.first;
        final others = [for (final e in byWindow.entries) if (e.key != top.key) ...e.value];
        out.add(Learning(
          id: 'focus_window',
          text: 'Your focus is sharpest in the ${top.key.label.toLowerCase()}.',
          evidence: 'Focus ${_one(_mean(top.value))}/5 there vs ${_one(_mean(others))}/5 at other times.',
        ));
      }
    }

    if (ratio != null) {
      final pct = ((ratio - 1).abs() * 100).round();
      out.add(Learning(
        id: 'estimates',
        text: ratio >= 0.9 && ratio <= 1.1
            ? 'Your time estimates are reliable.'
            : (ratio > 1 ? 'Tasks tend to run about $pct% over what you plan.' : 'You tend to finish about $pct% faster than planned.'),
        evidence: 'Median of $ratioCount tasks with a planned and an actual time.',
      ));
    }

    // Does difficulty change how a task feels? Needs 2+ hard and 2+ easier reflections.
    final hard = reflections.where((r) => r.difficulty >= 4).map((r) => r.feeling).toList();
    final easier = reflections.where((r) => r.difficulty <= 3).map((r) => r.feeling).toList();
    if (hard.length >= 2 && easier.length >= 2) {
      final gap = _mean(hard) - _mean(easier);
      if (gap.abs() >= 0.75) {
        out.add(Learning(
          id: 'difficulty',
          text: gap < 0 ? 'Harder tasks tend to leave you drained.' : 'You come out of harder tasks feeling better.',
          evidence: 'Feeling ${_one(_mean(hard))}/4 after hard tasks vs ${_one(_mean(easier))}/4 after easier ones.',
        ));
      }
    }

    if (reflections.length >= 5) {
      final r = _correlation([for (final x in reflections) x.energy], [for (final x in reflections) x.focus]);
      if (r != null && r >= 0.5) {
        out.add(Learning(
          id: 'energy_focus',
          text: 'Your focus follows your energy.',
          evidence: 'Across ${reflections.length} reflections, your higher-energy sessions were the more focused ones.',
        ));
      }
      final distraction = _mean([for (final x in reflections) x.distraction]);
      if (distraction >= 3.5 || distraction <= 1.5) {
        out.add(Learning(
          id: 'distraction',
          text: distraction >= 3.5 ? 'Distraction is costing you focus.' : 'Once you start, you rarely get distracted.',
          evidence: 'Distraction averaged ${_one(distraction)}/5 across ${reflections.length} reflections.',
        ));
      }
    }

    if (planned >= minPlannedForFollowThrough) {
      final rate = plannedDone / planned;
      out.add(Learning(
        id: 'follow_through',
        text: rate >= 0.8
            ? 'You reliably finish what you plan.'
            : (rate >= 0.5 ? 'Most of what you plan gets done.' : 'Your plans tend to be bigger than your days.'),
        evidence: '$plannedDone of $planned tasks planned in the last two weeks are finished.',
      ));
    }

    return out;
  }
}
