import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/ai_plan_models.dart';

/// Fields from a real /ai/plan response (Gemini, messy input, 2026-10-03). The candidate carries
/// both `deadline` (a display date with no time) and `deadline_at` (the real instant); the date-only
/// string used to win, turning "due Friday 11pm" into Friday 00:00 and "by 10pm tonight" into a
/// deadline already in the past, which the confirm endpoint then rejected.
void main() {
  Map<String, dynamic> candidate(Map<String, dynamic> extra) => {
        'title': 'Finish DBMS assignment',
        'estimated_minutes': 120,
        'task_type': 'study',
        'difficulty': 'medium',
        'priority': 'medium',
        'priority_source': 'unspecified',
        'deadline': '2026-10-09',
        'deadline_at': '2026-10-09T23:00:00+05:30',
        'target_date': '2026-10-04',
        'recommended_slot_start': '2026-10-04T09:30:00+05:30',
        'recommended_slot_date': '2026-10-04',
        'planned_date': '2026-10-04',
        ...extra,
      };

  test('deadline keeps its time: deadline_at wins over the date-only string', () {
    final task = ExtractedTaskItem.fromJson(candidate({})).toTaskItem();
    expect(task.deadlineAt, isNotNull);
    expect(task.deadlineAt!.toUtc(), DateTime.utc(2026, 10, 9, 17, 30)); // 23:00 IST
  });

  test('planned_date from the backend reaches the confirm payload source (TaskItem.plannedDate)', () {
    final task = ExtractedTaskItem.fromJson(candidate({})).toTaskItem();
    expect(task.plannedDate, DateTime(2026, 10, 4));
  });

  test('older payloads without deadline_at still fall back to the display date', () {
    final task = ExtractedTaskItem.fromJson(candidate({'deadline_at': null})).toTaskItem();
    expect(task.deadlineAt, DateTime(2026, 10, 9));
  });

  test('toJson round-trips the new fields', () {
    final item = ExtractedTaskItem.fromJson(candidate({}));
    final again = ExtractedTaskItem.fromJson({...candidate({}), ...item.toJson()});
    expect(again.deadlineAt!.toUtc(), DateTime.utc(2026, 10, 9, 17, 30));
    expect(again.plannedDate, '2026-10-04');
  });
}
