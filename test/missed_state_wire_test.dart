import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/models/calendar_models.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

// Replan M5: missed is derived by the server and carried on `state`; a missed task never leads "do this now".
TaskItem task(String id, {DateTime? start, DateTime? planned}) => TaskItem(
      id: id,
      title: id,
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'General',
      status: TaskStatus.todo,
      scheduledStart: start,
      scheduledEnd: start?.add(const Duration(minutes: 30)),
      plannedDate: planned,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  Map<String, dynamic> item(String id, Map<String, dynamic> extra) => {
        'id': id,
        'task_id': 't-$id',
        'title': id,
        'start_time': '2026-10-05T18:00:00+05:30',
        'end_time': '2026-10-05T19:00:00+05:30',
        'time': '6:00',
        'period': 'PM',
        'duration_minutes': 60,
        'type': 'deep_work',
        'tag_text': 'DEEP WORK',
        ...extra,
      };

  test('server state and the missed history node survive parse and round trip', () {
    final r = DayScheduleResponse.fromJson({
      'date': '2026-10-05',
      'timeline': [item('c', {'state': 'missed', 'is_missed': true})],
      'deviations': [item('dev-1', {'state': 'missed', 'is_missed': true, 'deviation': 'missed'})],
    });
    expect(r.timeline.single.state, 'missed');
    expect(r.timeline.single.isMissed, isTrue);
    expect(r.deviations.single.deviation, 'missed');
    expect(ScheduleItem.fromJson(r.toJson()['timeline'][0] as Map<String, dynamic>).state, 'missed');
    expect(ScheduleItem.fromJson(item('x', {})).state, isNull); // older servers
  });

  test('a missed task never leads do-this-now; an actionable task does', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final missed = task('missed', start: now.subtract(const Duration(hours: 2)), planned: today);
    final open = task('open', planned: today);
    final state = AppStateProvider()..setTasksForTesting([missed, open]);
    expect(state.recommendedTask?.id, 'open');
    state.setTasksForTesting([missed]);
    expect(state.recommendedTask?.id, isNot('missed'));
  });
}
