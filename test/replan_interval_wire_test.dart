import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/calendar_models.dart';

// The Replan preview must show whole intervals ("6:30 PM – 8:30 PM"), never a start-only "6:30 PM → 6:30 PM".
void main() {
  Map<String, dynamic> row(Map<String, dynamic> extra) => {
        'task_id': 't',
        'title': 'Going out',
        'change_type': 'unchanged',
        'old_time': '6:30 PM',
        'new_time': '6:30 PM',
        ...extra,
      };

  test('a locked commitment keeps its full interval and flag', () {
    final t = TaskDiffItem.fromJson(row({
      'old_time_range': '6:30 PM – 8:30 PM',
      'new_time_range': '6:30 PM – 8:30 PM',
      'new_start': '2026-10-05T18:30:00+05:30',
      'new_end': '2026-10-05T20:30:00+05:30',
      'is_commitment': true,
      'time_locked': true,
    }));
    expect(t.isCommitment, isTrue);
    expect(t.timeLocked, isTrue);
    expect(t.changeLabel, '6:30 PM – 8:30 PM');
    expect(t.newEnd!.difference(t.newStart!).inMinutes, 120);
    expect(TaskDiffItem.fromJson(t.toJson()).changeLabel, '6:30 PM – 8:30 PM');
  });

  test('a moved task shows old interval -> new interval', () {
    final t = TaskDiffItem.fromJson(row({
      'change_type': 'moved',
      'old_time_range': '8:30 PM – 10:45 PM',
      'new_time_range': '9:00 PM – 11:15 PM',
    }));
    expect(t.changeLabel, '8:30 PM – 10:45 PM → 9:00 PM – 11:15 PM');
  });

  test('older servers without ranges fall back to the start times', () {
    final t = TaskDiffItem.fromJson(row({'old_time': '5:00 PM', 'new_time': '7:30 PM', 'change_type': 'moved'}));
    expect(t.changeLabel, '5:00 PM → 7:30 PM');
    expect(t.isCommitment, isFalse);
  });
}
