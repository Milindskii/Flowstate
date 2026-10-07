import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/flow_clock.dart';

TaskItem _t(String id, {bool done = false}) => TaskItem(
      id: id,
      title: 'Task $id',
      durationMinutes: 30,
      difficulty: TaskDifficulty.medium,
      deadline: 'Today',
      category: 'Work',
      isCompleted: done,
    );

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  test('a completion reaches Noya exactly once, with whether it finished the day', () {
    final state = AppStateProvider()..setTasksForTesting([_t('a'), _t('b')]);
    final calls = <(String, bool)>[];
    state.onTaskCompletedForNoya = (task, {required bool lastOfDay}) => calls.add((task.id, lastOfDay));

    state.toggleTaskCompletion('a');
    expect(calls, [('a', false)]);

    state.toggleTaskCompletion('b');
    expect(calls, [('a', false), ('b', true)]);
  });

  test('un-completing never reacts; completion via a Calendar id still reacts once', () {
    final state = AppStateProvider()..setTasksForTesting([_t('a', done: true), _t('b')]);
    var count = 0;
    state.onTaskCompletedForNoya = (_, {required bool lastOfDay}) => count++;

    state.toggleTaskCompletion('a'); // un-complete
    expect(count, 0);

    state.toggleTaskCompletion('sched-b');
    expect(count, 1);
  });
}
