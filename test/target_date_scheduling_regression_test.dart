import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/services/task_parse_service.dart';

void main() {
  group('Target Date & Fixed Start Regression Tests (7 Cases)', () {
    // 1. "dentist appointment on Friday at 9 PM"
    test('1. "dentist appointment on Friday at 9 PM" -> target_date Friday, fixed_start 21:00, deadline null', () {

      // Backend JSON payload simulation
      final backendJson = {
        'title': 'Dentist appointment',
        'target_date': '2026-10-02',
        'fixed_start': '21:00',
        'deadline': null,
        'scheduled_start': '2026-10-02T21:00:00+05:30',
        'scheduled_end': '2026-10-02T21:45:00+05:30',
        'deadline_at': null,
        'temporal': {
          'fixed_start': '2026-10-02T21:00:00+05:30',
          'target_date': '2026-10-02',
        },
        'recommended_slot_start': '2026-10-02T21:00:00+05:30',
        'recommended_slot_display': 'Friday · 9:00 PM',
      };

      final extracted = ExtractedTaskItem.fromJson(backendJson);
      expect(extracted.targetDate, '2026-10-02');
      expect(extracted.fixedStart, '21:00');
      expect(extracted.deadline, isNull);

      final taskItem = extracted.toTaskItem();
      expect(taskItem.scheduledStart?.year, 2026);
      expect(taskItem.scheduledStart?.month, 10);
      expect(taskItem.scheduledStart?.day, 2);
      expect(taskItem.scheduledStart?.hour, 21);
      expect(taskItem.scheduledStart?.minute, 0);
      expect(taskItem.scheduledTime, contains('9:00 PM'));
      expect(taskItem.deadlineAt, isNull);

      // Deterministic fallback local parser
      final local = TaskParseService.deterministicFallbackParse('dentist appointment on Friday at 9 PM');
      expect(local.length, 1);
      expect(local[0].scheduledStart?.weekday, DateTime.friday);
      expect(local[0].scheduledStart?.hour, 21);
      expect(local[0].deadlineAt, isNull);
    });

    // 2. "dentist appointment Friday at 5 PM"
    test('2. "dentist appointment Friday at 5 PM" -> fixed_start 17:00, target_date Friday, deadline null', () {
      final backendJson = {
        'title': 'Dentist appointment',
        'target_date': '2026-10-02',
        'fixed_start': '17:00',
        'deadline': null,
        'scheduled_start': '2026-10-02T17:00:00+05:30',
      };

      final extracted = ExtractedTaskItem.fromJson(backendJson);
      expect(extracted.targetDate, '2026-10-02');
      expect(extracted.fixedStart, '17:00');
      expect(extracted.deadline, isNull);

      final taskItem = extracted.toTaskItem();
      expect(taskItem.scheduledStart?.weekday, DateTime.friday);
      expect(taskItem.scheduledStart?.hour, 17);
      expect(taskItem.deadlineAt, isNull);

      final local = TaskParseService.deterministicFallbackParse('dentist appointment Friday at 5 PM');
      expect(local.length, 1);
      expect(local[0].scheduledStart?.weekday, DateTime.friday);
      expect(local[0].scheduledStart?.hour, 17);
      expect(local[0].deadlineAt, isNull);
    });

    // 3. "dentist appointment tomorrow at 9 PM"
    test('3. "dentist appointment tomorrow at 9 PM" -> target_date tomorrow, fixed_start 21:00', () {
      final local = TaskParseService.deterministicFallbackParse('dentist appointment tomorrow at 9 PM');
      expect(local.length, 1);
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 1));
      expect(local[0].scheduledStart?.day, tomorrow.day);
      expect(local[0].scheduledStart?.hour, 21);
      expect(local[0].deadlineAt, isNull);
    });

    // 4. "dentist appointment today at 9 PM"
    test('4. "dentist appointment today at 9 PM" -> target_date today, fixed_start 21:00', () {
      final local = TaskParseService.deterministicFallbackParse('dentist appointment today at 9 PM');
      expect(local.length, 1);
      final now = DateTime.now();
      expect(local[0].scheduledStart?.day, now.day);
      expect(local[0].scheduledStart?.hour, 21);
      expect(local[0].deadlineAt, isNull);
    });

    // 5. "dentist appointment at 9 PM" with no target date
    test('5. "dentist appointment at 9 PM" -> scheduled today at 9 PM, no deadline', () {
      final local = TaskParseService.deterministicFallbackParse('dentist appointment at 9 PM');
      expect(local.length, 1);
      final now = DateTime.now();
      expect(local[0].scheduledStart?.day, now.day);
      expect(local[0].scheduledStart?.hour, 21);
      expect(local[0].deadlineAt, isNull);
    });

    // 6. "dentist appointment by Friday"
    test('6. "dentist appointment by Friday" -> deadline Friday, scheduledStart null', () {
      final local = TaskParseService.deterministicFallbackParse('dentist appointment by Friday');
      expect(local.length, 1);
      expect(local[0].scheduledStart, isNull);
      expect(local[0].deadlineAt?.weekday, DateTime.friday);
      expect(local[0].deadline, 'Friday');
    });

    // 7. "dentist appointment due Friday"
    test('7. "dentist appointment due Friday" -> deadline Friday, scheduledStart null', () {
      final local = TaskParseService.deterministicFallbackParse('dentist appointment due Friday');
      expect(local.length, 1);
      expect(local[0].scheduledStart, isNull);
      expect(local[0].deadlineAt?.weekday, DateTime.friday);
      expect(local[0].deadline, 'Friday');
    });
  });
}
