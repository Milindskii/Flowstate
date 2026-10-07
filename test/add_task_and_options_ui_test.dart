import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flowstate/components/edit_task_sheet.dart';
import 'package:flowstate/components/task_card.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/add_task_sheet.dart';

void main() {
  group('Task 1: Add Task Date/Time UI & Persistence Tests', () {
    testWidgets('1. AddTaskSheet renders date/time pickers, quick presets, and attributes', (WidgetTester tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header & Close Button
      expect(find.text('Add Task'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      // Verify Title Input Field
      expect(find.byType(TextField), findsOneWidget);

      // Verify Shared Date & Time Picker Controls
      expect(find.byKey(const Key('add_task_date_button')), findsOneWidget);
      expect(find.byKey(const Key('add_task_time_button')), findsOneWidget);
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);

      // Verify Quick Date Preset Chips
      expect(find.byKey(const Key('add_task_preset_today')), findsOneWidget);
      expect(find.byKey(const Key('add_task_preset_tomorrow')), findsOneWidget);
      expect(find.byKey(const Key('add_task_preset_friday')), findsOneWidget);
      expect(find.byKey(const Key('add_task_preset_next_week')), findsOneWidget);

      // Verify Duration and Difficulty Controls
      expect(find.text('ESTIMATED DURATION'), findsOneWidget);
      expect(find.text('FOCUS REQUIREMENT'), findsOneWidget);
      expect(find.text('Medium priority'), findsOneWidget);

      // Verify CTA Button
      expect(find.byKey(const Key('add_task_submit_button')), findsOneWidget);
    });

    testWidgets('2. Tapping quick preset "Tomorrow" sets date to tomorrow and does not replace with today', (WidgetTester tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter task title
      await tester.enterText(find.byType(TextField), 'Prepare Q4 Product Roadmap');
      await tester.pumpAndSettle();

      // Tap "Tomorrow" preset
      await tester.tap(find.byKey(const Key('add_task_preset_tomorrow')));
      await tester.pumpAndSettle();

      // Date button must now display "Tomorrow"
      expect(find.text('Tomorrow'), findsWidgets);

      // Save task
      await tester.ensureVisible(find.byKey(const Key('add_task_submit_button')));
      await tester.tap(find.byKey(const Key('add_task_submit_button')));
      await tester.pumpAndSettle();

      // Verify task in appState
      final created = appState.tasks.firstWhere((t) => t.title == 'Prepare Q4 Product Roadmap');
      expect(created, isNotNull);
      expect(created.deadline, 'Tomorrow');
      expect(created.scheduledStart, isNotNull);

      // Verify date is indeed tomorrow, NOT today
      final now = DateTime.now();
      final expectedTomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
      expect(created.scheduledStart!.year, expectedTomorrow.year);
      expect(created.scheduledStart!.month, expectedTomorrow.month);
      expect(created.scheduledStart!.day, expectedTomorrow.day);
    });

    testWidgets('3. Date can be cleared back to unscheduled using clear date button', (WidgetTester tester) async {
      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: AddTaskSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Today" preset
      await tester.tap(find.byKey(const Key('add_task_preset_today')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add_task_clear_date')), findsOneWidget);

      // Clear the date
      await tester.tap(find.byKey(const Key('add_task_clear_date')));
      await tester.pumpAndSettle();

      // Date should show 'No date set'
      expect(find.text('No date set'), findsOneWidget);
    });

    testWidgets('4. Close button dismisses AddTaskSheet without saving', (WidgetTester tester) async {
      final appState = AppStateProvider();
      final initialCount = appState.tasks.length;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => showModalBottomSheet(
                    context: ctx,
                    builder: (_) => const AddTaskSheet(),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Add Task'), findsOneWidget);

      // Tap Close (X) button
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      // Sheet is gone and no task was created
      expect(find.text('Add Task'), findsNothing);
      expect(appState.tasks.length, initialCount);
    });
  });

  group('Task 2: Task Options Menu UI & Safety Tests', () {
    testWidgets('5. TaskCard options menu displays context header, all working actions, and distinct delete section', (WidgetTester tester) async {
      const task = TaskItem(
        id: 'opt-task-1',
        title: 'Review System Design Document',
        durationMinutes: 45,
        difficulty: TaskDifficulty.high,
        deadline: 'Tomorrow',
        category: 'Work',
      );

      final appState = AppStateProvider();
      appState.addTask(
        title: 'Review System Design Document',
        durationMinutes: 45,
        difficulty: TaskDifficulty.high,
        deadline: 'Tomorrow',
        category: 'Work',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: task,
                onToggleComplete: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the more options button (three dots)
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Context Header
      expect(find.text('Review System Design Document'), findsWidgets);
      expect(find.textContaining('45 min'), findsWidgets);

      // Core actions
      expect(find.text('Start Focus Session'), findsOneWidget);
      expect(find.text('Mark as Done'), findsOneWidget);
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.text('Reschedule / Later'), findsOneWidget);

      // Destructive section
      expect(find.text('Delete Task'), findsOneWidget);
      expect(find.text('Permanently remove this task'), findsOneWidget);
    });

    testWidgets('6. Tapping Delete Task requires confirmation dialog before deletion', (WidgetTester tester) async {
      final appState = AppStateProvider();
      final created = await appState.addTask(
        title: 'Task To Delete Safely',
        durationMinutes: 30,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Personal',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: created,
                onToggleComplete: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open options menu
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      // Tap Delete Task
      await tester.tap(find.text('Delete Task'));
      await tester.pumpAndSettle();

      // Confirmation dialog must appear
      expect(find.text('Delete Task?'), findsOneWidget);
      expect(find.text('Are you sure you want to delete "Task To Delete Safely"? This action cannot be undone.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Cancel -> task is NOT deleted
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(appState.tasks.any((t) => t.id == created.id), isTrue);

      // Re-open and confirm Delete
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete Task'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Task is now safely removed
      expect(appState.tasks.any((t) => t.id == created.id), isFalse);
    });

    testWidgets('7. EditTaskSheet includes Delete Task with confirmation dialog', (WidgetTester tester) async {
      final appState = AppStateProvider();
      final created = await appState.addTask(
        title: 'Task In Edit Sheet',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: EditTaskSheet(task: created),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find Delete Task button
      expect(find.text('Delete Task'), findsOneWidget);

      // Tap Delete Task
      await tester.tap(find.text('Delete Task'));
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Delete Task?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Task removed from appState
      expect(appState.tasks.any((t) => t.id == created.id), isFalse);
    });
  });
}
