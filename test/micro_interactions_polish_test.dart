import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/theme/flow_haptics.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/components/flow_bottom_nav.dart';
import 'package:flowstate/components/right_now_task_card.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/screens/task_inbox_tab.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/screens/insights_tab.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Flowstate Micro-Interactions, Haptics, and Empty States', () {
    test('1. FlowHaptics utility executes safely across all feedback tiers', () async {
      // Test that none of the haptic utility methods throw unhandled exceptions
      await expectLater(FlowHaptics.lightTap(), completes);
      await expectLater(FlowHaptics.selection(), completes);
      await expectLater(FlowHaptics.success(), completes);
      await expectLater(FlowHaptics.warning(), completes);
    });

    test('2. ThemeProvider toggles between Light, Dark, and System modes and saves to SharedPreferences', () async {
      final themeProvider = ThemeProvider();
      await Future.delayed(const Duration(milliseconds: 50));

      // Default mode should be light
      expect(themeProvider.themeMode, ThemeMode.light);

      // Switch to Dark
      themeProvider.setThemeMode(ThemeMode.dark);
      expect(themeProvider.themeMode, ThemeMode.dark);
      final prefsDark = await SharedPreferences.getInstance();
      expect(prefsDark.getString('flowstate_theme_mode'), 'dark');

      // Switch to System
      themeProvider.setThemeMode(ThemeMode.system);
      expect(themeProvider.themeMode, ThemeMode.system);
      final prefsSystem = await SharedPreferences.getInstance();
      expect(prefsSystem.getString('flowstate_theme_mode'), 'system');

      // Switch back to Light
      themeProvider.setThemeMode(ThemeMode.light);
      expect(themeProvider.themeMode, ThemeMode.light);
      final prefsLight = await SharedPreferences.getInstance();
      expect(prefsLight.getString('flowstate_theme_mode'), 'light');
    });

    testWidgets('3. FlowBottomNav renders filled icon for active tab and outlined for inactive tabs', (WidgetTester tester) async {
      int activeIndex = 0;

      Widget buildNav(int index) {
        return MaterialApp(
          home: Scaffold(
            bottomNavigationBar: FlowBottomNav(
              currentIndex: index,
              onTap: (i) => activeIndex = i,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildNav(0));
      await tester.pumpAndSettle();

      // At index 0 (Today active):
      // Today should be Icons.today_rounded
      // Tasks should be Icons.assignment_outlined
      // Calendar should be Icons.calendar_month_outlined
      // Insights should be Icons.insights_outlined
      // Profile should be Icons.person_outline_rounded
      expect(find.byIcon(Icons.today_rounded), findsOneWidget);
      expect(find.byIcon(Icons.assignment_outlined), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
      expect(find.byIcon(Icons.insights_outlined), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);

      // Now tap Tasks (index 1) to trigger callback
      await tester.tap(find.byIcon(Icons.assignment_outlined));
      await tester.pumpAndSettle();
      expect(activeIndex, 1);

      // Now switch to Tasks (index 1)
      await tester.pumpWidget(buildNav(1));
      await tester.pumpAndSettle();

      // Today should now be Icons.today_outlined
      // Tasks should now be Icons.assignment_rounded
      expect(find.byIcon(Icons.today_outlined), findsOneWidget);
      expect(find.byIcon(Icons.assignment_rounded), findsOneWidget);
    });

    testWidgets('4. Major Empty States Audit: All 4 major tabs answer "What is happening? + What should I do?"', (WidgetTester tester) async {
      final appState = AppStateProvider();
      appState.clearAllTasksForNewUserState();
      final themeProvider = ThemeProvider();

      Widget wrapWithProviders(Widget child) {
        return MultiProvider(
          providers: [
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
            home: child,
          ),
        );
      }

      // 4a. Today Dashboard Empty State
      await tester.pumpWidget(wrapWithProviders(const TodayDashboardTab()));
      await tester.pumpAndSettle();
      expect(find.text("What's on your plate?"), findsOneWidget);
      expect(find.text("Tell Flowstate what you need to do and we'll shape your day."), findsOneWidget);
      expect(find.text('Build my day'), findsOneWidget);

      // 4b. Task Inbox Empty State
      await tester.pumpWidget(wrapWithProviders(const TaskInboxTab()));
      await tester.pumpAndSettle();
      expect(find.text('Your task inbox is clear'), findsOneWidget);
      expect(find.textContaining('Flowstate will organize and schedule them'), findsOneWidget);
      expect(find.text('Add task'), findsOneWidget);

      // 4c. Calendar Empty State
      await tester.pumpWidget(wrapWithProviders(const CalendarTab()));
      await tester.pumpAndSettle();
      expect(find.text('No scheduled events yet'), findsOneWidget);
      expect(find.textContaining('Connect your calendar or calibrate your day'), findsOneWidget);
      expect(find.text('Calibrate focus blocks'), findsOneWidget);

      // 4d. Insights Empty State (learning mode without fabricated stats)
      await tester.pumpWidget(wrapWithProviders(const InsightsTab()));
      await tester.pumpAndSettle();
      expect(find.text('Gathering your pattern data'), findsOneWidget);
      expect(find.textContaining('Flowstate never fabricates metrics'), findsOneWidget);
      expect(find.text('Go to Today plan'), findsOneWidget);
    });

    testWidgets('5. RightNowTaskCard provides tactile state transitions and responsive feedback', (WidgetTester tester) async {
      final appState = AppStateProvider();
      final task = appState.tasks.first;
      bool started = false;
      bool completed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RightNowTaskCard(
              task: task,
              onStart: () => started = true,
              onReschedule: () {},
              onComplete: () => completed = true,
              isRunning: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Why this?" accordion
      expect(find.text('Why this?'), findsOneWidget);
      await tester.tap(find.text('Why this?'));
      await tester.pumpAndSettle();
      expect(find.text('Due tomorrow'), findsOneWidget);

      // Tap "Start"
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();
      expect(started, isTrue);

      // Re-render in running state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RightNowTaskCard(
              task: task,
              onStart: () {},
              onReschedule: () {},
              onComplete: () => completed = true,
              isRunning: true,
              elapsedSeconds: 45,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Running · 00:45 elapsed'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Tap "Done"
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
    });
  });
}
