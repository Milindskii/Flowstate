import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/task_parse_service.dart';
import 'package:flowstate/models/task_item.dart';

class MockP1ApiService extends ApiService {
  final List<Map<String, dynamic>> dbTasks = [];

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/auth/me') {
      return {
        'id': 'user-fresh-1',
        'email': 'fresh@flowstate.local',
        'name': 'Fresh User',
        'onboarding_completed': true,
      };
    }
    if (endpoint == '/api/v1/tasks') {
      return {'items': dbTasks, 'total': dbTasks.length};
    }
    if (endpoint == '/api/v1/today') {
      return {
        'user': {
          'id': 'user-fresh-1',
          'email': 'fresh@flowstate.local',
          'name': 'Fresh User',
          'timezone': 'UTC',
        },
        'date': '2026-09-21',
        'lifecycle_state': dbTasks.isEmpty ? 'new_user' : 'learning',
        'readiness': {
          'score': null,
          'max_score': 100,
          'confidence': 0.0,
          'model_version': 'readiness_v2.1',
          'status_message': 'Learning your rhythm',
          'focus_window_range': '9:30 AM – 11:30 AM',
          'explanation': "We're still learning when you work best.",
          'is_calibrated': false,
          'factors': [],
          'hourly_rhythm': [],
        },
        'current_recommendation': dbTasks.isNotEmpty
            ? {
                'task': dbTasks.first,
                'reasons': ['High priority', 'Strong focus window', 'Approaching deadline'],
              }
            : null,
        'ai_brief': {
          'title': 'FLOWSTATE',
          'message': dbTasks.isNotEmpty
              ? "You have ${dbTasks.length} important tasks today. I'd tackle ${dbTasks.first['title']} first."
              : "Let's build your day.",
          'action_label': 'Use this plan',
        },
        'workload_summary': {
          'planned_minutes': 165,
          'formatted_workload': '2h 45m planned',
          'message': 'Your day looks manageable.',
          'is_overloaded': false,
          'available_minutes': 390,
        },
        'active_task': null,
        'upcoming_timeline': [
          for (final t in dbTasks)
            {
              'id': 'sched-${t['id']}',
              'time': '9:30',
              'period': 'AM',
              'title': t['title'],
              'type': 'Deep Work',
              'tag_text': 'DEEP WORK',
              'is_active': false,
              'duration_minutes': t['estimated_minutes'],
            }
        ],
        'calendar_context': {'events_count': 0, 'next_event': null},
      };
    }
    return {};
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/tasks/parse') {
      // Simulate backend deterministic parser output for compound test prompt
      return [
        {
          'title': 'Finish ML assignment',
          'estimated_minutes': 45,
          'task_type': 'deep_work',
          'difficulty': 'high',
          'priority': 'high',
          'deadline': 'Due Tomorrow',
          'deadline_at': '2026-09-22T18:00:00Z',
          'category': 'College',
          'confidence': 0.71,
          'missing_fields': ['duration'],
          'ambiguities': [],
          'source': 'ai_parsed',
        },
        {
          'title': 'Study DBMS',
          'estimated_minutes': 60,
          'task_type': 'study',
          'difficulty': 'medium',
          'priority': 'medium',
          'category': 'College',
          'confidence': 0.88,
          'missing_fields': [],
          'ambiguities': [],
          'source': 'ai_parsed',
        },
        {
          'title': 'Go to gym',
          'estimated_minutes': 60,
          'task_type': 'physical',
          'difficulty': 'physical',
          'priority': 'low',
          'scheduled_time': '6:00 PM',
          'scheduled_start': '2026-09-21T18:00:00Z',
          'category': 'Fitness',
          'confidence': 0.70,
          'missing_fields': [],
          'ambiguities': ['time_am_pm'],
          'source': 'ai_parsed',
        },
      ];
    }
    if (endpoint == '/api/v1/tasks') {
      final taskMap = Map<String, dynamic>.from(body as Map);
      final realId = 'task-uuid-${dbTasks.length + 1}';
      taskMap['id'] = realId;
      taskMap['created_at'] = DateTime.now().toIso8601String();
      taskMap['updated_at'] = DateTime.now().toIso8601String();
      dbTasks.add(taskMap);
      return taskMap;
    }
    return {};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group("P1 Acceptance Test: End-to-End Real Tasks & Today Pipeline", () {
    test("Fresh user -> Login -> Tasks -> Compound prompt -> 3 candidates -> Confirm -> DB -> Today recommends one", () async {
      final mockApi = MockP1ApiService();
      final appState = AppStateProvider(customApi: mockApi);

      // Step 1: Login fresh user
      const freshUser = AuthUser(
        id: 'user-fresh-1',
        email: 'fresh@flowstate.local',
        name: 'Fresh User',
        onboardingCompleted: true,
      );
      await appState.onUserAuthenticated(freshUser);

      expect(appState.currentUser, isNotNull);
      expect(appState.isDemoMode, isFalse);
      expect(appState.tasks, isEmpty, reason: "Real authenticated user should have 0 mock tasks initially");

      // Step 2: User enters compound natural-language text in Tasks page:
      const compoundPrompt = "Finish ML assignment tomorrow, study DBMS for one hour, and go to gym at 6";
      final parseService = TaskParseService(api: mockApi);
      final candidates = await parseService.parseBrainDump(compoundPrompt);

      // Step 3: Must yield exactly 3 distinct task candidates
      expect(candidates.length, equals(3));

      final c1 = candidates[0];
      expect(c1.title, equals('Finish ML assignment'));
      expect(c1.difficulty, equals(TaskDifficulty.high));
      expect(c1.taskType, equals(TaskType.deepWork));
      expect(c1.deadline, equals('Due Tomorrow'));
      expect(c1.missingFields, contains('duration'));

      final c2 = candidates[1];
      expect(c2.title, equals('Study DBMS'));
      expect(c2.durationMinutes, equals(60));
      expect(c2.taskType, equals(TaskType.study));

      final c3 = candidates[2];
      expect(c3.title, equals('Go to gym'));
      expect(c3.taskType, equals(TaskType.physical));
      expect(c3.scheduledTime, equals('6:00 PM'));
      expect(c3.ambiguities, contains('time_am_pm'), reason: "Bare time number 6 flagged for AM/PM confirmation");

      // Step 4: Quick confirmation -> persists to database
      await appState.confirmCandidates(candidates);

      // Step 5: Tasks page shows them with real database IDs
      expect(appState.tasks.length, equals(3));
      expect(appState.tasks[0].id, startsWith('task-uuid-'));
      expect(mockApi.dbTasks.length, equals(3));

      // Step 6: Today fetches them and recommends one ("DO THIS NOW")
      expect(appState.recommendedTask, isNotNull);
      expect(appState.recommendedTask!.title, equals('Finish ML assignment'));
      expect(appState.todaySnapshot?.aiBrief.message, contains("Finish ML assignment"));
    });
  });
}
