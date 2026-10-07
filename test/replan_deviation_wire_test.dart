import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/calendar_models.dart';

// GET /calendar/day: a task skipped today stays as a history node in `deviations` (not in `timeline`).
void main() {
  Map<String, dynamic> item(String id, String title, {Map<String, dynamic> extra = const {}}) => {
        'id': id,
        'task_id': 't-$id',
        'title': title,
        'start_time': '2026-10-05T12:00:00+05:30',
        'end_time': '2026-10-05T13:00:00+05:30',
        'time': '12:00',
        'period': 'PM',
        'duration_minutes': 60,
        'type': 'deep_work',
        'tag_text': 'DEEP WORK',
        ...extra,
      };

  test('deviations parse with is_skipped and kind, separate from the timeline', () {
    final r = DayScheduleResponse.fromJson({
      'date': '2026-10-05',
      'timeline': [item('a', 'Alpha'), item('c', 'Charlie')],
      'deviations': [
        item('dev-1', 'Bravo', extra: {'is_skipped': true, 'deviation': 'skipped', 'tag_text': 'SKIPPED'}),
      ],
    });
    expect(r.timeline.map((i) => i.title), ['Alpha', 'Charlie']);
    expect(r.deviations, hasLength(1));
    expect(r.deviations.single.isSkipped, isTrue);
    expect(r.deviations.single.deviation, 'skipped');
    expect(DayScheduleResponse.fromJson(r.toJson()).deviations.single.deviation, 'skipped');
  });

  test('older servers without deviations still parse', () {
    final r = DayScheduleResponse.fromJson({'date': '2026-10-05', 'timeline': []});
    expect(r.deviations, isEmpty);
  });
}
