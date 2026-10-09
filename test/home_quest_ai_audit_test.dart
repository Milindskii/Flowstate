import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/add_task_sheet.dart';
import 'package:flowstate/screens/flow_screen.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  Widget buildTestableWidget({
    required AppStateProvider appState,
    FlowProvider? flowProvider,
    Widget? child,
  }) {
    if (!appState.isAuthenticated) {
      appState.setCurrentUserForTesting(const AuthUser(
        id: 'test-user-1',
        email: 'tester@flowstate.local',
        name: 'Tester',
        onboardingCompleted: true,
      ));
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<FlowProvider>.value(
          value: flowProvider ?? FlowProvider(),
        ),
      ],
      child: MaterialApp(
        home: child ?? const TodayDashboardTab(),
      ),
    );
  }

  group('TASK 1: Home Screen "All Done" vs "Clear For Now" States', () {
    testWidgets('1. Completing every task while the day is active shows sleeping Noya, "All done for today!" and Add more tasks', (tester) async {
      final appState = AppStateProvider();
      final flowProvider = FlowProvider();

      // Configure daytime bedtime (bedtime at 23:59 so day remains active)
      appState.updatePersonalData(appState.personalData.copyWith(bedtime: '23:59'));
      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Complete single important task',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      // Verify task exists
      expect(appState.tasks.length, 1);
      expect(appState.tasks.first.isCompleted, isFalse);

      // Complete the single task
      appState.toggleTaskCompletion(appState.tasks.first.id);
      expect(appState.tasks.first.isCompleted, isTrue);

      // Wire progression
      appState.onTaskCompletedForFlow = () {
        flowProvider.recordTaskCompletionLocally();
      };

      await tester.pumpWidget(buildTestableWidget(
        appState: appState,
        flowProvider: flowProvider,
      ));
      await tester.pumpAndSettle();

      // Verify it does NOT prematurely declare the day is over
      expect(find.text("You're all done for today. 🦊"), findsNothing);
      expect(find.text("You're all done for today 🦊"), findsNothing);

      // One calm all-done message with Noya asleep; the day itself is not declared over (no wind-down copy)
      expect(find.text('All done for today!'), findsOneWidget);
      expect(find.text('Nice work. Rest, or add a little more.'), findsOneWidget);
      expect(find.text('Nice work. Time to wind down.'), findsNothing);
      final noya = tester.widget<NoyaCompanionView>(find.byKey(const Key('all_done_noya')));
      expect(noya.state, NoyaState.sleepy);

      // Verify actions: Add more tasks (primary) and Build My Day (secondary)
      expect(find.text('Add more tasks'), findsOneWidget);
      expect(find.text('Build My Day'), findsOneWidget);
      expect(find.byKey(const Key('completed_state_primary_button')), findsOneWidget);
      expect(find.byKey(const Key('completed_state_secondary_button')), findsOneWidget);
    });

    testWidgets('2. Tapping "Add more tasks" on the all-done state opens Add Task modal', (tester) async {
      final appState = AppStateProvider();
      appState.updatePersonalData(appState.personalData.copyWith(bedtime: '23:59'));
      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Quick Task',
        durationMinutes: 25,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Personal',
      );
      appState.toggleTaskCompletion(appState.tasks.first.id);

      await tester.pumpWidget(buildTestableWidget(appState: appState));
      await tester.pumpAndSettle();

      // Tap primary action "Add more tasks"
      await tester.tap(find.text('Add more tasks'));
      await tester.pumpAndSettle();

      // Verify AddTaskSheet is opened
      expect(find.byType(AddTaskSheet), findsOneWidget);
      expect(find.text('What needs to get done?'), findsOneWidget);
    });

    testWidgets('3. Tapping "Build My Day" on clear-for-now state opens AI planner', (tester) async {
      final appState = AppStateProvider();
      appState.updatePersonalData(appState.personalData.copyWith(bedtime: '23:59'));
      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Task Alpha',
        durationMinutes: 30,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
      );
      appState.toggleTaskCompletion(appState.tasks.first.id);

      await tester.pumpWidget(buildTestableWidget(appState: appState));
      await tester.pumpAndSettle();

      // Tap secondary action "Build My Day"
      await tester.tap(find.text('Build My Day'));
      await tester.pumpAndSettle();

      // Verify Brain Dump sheet is opened
      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);
      expect(find.textContaining('Build My Day with Noya'), findsOneWidget);
    });

    testWidgets('4. Completing all tasks at or past configured bedtime displays "All done for today!" and "Plan tomorrow"', (tester) async {
      final appState = AppStateProvider();
      // Configure bedtime to an hour in the past
      final now = DateTime.now();
      final pastHour = (now.hour - 1).clamp(0, 23);
      final pad = pastHour.toString().padLeft(2, '0');
      appState.updatePersonalData(appState.personalData.copyWith(bedtime: '$pad:00'));
      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Late evening wrap up',
        durationMinutes: 15,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Personal',
      );
      appState.toggleTaskCompletion(appState.tasks.first.id);

      await tester.pumpWidget(buildTestableWidget(appState: appState));
      await tester.pumpAndSettle();

      expect(find.text('All done for today!'), findsOneWidget);
      expect(find.text('Add more tasks'), findsOneWidget);
      expect(find.text("Nice work. Time to wind down."), findsOneWidget);
      expect(find.text('Plan tomorrow'), findsOneWidget);
    });
  });

  group('TASK 2: AI Discoverability in Add Task Sheet', () {
    testWidgets('1. AddTaskSheet displays prominent "✨ Build with AI" banner near top', (tester) async {
      final appState = AppStateProvider();
      await tester.pumpWidget(buildTestableWidget(
        appState: appState,
        child: const Scaffold(body: AddTaskSheet()),
      ));
      await tester.pumpAndSettle();

      // Verify header and manual input field
      expect(find.text('Add Task'), findsOneWidget);
      expect(find.text('What needs to get done?'), findsOneWidget);

      // Verify AI discovery banner is clearly visible near the top
      expect(find.byKey(const Key('add_task_build_with_ai_button')), findsOneWidget);
      expect(find.text('✨ Build with AI'), findsOneWidget);
      expect(
        find.text('Describe what you need to get done in your own words'),
        findsOneWidget,
      );
    });

    testWidgets('2. Tapping "✨ Build with AI" opens BrainDumpSheet with prefilled text', (tester) async {
      final appState = AppStateProvider();
      await tester.pumpWidget(buildTestableWidget(
        appState: appState,
        child: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: ctx,
                  builder: (_) => const AddTaskSheet(),
                );
              },
              child: const Text('Open Add Task'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Open Add Task sheet
      await tester.tap(find.text('Open Add Task'));
      await tester.pumpAndSettle();

      // Enter some thoughts in the text field
      await tester.enterText(find.byType(TextField), 'Complete research report by 4pm');
      await tester.pumpAndSettle();

      // Tap "✨ Build with AI"
      await tester.tap(find.byKey(const Key('add_task_build_with_ai_button')));
      await tester.pumpAndSettle();

      // Verify BrainDumpSheet is opened and populated with typed text
      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);
      expect(find.textContaining('Build My Day with Noya'), findsOneWidget);
      expect(find.text('Complete research report by 4pm'), findsOneWidget);
    });
  });

  group('TASK 3 & 4: Quest Progress & Task Completion Consistency', () {
    test('1. FlowProvider.recordTaskCompletionLocally increments finish_2_tasks quest progress', () {
      final flowProvider = FlowProvider();
      final initialQuest = flowProvider.dailyQuests.firstWhere((q) => q.questKey == 'finish_2_tasks');
      expect(initialQuest.currentCount, 0);
      expect(initialQuest.targetCount, 2);
      expect(initialQuest.isCompleted, isFalse);

      // Record first task completion
      flowProvider.recordTaskCompletionLocally();
      final quest1 = flowProvider.dailyQuests.firstWhere((q) => q.questKey == 'finish_2_tasks');
      expect(quest1.currentCount, 1);
      expect(quest1.isCompleted, isFalse);

      // Record second task completion
      flowProvider.recordTaskCompletionLocally();
      final quest2 = flowProvider.dailyQuests.firstWhere((q) => q.questKey == 'finish_2_tasks');
      expect(quest2.currentCount, 2);
      expect(quest2.isCompleted, isTrue);
    });

    testWidgets('2. Completing a task in AppState updates Quest page state reactively', (tester) async {
      final appState = AppStateProvider();
      final flowProvider = FlowProvider();
      flowProvider.setMockMode(true);

      // Wire progression listener as MainShell does
      appState.onTaskCompletedForFlow = () {
        flowProvider.recordTaskCompletionLocally();
      };

      // Add a task
      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Quest test task',
        durationMinutes: 25,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Study',
      );

      // Pump Living Flow Hub (FlowScreen) on Quests tab
      await tester.pumpWidget(buildTestableWidget(
        appState: appState,
        flowProvider: flowProvider,
        child: const FlowScreen(),
      ));
      await tester.pumpAndSettle();

      // Switch to Quests tab
      await tester.tap(find.text('Quests'));
      await tester.pumpAndSettle();

      expect(find.text('TODAY’S QUESTS'), findsOneWidget);
      expect(find.text('0 / 2'), findsOneWidget);

      // Complete the task in AppState
      appState.toggleTaskCompletion(appState.tasks.first.id);
      await tester.pumpAndSettle();

      // Quest tab must now reflect 1 / 2 progress!
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('3. Quest page retains updated progress after navigating away and returning', (tester) async {
      final appState = AppStateProvider();
      final flowProvider = FlowProvider();
      flowProvider.setMockMode(true);

      appState.onTaskCompletedForFlow = () {
        flowProvider.recordTaskCompletionLocally();
      };

      appState.clearAllTasksForNewUserState();
      appState.addTask(
        title: 'Task 1',
        durationMinutes: 25,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Study',
      );

      // Complete task
      appState.toggleTaskCompletion(appState.tasks.first.id);

      // Verify FlowProvider has 1 / 2
      final quest = flowProvider.dailyQuests.firstWhere((q) => q.questKey == 'finish_2_tasks');
      expect(quest.currentCount, 1);

      // Mount FlowScreen, verify Quests tab
      await tester.pumpWidget(buildTestableWidget(
        appState: appState,
        flowProvider: flowProvider,
        child: const FlowScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quests'));
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);

      // Switch to Badges tab (navigate away)
      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ACHIEVEMENTS'), findsOneWidget);

      // Switch back to Quests tab (return)
      await tester.tap(find.text('Quests'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
    });

    test('4. FlowProvider persists completion state to cache and restores offline', () async {
      SharedPreferences.setMockInitialValues({});
      final flowProvider = FlowProvider();

      // Record completion
      flowProvider.recordTaskCompletionLocally();
      final quest = flowProvider.dailyQuests.firstWhere((q) => q.questKey == 'finish_2_tasks');
      expect(quest.currentCount, 1);

      // Wait for async cache write
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify SharedPreferences has cached overview
      final prefs = await SharedPreferences.getInstance();
      final cachedStr = prefs.getString('flowstate_flow_overview_cache');
      expect(cachedStr, isNotNull);
      expect(cachedStr, contains('"current_count":1'));
    });
  });
}
