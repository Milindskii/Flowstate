import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group(
      'Dates survive preview -> confirm (finding 11) and time_locked semantics (finding 2)',
      () {
    test(
        'a server recommendation for TOMORROW keeps tomorrow and is NOT user-locked',
        () {
      final item = ExtractedTaskItem.fromJson({
        'title': 'Study DSA',
        'estimated_minutes': 60,
        'type': 'study',
        'difficulty': 'medium',
        'priority_source': 'unspecified',
        'recommended_slot_start': '2026-10-06T04:00:00Z',
        'recommended_slot_end': '2026-10-06T05:00:00Z',
        'recommended_slot_display': 'Tomorrow · 9:30 AM',
        'recommended_slot_date': '2026-10-06',
        'time_locked': false,
      });
      final task = item.toTaskItem();
      expect(task.scheduledStart, isNotNull);
      expect(task.scheduledStart!.toUtc(), DateTime.utc(2026, 10, 6, 4, 0),
          reason: 'the full instant, with its date');
      expect(task.scheduledStart!.isUtc, isFalse,
          reason: 'parsed instants are converted to device-local time');
      expect(task.timeLocked, isFalse,
          reason: 'a recommendation is never a user lock');
    });

    test('an explicit user time arrives locked', () {
      final item = ExtractedTaskItem.fromJson({
        'title': 'Dentist',
        'estimated_minutes': 45,
        'type': 'meeting',
        'difficulty': 'medium',
        'priority_source': 'unspecified',
        'fixed_start': '18:00',
        'target_date': '2026-10-06',
        'time_locked': true,
        'recommended_slot_start': '2026-10-06T12:30:00Z',
        'recommended_slot_display': 'Tomorrow · 6:00 PM',
      });
      final task = item.toTaskItem();
      expect(task.timeLocked, isTrue);
      expect(task.scheduledStart!.hour, 18);
      expect(task.scheduledStart!.day, 6);
    });

    test('TaskItem JSON round-trips instants, time_locked and planned_date',
        () {
      final src = TaskItem.fromJson({
        'id': 't1',
        'title': 'Report',
        'estimated_minutes': 60,
        'scheduled_start': '2026-10-06T11:30:00Z',
        'scheduled_end': '2026-10-06T12:30:00Z',
        'deadline_at': '2026-10-09T11:30:00Z',
        'time_locked': true,
        'planned_date': '2026-10-06',
        'status': 'todo',
      });
      expect(src.scheduledStart!.isUtc, isFalse);
      expect(src.timeLocked, isTrue);
      expect(src.plannedDate!.day, 6);
      final out = src.toJson();
      expect(out['scheduled_start'], '2026-10-06T11:30:00.000Z');
      expect(out['deadline_at'], '2026-10-09T11:30:00.000Z');
      expect(out['time_locked'], true);
      expect(out['planned_date'], '2026-10-06');
    });

    test('defaults: unlocked and no planned date', () {
      final t =
          TaskItem.fromJson({'id': 'x', 'title': 'x', 'estimated_minutes': 30});
      expect(t.timeLocked, isFalse);
      expect(t.plannedDate, isNull);
      expect(t.toJson()['planned_date'], isNull);
    });
  });
}
