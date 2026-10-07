import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A tiny scripted backend for Calendar tests: it owns the tasks, answers the day / task-list / mutation endpoints
/// from them, and can HOLD individual responses so a test can make a read finish after (or before) a write — the
/// interleavings that cause stale Calendar state in the real app.
///
/// A held request still reads the world at the moment it ARRIVES (like a real server), only its answer is late.
class CalendarWorld {
  CalendarWorld(this.today);

  /// Local midnight of the day the tests treat as "today".
  final DateTime today;

  /// id -> task. `day` is an offset from [today]; `hour` the slot's local start hour.
  final Map<String, WorldTask> tasks = {};

  /// Original hour of a skipped task, per id (the server keeps it as history).
  final Map<String, double> skippedFrom = {};
  final Set<String> claimedDays = {};

  int dayGets = 0;
  int taskGets = 0;
  int todayGets = 0;
  int claimPosts = 0;
  int xpAwardedTotal = 0;
  final List<String> calls = [];

  // Hold the NEXT request of a kind until the completer is completed.
  Completer<void>? holdNextDay;
  Completer<void>? holdNextTasks;
  Completer<void>? holdNextToday;
  Completer<void>? holdNextComplete;
  Completer<void>? holdNextDelete;
  Completer<void>? holdNextPatch;
  Completer<void>? holdNextClaim;

  /// Make the next completion / delete / patch fail with a 500.
  bool failNextComplete = false;
  bool failNextDelete = false;
  bool failNextPatch = false;
  bool failNextClaim = false;

  WorldTask add(String id, double hour, {int day = 0, bool done = false}) =>
      tasks[id] = WorldTask(id: id, title: 'Task $id', hour: hour, day: day, done: done);

  DateTime at(double hour, {int day = 0}) {
    final base = DateTime(today.year, today.month, today.day).add(Duration(days: day));
    return base.add(Duration(minutes: (hour * 60).round()));
  }

  String dateStr(int day) {
    final d = DateTime(today.year, today.month, today.day).add(Duration(days: day));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  int dayOffsetOf(String date) {
    final d = DateTime.parse(date);
    return DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
  }

  Map<String, dynamic> _item(String id, WorldTask t, {String? deviation, double? hour}) {
    final start = at(hour ?? t.hour, day: t.day);
    final h12 = start.hour % 12 == 0 ? 12 : start.hour % 12;
    return {
      'id': id,
      'task_id': t.id,
      'title': t.title,
      'start_time': start.toUtc().toIso8601String(),
      'end_time': start.add(const Duration(minutes: 30)).toUtc().toIso8601String(),
      'time': '$h12:${start.minute.toString().padLeft(2, '0')}',
      'period': start.hour >= 12 ? 'PM' : 'AM',
      'duration_minutes': 30,
      'type': 'deep_work',
      'tag_text': deviation != null ? deviation.toUpperCase() : (t.done ? 'COMPLETED' : 'DEEP WORK'),
      'is_completed': deviation == null && t.done,
      'state': deviation ?? (t.done ? 'completed' : 'scheduled'),
      if (deviation != null) 'deviation': deviation,
      if (deviation == 'skipped') 'is_skipped': true,
    };
  }

  String dayBody(int day) {
    final live = [for (final t in tasks.values) if (t.day == day) t];
    final timeline = [for (final t in live) _item(t.done ? 'comp-${t.id}' : 'sched-${t.id}', t)];
    final history = [
      for (final e in skippedFrom.entries)
        if (tasks[e.key] != null && (tasks[e.key]!.day == day || day == 0))
          _item('dev-${e.key}', tasks[e.key]!, deviation: 'skipped', hour: e.value),
    ];
    final done = live.where((t) => t.done).length;
    final open = live.where((t) => !t.done).length;
    final date = dateStr(day);
    return jsonEncode({
      'date': date,
      'is_today': day == 0,
      'is_past': day < 0,
      'timeline': timeline,
      'fixed_commitments': [],
      'completed_tasks': [for (final i in timeline) if (i['is_completed'] == true) i],
      'remaining_tasks': [],
      'unscheduled_tasks': [],
      'deviations': history,
      'conflicts': [],
      'day_complete': {
        'eligible': (day <= 0 && done > 0 && open == 0) || claimedDays.contains(date),
        'claimed': claimedDays.contains(date),
        'xp': 25,
      },
    });
  }

  Map<String, dynamic> taskRow(WorldTask t) => {
        'id': t.id,
        'title': t.title,
        'status': t.done ? 'completed' : 'todo',
        'is_completed': t.done,
        'estimated_minutes': 30,
        'scheduled_start': at(t.hour, day: t.day).toUtc().toIso8601String(),
        'scheduled_end': at(t.hour + 0.5, day: t.day).toUtc().toIso8601String(),
        'planned_date': dateStr(t.day),
        'category': 'Work',
      };

  String tasksBody() => jsonEncode({'items': [for (final t in tasks.values) taskRow(t)], 'total': tasks.length});

  Future<void> _hold(Completer<void>? c) async {
    if (c != null) await c.future;
  }

  Future<http.Response> handle(http.Request r) async {
    final headers = {'content-type': 'application/json'};
    http.Response ok(String body) => http.Response(body, 200, headers: headers);
    final path = r.url.path;
    calls.add('${r.method} $path');

    if (path.endsWith('/api/v1/calendar/day') && r.method == 'GET') {
      dayGets++;
      final body = dayBody(dayOffsetOf(r.url.queryParameters['date']!)); // read on arrival
      final c = holdNextDay;
      holdNextDay = null;
      await _hold(c);
      return ok(body);
    }
    if (path.endsWith('/api/v1/tasks') && r.method == 'GET') {
      taskGets++;
      final body = tasksBody();
      final c = holdNextTasks;
      holdNextTasks = null;
      await _hold(c);
      return ok(body);
    }
    if (path.endsWith('/api/v1/today') && r.method == 'GET') {
      todayGets++;
      final c = holdNextToday;
      holdNextToday = null;
      await _hold(c);
      return http.Response('{"detail":"no today in this world"}', 404, headers: headers);
    }
    final complete = RegExp(r'/api/v1/tasks/([^/]+)/complete$').firstMatch(path);
    if (complete != null && r.method == 'POST') {
      final c = holdNextComplete;
      holdNextComplete = null;
      await _hold(c);
      if (failNextComplete) {
        failNextComplete = false;
        return http.Response('{"detail":"boom"}', 500, headers: headers);
      }
      tasks[complete.group(1)!]?.done = true;
      return ok('{}');
    }
    final skip = RegExp(r'/api/v1/today/skip/([^/]+)$').firstMatch(path);
    if (skip != null && r.method == 'POST') {
      final t = tasks[skip.group(1)!];
      if (t != null) {
        skippedFrom[t.id] = t.hour;
        t.hour += 6;
      }
      return ok(jsonEncode({'recorded': true, 'next_window': null, 'message': 'Skipped.'}));
    }
    final single = RegExp(r'/api/v1/tasks/([^/]+)$').firstMatch(path);
    if (single != null && r.method == 'DELETE') {
      final c = holdNextDelete;
      holdNextDelete = null;
      await _hold(c);
      if (failNextDelete) {
        failNextDelete = false;
        return http.Response('{"detail":"boom"}', 500, headers: headers);
      }
      tasks.remove(single.group(1)!);
      skippedFrom.remove(single.group(1)!);
      return ok('{}');
    }
    if (single != null && r.method == 'PATCH') {
      final c = holdNextPatch;
      holdNextPatch = null;
      await _hold(c);
      if (failNextPatch) {
        failNextPatch = false;
        return http.Response('{"detail":"boom"}', 500, headers: headers);
      }
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final t = tasks[single.group(1)!];
      if (t != null && body['planned_date'] is String) t.day = dayOffsetOf(body['planned_date'] as String);
      return ok(tasksBody());
    }
    if (path.endsWith('/api/v1/calendar/apply-replan') && r.method == 'POST') {
      // applies the server-authored updates verbatim: [{task_id, scheduled_start}]
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final moved = <Map<String, dynamic>>[];
      for (final u in (body['task_updates'] as List? ?? const []).whereType<Map<String, dynamic>>()) {
        final t = tasks[u['task_id']];
        if (t == null) continue;
        final start = DateTime.parse(u['scheduled_start'] as String).toLocal();
        t.hour = start.hour + start.minute / 60;
        moved.add(taskRow(t));
      }
      return ok(jsonEncode({'success': true, 'updated_count': moved.length, 'persisted_tasks': moved}));
    }
    if (path.endsWith('/api/v1/flow/day-complete/claim') && r.method == 'POST') {
      claimPosts++;
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final c = holdNextClaim;
      holdNextClaim = null;
      await _hold(c);
      if (failNextClaim) {
        failNextClaim = false;
        return http.Response('{"detail":"boom"}', 500, headers: headers);
      }
      final date = body['date'] as String;
      final already = !claimedDays.add(date);
      final awarded = already ? 0 : 25;
      xpAwardedTotal += awarded;
      return ok(jsonEncode({
        'date': date,
        'claimed': true,
        'already_claimed': already,
        'xp_awarded': awarded,
        'companion_xp': xpAwardedTotal,
        'level': 1,
        'leveled_up': false,
      }));
    }
    return ok('{}');
  }
}

class WorldTask {
  WorldTask({required this.id, required this.title, required this.hour, required this.day, required this.done});
  final String id;
  final String title;
  double hour;
  int day;
  bool done;
}
