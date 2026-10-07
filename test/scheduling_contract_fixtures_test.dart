import 'dart:convert';
import 'dart:io';

import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the SAME invariant fixtures as backend/tests/test_scheduling_contract_fixtures.py against the
/// Dart engine (spec section 9). The backend planner is authoritative; this test measures how far the
/// client engine diverges. A failure here is a real divergence to triage, NOT a reason to delete the
/// Dart engine yet (removal needs a separate spec once this file passes unchanged).
void main() {
  final fixture = jsonDecode(
      File('backend/tests/fixtures/scheduling_contract_cases.json')
          .readAsStringSync()) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  TaskItem toTask(Map<String, dynamic> t) {
    final minutes = t['minutes'] as int;
    final locked = t['locked'] == true;
    final start =
        t['start'] != null ? DateTime.parse(t['start'] as String) : null;
    return TaskItem(
      id: t['id'] as String,
      title: t['title'] as String,
      durationMinutes: minutes,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      taskType: TaskType.fromString(t['type'] as String?),
      priority: TaskPriority.tryFromString(t['priority'] as String?),
      scheduledStart: start,
      scheduledEnd: start?.add(Duration(minutes: minutes)),
      timeLocked: locked,
      deadlineAt: t['deadline'] != null
          ? DateTime.parse(t['deadline'] as String)
          : null,
    );
  }

  for (final c in cases) {
    test('Dart engine honours the contract invariants: ${c['name']}', () {
      final now = DateTime.parse(
          c['now'] as String); // wall-clock string => device-local DateTime
      final tasks = (c['tasks'] as List)
          .cast<Map<String, dynamic>>()
          .map(toTask)
          .toList();
      const engine = SchedulingEngine();

      // Same order of operations as enrichTasksWithOptimalSlots: fixed times first, then flexible in order.
      final busy = <MapEntry<DateTime, DateTime>>[];
      final spans = <String, MapEntry<DateTime, DateTime>>{};
      for (final t in tasks.where((t) => t.timeLocked)) {
        final e = t.scheduledEnd ??
            t.scheduledStart!.add(Duration(minutes: t.durationMinutes));
        busy.add(MapEntry(t.scheduledStart!, e));
        spans[t.id] = MapEntry(t.scheduledStart!, e);
      }
      for (final t in tasks.where((t) => !t.timeLocked)) {
        final eval =
            engine.evaluateCandidateSlot(t, existingBusy: busy, nowLocal: now);
        spans[t.id] = MapEntry(eval.slotStart, eval.slotEnd);
        busy.add(MapEntry(
            eval.slotStart, eval.slotEnd.add(const Duration(minutes: 10))));
      }

      final violations = <String>[];
      final ids = spans.keys.toList();
      for (final t in tasks.where((t) => !t.timeLocked)) {
        final s = spans[t.id]!;
        if (s.key.isBefore(now)) {
          violations.add('${t.id} placed in the past (${s.key})');
        }
        if (t.deadlineAt != null && s.value.isAfter(t.deadlineAt!)) {
          violations.add('${t.id} ends after its deadline');
        }
      }
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = spans[ids[i]]!, b = spans[ids[j]]!;
          final aLocked = tasks.firstWhere((t) => t.id == ids[i]).timeLocked;
          final bLocked = tasks.firstWhere((t) => t.id == ids[j]).timeLocked;
          if (aLocked && bLocked) continue; // two user-fixed times may overlap
          if (a.key.isBefore(b.value) && a.value.isAfter(b.key)) {
            violations.add('${ids[i]} overlaps ${ids[j]}');
          }
        }
      }
      for (final t in tasks.where((t) => t.timeLocked)) {
        if (spans[t.id]!.key != t.scheduledStart) {
          violations.add('${t.id} user-fixed time moved');
        }
      }
      expect(violations, isEmpty,
          reason: 'divergence from the backend planner contract: $violations');
    });
  }
}
