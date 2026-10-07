import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';

/// M2 Step 0 (spec §3 S3 vs S7): a task confirmed with an explicit time ("gym at 4pm")
/// is persisted with time_locked=true. The backend renders it as is_fixed (covered by
/// backend/tests/test_e2e_build_and_replan.py). The client-built Calendar day — used in
/// demo mode and as the offline fallback — dropped the lock, so the same task showed as a
/// default "Scheduled by Flowstate" row.
void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => FlowClock().stopTimer());

  final now = FlowClock().now;
  final day = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

  List<TaskItem> confirmedTasks() => [
        TaskItem(
          id: 'task-gym',
          title: 'Go to the gym',
          durationMinutes: 60,
          difficulty: TaskDifficulty.medium,
          deadline: 'Tomorrow',
          category: 'Health',
          taskType: TaskType.physical,
          scheduledStart: DateTime(day.year, day.month, day.day, 16),
          timeLocked: true,
        ),
        TaskItem(
          id: 'task-flex',
          title: 'Write outline',
          durationMinutes: 45,
          difficulty: TaskDifficulty.medium,
          deadline: 'Tomorrow',
          category: 'Work',
          scheduledStart: DateTime(day.year, day.month, day.day, 10),
        ),
      ];

  Future<void> expectFixedState(AppStateProvider provider) async {
    provider.setTasksForTesting(confirmedTasks());
    await provider.loadCalendarDay(day);

    final timeline = provider.selectedDateSchedule!.timeline;
    final gym = timeline.firstWhere((i) => i.taskId == 'task-gym');
    final flex = timeline.firstWhere((i) => i.taskId == 'task-flex');

    expect(gym.isFixed, isTrue, reason: 'user-fixed time must render as Fixed in Calendar');
    expect(gym.tagText, 'FIXED');
    expect(flex.isFixed, isFalse);
    expect(flex.tagText, isNot('FIXED'));
    expect(provider.selectedDateSchedule!.fixedCommitments.map((i) => i.taskId), ['task-gym']);
  }

  test('offline fallback keeps a time-locked task fixed in Calendar', () async {
    final api = ApiService(client: MockClient((_) async => http.Response('down', 503)));
    final provider = AppStateProvider(customApi: api);
    provider.setDemoMode(false);
    await expectFixedState(provider);
  });

  test('demo mode keeps a time-locked task fixed in Calendar', () async {
    final provider = AppStateProvider(customApi: ApiService(client: MockClient((_) async => http.Response('{}', 200))));
    provider.setDemoMode(true);
    await expectFixedState(provider);
  });
}
