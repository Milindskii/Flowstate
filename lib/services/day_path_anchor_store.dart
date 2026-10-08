import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../engines/day_path_order.dart';

/// Where each task's Calendar stop was first placed on a day, kept on the device.
///
/// The server moves tasks (a "Do this now" pulls one to now, a suggestion is re-planned as the clock moves, a
/// completion reports its session time); the day path must not. The first anchor seen for a task on a day wins
/// until the user explicitly moves that task ([forgetTask]). Days older than [keepDays] are pruned.
class DayPathAnchorStore {
  static const String prefsKey = 'flowstate_day_path_anchors_v1';
  static const int keepDays = 14;

  final Map<String, Map<String, DayPathAnchorHint>> _days = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        decoded.forEach((day, entries) {
          if (entries is! Map<String, dynamic>) return;
          _days[day] = {
            for (final e in entries.entries)
              if (e.value is Map<String, dynamic>)
                e.key: DayPathAnchorHint(
                  anchor: (e.value['a'] as String?) == null ? null : DateTime.tryParse(e.value['a'] as String)?.toLocal(),
                  seq: (e.value['s'] as num?)?.toInt() ?? 0,
                ),
          };
        });
      }
    } catch (_) {
      // a corrupt ledger only costs anchors, never the day
    }
    _loaded = true;
  }

  Map<String, DayPathAnchorHint> forDay(String day) => Map.unmodifiable(_days[day] ?? const {});

  /// Records the first anchor of every key not yet known for [day]. Returns true when something new was stored.
  bool record(String day, Map<String, DateTime?> anchors) {
    final entries = _days.putIfAbsent(day, () => {});
    var changed = false;
    var next = entries.values.fold<int>(0, (m, h) => h.seq >= m ? h.seq + 1 : m);
    for (final e in anchors.entries) {
      if (entries.containsKey(e.key)) continue;
      entries[e.key] = DayPathAnchorHint(anchor: e.value, seq: next++);
      changed = true;
    }
    return changed;
  }

  /// The user explicitly moved this task: its stop may take its new place on every day.
  bool forgetTask(String taskId) {
    var changed = false;
    for (final entries in _days.values) {
      changed = entries.remove(taskId) != null || changed;
    }
    return changed;
  }

  /// Forgets every anchor (sign-out): the ledger belongs to the account that built it.
  Future<void> clear() async {
    _days.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefsKey);
    } catch (_) {}
  }

  Future<void> save({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final cutoff = DateTime(today.year, today.month, today.day).subtract(const Duration(days: keepDays));
    _days.removeWhere((day, _) {
      final d = DateTime.tryParse(day);
      return d == null || d.isBefore(cutoff);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode({
          for (final day in _days.entries)
            day.key: {
              for (final e in day.value.entries)
                e.key: {if (e.value.anchor != null) 'a': e.value.anchor!.toUtc().toIso8601String(), 's': e.value.seq},
            },
        }),
      );
    } catch (_) {}
  }
}
