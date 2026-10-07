import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/engines/task_state.dart';
import 'package:flowstate/models/schedule_item.dart';

/// The Flutter half of the shared task-state contract (shared/task_state_vectors.json).
/// The backend runs the same vectors in backend/tests/test_task_state_vectors.py.
void main() {
  final spec = jsonDecode(File('shared/task_state_vectors.json').readAsStringSync()) as Map<String, dynamic>;

  test('constants match the shared contract', () {
    expect(kMissedGraceMinutes, spec['missed_grace_minutes']);
    expect(kBedtimeAfterMidnightBelowHours, spec['bedtime_after_midnight_below_hours']);
  });

  for (final c in (spec['cases'] as List).cast<Map<String, dynamic>>()) {
    test(c['name'] as String, () {
      DateTime? dt(String? s) => s == null ? null : DateTime.parse(s);
      final start = dt(c['start'] as String?);
      final now = dt(c['now'] as String)!;
      final boundary = dayBoundary(start ?? now, (c['bedtime'] as num).toDouble());
      final got = deriveTaskState(
        completed: c['completed'] as bool,
        cancelled: c['cancelled'] as bool,
        active: c['active'] as bool,
        start: start,
        end: dt(c['end'] as String?),
        now: now,
        dayBoundary: boundary,
        commitment: (c['commitment'] as bool?) ?? false,
      );
      expect(got.name, c['expected']);
    });
  }

  // The same vectors, through the object every screen renders: ScheduleItem.withDerivedState.
  group('ScheduleItem.withDerivedState follows the shared vectors', () {
    for (final c in (spec['cases'] as List).cast<Map<String, dynamic>>().where((c) => c['cancelled'] == false)) {
      test(c['name'] as String, () {
        DateTime? dt(String? s) => s == null ? null : DateTime.parse(s);
        final item = ScheduleItem(
          id: 'i', time: '9:00', period: 'AM', title: 't', type: 'Task', tagText: 'TASK',
          isCompleted: c['completed'] as bool,
          isActive: c['active'] as bool,
          isCommitment: (c['commitment'] as bool?) ?? false,
          startTime: dt(c['start'] as String?),
          endTime: dt(c['end'] as String?),
        ).withDerivedState(now: dt(c['now'] as String)!, bedtimeHours: (c['bedtime'] as num).toDouble());
        expect(item.state, c['expected']);
        expect(item.isMissed, c['expected'] == 'missed');
        expect(item.isFailed, c['expected'] == 'failed');
      });
    }

    test('a recorded history node keeps its own kind and is never re-derived', () {
      final node = ScheduleItem(
        id: 'h', time: '9:00', period: 'AM', title: 't', type: 'Task', tagText: 'TASK',
        deviation: 'skipped', startTime: DateTime(2026, 10, 3, 9), endTime: DateTime(2026, 10, 3, 10), state: 'skipped',
      ).withDerivedState(now: DateTime(2026, 10, 4, 12), bedtimeHours: 23.0);
      expect(node.state, 'skipped');
      expect(node.isFailed, false);
    });
  });

  test('slotHasEnded is inclusive at the exact end and honours the shared grace', () {
    final end = DateTime(2026, 10, 4, 10);
    expect(slotHasEnded(end, end.subtract(const Duration(seconds: 1))), false);
    expect(slotHasEnded(end, end), true);
    expect(slotHasEnded(null, end), false);
  });
}
