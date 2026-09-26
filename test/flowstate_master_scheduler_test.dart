import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/models/readiness_model.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/task_parse_service.dart';

class _MockTestApiService extends ApiService {
  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/tasks/batch-create-and-schedule') {
      return {'success': true, 'created_count': 3, 'tasks': []};
    }
    return {};
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/auth/me') {
      return {'id': 'user-1', 'email': 'test@flowstate.local'};
    }
    if (endpoint == '/api/v1/ai/status') {
      return {'is_pro': false, 'free_use_available': true, 'shields_available': 0};
    }
    return {};
  }
}

Widget _buildTestApp({required Widget child}) {
  final mockApi = _MockTestApiService();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStateProvider>(create: (_) => AppStateProvider(customApi: mockApi)),
      ChangeNotifierProvider<FlowProvider>(create: (_) => FlowProvider(api: mockApi)),
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
    ],
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: false,
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => child,
        ),
      ),
    ),
  );
}

void main() {
  group('Flowstate Master Scheduling Architecture Tests', () {
    test('1. Task Segmentation: "gym work assignment" splits into 3 tasks', () {
      final tasks = TaskParseService.deterministicFallbackParse('gym work assignment');
      expect(tasks.length, 3);
      expect(tasks[0].title, 'Gym');
      expect(tasks[0].taskType, TaskType.physical);
      expect(tasks[1].title, 'Work');
      expect(tasks[2].title, 'Assignment');
      expect(tasks[2].taskType, TaskType.study);
    });

    test('2. Task Segmentation: "finish my work assignment" remains 1 task', () {
      final tasks = TaskParseService.deterministicFallbackParse('finish my work assignment');
      expect(tasks.length, 1);
      expect(tasks[0].title.toLowerCase(), contains('assignment'));
    });

    test('3. Task Segmentation: "finish my Python assignment and submit it" remains 1 task', () {
      final tasks = TaskParseService.deterministicFallbackParse('finish my Python assignment and submit it');
      expect(tasks.length, 1);
      expect(tasks[0].title.toLowerCase(), contains('submit it'));
    });

    test('4. Current time = 18:22, important work, no deadline -> Recommended: Tomorrow morning', () {
      // 18:22 today
      final nowLocal = DateTime(2026, 9, 26, 18, 22);
      final scheduler = const SchedulingEngine();
      final task = TaskItem(
        id: 't1',
        title: 'Important work',
        durationMinutes: 90,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
        taskType: TaskType.deepWork,
        priority: TaskPriority.high,
        deadlineAt: null,
      );

      final eval = scheduler.evaluateCandidateSlot(task, nowLocal: nowLocal);
      expect(eval.dayOffset, 1, reason: 'Should recommend Tomorrow because past peak focus window today');
      expect(eval.slotStart.hour, 9);
      expect(eval.slotStart.minute, 30);
      expect(eval.slotDisplay, contains('Tomorrow'));
      expect(eval.explanation, contains("strongest focus window"));
    });

    test('5. Imminent deadline overrides preferred peak window -> Recommended: Today', () {
      final nowLocal = DateTime(2026, 9, 26, 18, 22);
      final tomorrowDeadline = DateTime(2026, 9, 27, 8, 0); // 8:00 AM tomorrow
      final scheduler = const SchedulingEngine();
      final task = TaskItem(
        id: 't2',
        title: 'Urgent client work',
        durationMinutes: 90,
        difficulty: TaskDifficulty.high,
        deadline: 'Due Tomorrow',
        deadlineAt: tomorrowDeadline,
        category: 'Work',
        taskType: TaskType.deepWork,
        priority: TaskPriority.high,
      );

      final eval = scheduler.evaluateCandidateSlot(task, nowLocal: nowLocal);
      expect(eval.dayOffset, 0, reason: 'Must schedule TODAY to meet tomorrow morning 8 AM deadline');
      expect(eval.slotStart.day, nowLocal.day);
      expect(eval.primaryReason, 'deadline_imminent');
      expect(eval.explanation, contains('protect your upcoming deadline'));
    });

    testWidgets('6. Preview Sheet renders Recommended time and Why explanation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _buildTestApp(
          child: ElevatedButton(
            key: const Key('open_sheet'),
            onPressed: () {},
            child: const Text('Open'),
          ),
        ),
      );

      final BuildContext ctx = tester.element(find.byKey(const Key('open_sheet')));
      showBrainDumpSheet(ctx);
      await tester.pumpAndSettle();

      // Enter input and tap Build my day
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym work assignment');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // Assert Recommended and Why are visible
      expect(find.textContaining('Recommended:'), findsWidgets);
      expect(find.textContaining('Why:'), findsWidgets);
      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
    });
  });
}
