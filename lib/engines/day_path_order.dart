import '../models/schedule_item.dart';

/// Whether [item] has no real slot (it carries the start-of-day placeholder the server/fallback gives it).
bool isUnscheduledItem(ScheduleItem item) => item.tagText == 'UNSCHEDULED';

/// The one ordering of a day's nodes: first task of the day first (it is drawn at the TOP of the path), last task
/// last. Timed items go by start time; items without a slot follow ALL timed items (they never push a timed task
/// down), each group tie-broken deterministically so the order never shuffles between rebuilds.
///
/// Nothing is dropped or reversed here: the output has exactly the items it was given.
List<ScheduleItem> orderDayPathItems(Iterable<ScheduleItem> items) {
  final list = items.toList();
  int cmp(ScheduleItem a, ScheduleItem b) {
    final ua = isUnscheduledItem(a);
    final ub = isUnscheduledItem(b);
    if (ua != ub) return ua ? 1 : -1;
    final byStart = (a.startTime ?? DateTime(0)).compareTo(b.startTime ?? DateTime(0));
    if (byStart != 0) return byStart;
    final byEnd = (a.endTime ?? DateTime(0)).compareTo(b.endTime ?? DateTime(0));
    if (byEnd != 0) return byEnd;
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }

  // List.sort is not guaranteed stable; the comparator above is total, so it does not need to be.
  list.sort(cmp);
  return list;
}

/// The task a path item belongs to (live items are `sched-<id>` / `comp-<id>`, history nodes may be either).
String dayPathTaskKey(ScheduleItem item) {
  final key = item.taskId ?? item.id;
  if (key.startsWith('sched-')) return key.substring(6);
  if (key.startsWith('comp-')) return key.substring(5);
  return key;
}

/// One stop per task, always at the slot the task first held on this day.
///
/// A skipped, deferred or missed task is moved by the server (to a later slot or day) but its stop must not move:
/// the route bypasses it, the stop keeps its place and its history. [history] is the day's deviation nodes (original
/// slots). When the task is also live on this day ([live]), the live item is the stop: it takes the original time and
/// carries the history (skipped / missed; completed -> recovered) so it can still be completed from there. A history
/// node with no live item is the stop itself. Nothing is dropped except a second history node of the same task.
List<ScheduleItem> mergeDayPathHistory(List<ScheduleItem> live, List<ScheduleItem> history) {
  final earliest = <String, ScheduleItem>{};
  for (final g in history) {
    if (g.deviation == null) continue;
    final key = dayPathTaskKey(g);
    final cur = earliest[key];
    if (cur == null || (g.startTime ?? DateTime(0)).isBefore(cur.startTime ?? DateTime(0))) earliest[key] = g;
  }

  final used = <String>{};
  final merged = <ScheduleItem>[];
  for (final item in live) {
    final ghost = item.deviation == null ? earliest[dayPathTaskKey(item)] : null;
    if (ghost == null) {
      merged.add(item);
      continue;
    }
    used.add(dayPathTaskKey(item));
    final skippedFamily = ghost.deviation == 'skipped' || ghost.deviation == 'deferred';
    merged.add(item.copyWith(
      time: ghost.time,
      period: ghost.period,
      startTime: ghost.startTime,
      endTime: ghost.endTime,
      // an unslotted live task has no place of its own: it takes the history node's look as well
      tagText: isUnscheduledItem(item) ? ghost.tagText : null,
      tagBg: isUnscheduledItem(item) ? ghost.tagBg : null,
      tagColor: isUnscheduledItem(item) ? ghost.tagColor : null,
      isConflict: isUnscheduledItem(item) ? false : null,
      isSkipped: item.isCompleted ? false : (skippedFamily ? true : item.isSkipped),
      isMissed: item.isCompleted
          ? item.isMissed
          : (skippedFamily ? false : (item.isCommitment ? item.isMissed : true)),
      isCompletedAfterDeviation: item.isCompleted ? true : item.isCompletedAfterDeviation,
      state: item.isCompleted ? item.state : ghost.deviation,
    ));
  }
  for (final e in earliest.entries) {
    if (!used.contains(e.key)) merged.add(e.value);
  }
  return merged;
}

/// Where a task's stop was first placed on a day (kept on the device by the anchor ledger). [seq] orders stops
/// that have no time (unscheduled) by when they first appeared.
class DayPathAnchorHint {
  final DateTime? anchor;
  final int seq;
  const DayPathAnchorHint({this.anchor, this.seq = 0});
}

/// The original slot of every task with history on this day (earliest history node per task).
Map<String, DateTime> dayPathHistoryAnchors(List<ScheduleItem> history) {
  final out = <String, DateTime>{};
  for (final g in history) {
    if (g.deviation == null || g.startTime == null) continue;
    final key = dayPathTaskKey(g);
    final cur = out[key];
    if (cur == null || g.startTime!.isBefore(cur)) out[key] = g.startTime!;
  }
  return out;
}

/// The anchor a stop gets without the device ledger: history slot, else the server's planned anchor, else its start.
DateTime? dayPathNaturalAnchor(ScheduleItem item, Map<String, DateTime> historyAnchors) =>
    isUnscheduledItem(item) ? null : (historyAnchors[dayPathTaskKey(item)] ?? item.anchorStart ?? item.startTime);

/// THE Calendar stop list: one stop per task, sorted ONCE by a stable anchor, then states are drawn onto it.
///
/// * identity: every task's stop is `sched-<task id>` whatever its state (planned, done, skipped, moved), so the
///   widget, its key and the route's layout never remount on a state change;
/// * position: the history slot (skip/defer/miss) > the device ledger's first-seen slot > the server's planned
///   anchor > the live start. A completion (session time), a "Do this now", a skip or a re-suggested placement
///   therefore never moves a stop; only an explicit move (which forgets the ledger entry) does;
/// * unscheduled stops come after every timed stop, in the order they first appeared.
List<ScheduleItem> buildCanonicalDayStops({
  required List<ScheduleItem> live,
  List<ScheduleItem> history = const [],
  Map<String, DayPathAnchorHint> anchors = const {},
}) {
  final historyAnchors = dayPathHistoryAnchors(history);
  final seen = <String>{};
  final stops = <ScheduleItem>[];
  for (final s in mergeDayPathHistory(live, history)) {
    if (s.taskId == null) {
      stops.add(s);
      continue;
    }
    final key = dayPathTaskKey(s);
    if (!seen.add(key)) continue; // never two stops for one task
    stops.add(s.id == 'sched-$key' ? s : s.copyWith(id: 'sched-$key'));
  }

  DateTime? orderTime(ScheduleItem s) {
    if (isUnscheduledItem(s)) return null;
    final key = dayPathTaskKey(s);
    return historyAnchors[key] ?? anchors[key]?.anchor ?? s.anchorStart ?? s.startTime;
  }

  int cmp(ScheduleItem a, ScheduleItem b) {
    final ua = isUnscheduledItem(a);
    final ub = isUnscheduledItem(b);
    if (ua != ub) return ua ? 1 : -1;
    if (ua) {
      final sa = anchors[dayPathTaskKey(a)]?.seq ?? 1 << 30;
      final sb = anchors[dayPathTaskKey(b)]?.seq ?? 1 << 30;
      if (sa != sb) return sa.compareTo(sb);
    } else {
      final byTime = (orderTime(a) ?? DateTime(0)).compareTo(orderTime(b) ?? DateTime(0));
      if (byTime != 0) return byTime;
    }
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }

  stops.sort(cmp);
  return stops;
}

/// Where the traveller is on today's path: the "Do this now" pick, else a running task (whose slot has not ended,
/// or which is the focus session), else the first stop in path order that is still open. A stop the route has
/// bypassed (skipped, missed, failed, history) is never the target.
String? pickDayPathNowId(
  List<ScheduleItem> stops, {
  required DateTime now,
  String? preferredTaskId,
  String? focusTaskId,
}) {
  bool open(ScheduleItem s) =>
      !s.isCompleted && !s.isSkipped && !s.isFailed && !s.isMissed && s.deviation == null;
  if (preferredTaskId != null) {
    for (final s in stops) {
      if (dayPathTaskKey(s) == preferredTaskId && open(s)) return s.id;
    }
  }
  for (final s in stops) {
    if (!s.isActive || s.isCompleted) continue;
    final key = dayPathTaskKey(s);
    if (key == focusTaskId || s.endTime == null || s.endTime!.isAfter(now)) return s.id;
  }
  for (final s in stops) {
    if (open(s)) return s.id;
  }
  return null;
}
