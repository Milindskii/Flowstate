import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/today_model.dart';

/// Today's workload: remaining (actionable) minutes are separate from missed minutes kept for history.
void main() {
  test('missed minutes are parsed apart from the remaining planned minutes', () {
    final w = WorkloadSummaryModel.fromJson({
      'planned_minutes': 90,
      'formatted_workload': '1h 30m planned',
      'message': 'Your day looks manageable.',
      'is_overloaded': false,
      'available_minutes': 390,
      'missed_minutes': 45,
      'missed_count': 1,
    });
    expect(w.plannedMinutes, 90);
    expect(w.missedMinutes, 45);
    expect(w.missedCount, 1);
  });

  test('an older payload without the missed fields still parses (missed = 0)', () {
    final w = WorkloadSummaryModel.fromJson({'planned_minutes': 30});
    expect(w.plannedMinutes, 30);
    expect(w.missedMinutes, 0);
    expect(w.missedCount, 0);
  });

  test('missed fields survive the cache round trip', () {
    final back = WorkloadSummaryModel.fromJson(
      const WorkloadSummaryModel(plannedMinutes: 20, missedMinutes: 45, missedCount: 2).toJson(),
    );
    expect((back.plannedMinutes, back.missedMinutes, back.missedCount), (20, 45, 2));
  });
}
