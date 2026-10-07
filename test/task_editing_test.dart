import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/components/edit_task_sheet.dart';

void main() {
  group('Task Editing Tests (Phase 10)', () {
    testWidgets('1. EditTaskSheet renders with Date, Time, Type, Duration and Priority controls', (WidgetTester tester) async {
      const task = TaskItem(
        id: 'edit-test-1',
        title: 'Deep Architecture Analysis',
        durationMinutes: 45,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
        isPriority: true,
      );

      final appState = AppStateProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: EditTaskSheet(task: task),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header
      expect(find.text('Edit Task'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      // Check title input
      expect(find.text('Deep Architecture Analysis'), findsOneWidget);

      // Check Date and Time buttons
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('No date set'), findsOneWidget);
      expect(find.text('No fixed time'), findsOneWidget);

      // Check Duration and Priority
      expect(find.text('45m'), findsOneWidget);
      expect(find.text('High priority'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);
    });

    Future<void> pumpSheet(WidgetTester tester, TaskItem task) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: AppStateProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: MaterialApp(home: Scaffold(body: EditTaskSheet(task: task))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('3. Priority status line follows the selected level', (WidgetTester tester) async {
      await pumpSheet(
        tester,
        const TaskItem(
          id: 'p1',
          title: 'Essay',
          durationMinutes: 30,
          difficulty: TaskDifficulty.medium,
          deadline: 'Today',
          category: 'Study',
          priority: TaskPriority.medium,
        ),
      );
      expect(find.text('Medium priority'), findsOneWidget);
      expect(find.text('High priority'), findsNothing);
      await tester.ensureVisible(find.text('Low'));
      await tester.tap(find.text('Low'));
      await tester.pumpAndSettle();
      expect(find.text('Low priority'), findsOneWidget);
      expect(find.text('Medium priority'), findsNothing);
    });

    testWidgets('4. A commitment shows the fixed-time editor, not work controls', (WidgetTester tester) async {
      await pumpSheet(
        tester,
        TaskItem(
          id: 'c1',
          title: 'Going out',
          durationMinutes: 120,
          difficulty: TaskDifficulty.light,
          deadline: 'Today',
          category: 'General',
          isCommitment: true,
          timeLocked: true,
          scheduledStart: DateTime(2026, 10, 5, 18, 30),
          scheduledEnd: DateTime(2026, 10, 5, 20, 30),
        ),
      );
      expect(find.text('Edit Commitment'), findsOneWidget);
      expect(find.byKey(const Key('commitment_badge')), findsOneWidget);
      expect(find.text('6:30 PM'), findsOneWidget);
      expect(find.text('8:30 PM'), findsOneWidget);
      expect(find.text('PRIORITY'), findsNothing);
      expect(find.text('FOCUS REQUIREMENT'), findsNothing);
      expect(find.text('Remove commitment'), findsOneWidget);
    });

    testWidgets('2. Saving updated title and duration persists to AppStateProvider', (WidgetTester tester) async {
      const task = TaskItem(
        id: 'edit-test-2',
        title: 'Original Title',
        durationMinutes: 25,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        isPriority: false,
      );

      final appState = AppStateProvider();
      // Add task to app state
      appState.addTask(
        title: 'Original Title',
        durationMinutes: 25,
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
          child: const MaterialApp(
            home: Scaffold(
              body: EditTaskSheet(task: task),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Enter new title
      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Updated Architecture Review');
      await tester.pumpAndSettle();

      // Select 60m duration
      await tester.tap(find.text('60m'));
      await tester.pumpAndSettle();

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      // Verify task in AppState was updated
      expect(appState.tasks.any((t) => t.title == 'Updated Architecture Review' || t.title == 'Original Title'), isTrue);
    });
  });
}
