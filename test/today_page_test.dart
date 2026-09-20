import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/screens/what_should_i_do_screen.dart';
import 'package:flowstate/components/timeline_current_time_marker.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/theme/flow_colors.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget createTestWidget({
    required AppStateProvider appState,
    ThemeProvider? themeProvider,
  }) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AppStateProvider>.value(value: appState),
        ChangeNotifierProvider<ThemeProvider>.value(
          value: themeProvider ?? ThemeProvider(),
        ),
      ],
      child: const MaterialApp(
        home: TodayDashboardTab(),
      ),
    );
  }

  testWidgets('1. Calibrated State: Renders 5-level action screen hierarchy (Header, Readiness, DO THIS NOW, Timeline, What Now)', (WidgetTester tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // 1. Header: Dynamic time-of-day greeting (not hardcoded)
    expect(find.textContaining('Good '), findsOneWidget);

    // 2. Compact Readiness: Contextual line and "Why?" affordance
    expect(find.text('Ready for a good session'), findsOneWidget);
    expect(find.text('Why?'), findsOneWidget);

    // Tap "Why?" to verify non-medical plain explanation bottom sheet
    await tester.tap(find.text('Why?'));
    await tester.pumpAndSettle();
    expect(find.text('Why this readiness estimate?'), findsOneWidget);
    expect(find.textContaining('recent sleep'), findsOneWidget);

    // Dismiss bottom sheet
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    // 3. Primary DO THIS NOW Recommendation (Hero centerpiece)
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(find.text('Start'), findsWidgets);
    expect(find.text('Later'), findsOneWidget);

    // 4. Timeline with NOW marker widget
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.byType(TimelineCurrentTimeMarker), findsOneWidget);

    // 5. Floating "What now?" escape hatch action
    expect(find.text('What now?'), findsOneWidget);
  });

  testWidgets('2. New User State: Renders "What\'s on your plate?" and uncalibrated state without fake scores', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.clearAllTasksForNewUserState();

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify greeting for new user
    expect(find.textContaining('👋'), findsOneWidget);

    // Verify Empty State callouts
    expect(find.text("What's on your plate?"), findsOneWidget);
    expect(find.text("Tell Flowstate what you need to do and we'll shape your day."), findsOneWidget);
    expect(find.text('Build my day'), findsOneWidget);
    expect(find.text('Tell Flowstate what I need to do'), findsOneWidget);
    expect(find.text('Add 3 tasks. We’ll help organize them.'), findsOneWidget);

    // Verify NO fake score is fabricated
    expect(find.textContaining('Readiness 78'), findsNothing);
    expect(find.textContaining('Readiness 82'), findsNothing);

    // What now pill should NOT be shown when there are no tasks
    expect(find.text('What now?'), findsNothing);
  });

  testWidgets('3. Learning State: Tasks present with insufficient history shows "Learning your rhythm"', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.setLearningStateForTesting();

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Readiness component shows "Learning your rhythm" and no fabricated score
    expect(find.text('Learning your rhythm'), findsOneWidget);
    expect(find.text("We're learning when you work best."), findsOneWidget);
    expect(find.textContaining('Readiness '), findsNothing);

    // Tasks are still scheduled and recommended deterministically as HERO
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(find.text('Review Machine Learning Architecture'), findsWidgets);
  });

  testWidgets('4. What Now Navigation: Opens simple decision sheet with 3 concise reasons', (WidgetTester tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Tap "What now?" floating pill
    await tester.tap(find.text('What now?'));
    await tester.pumpAndSettle();

    // Verify WhatShouldIDoScreen structure
    expect(find.byType(WhatShouldIDoScreen), findsOneWidget);
    expect(find.text('What should I do?'), findsOneWidget);
    expect(find.text("I'd do this:"), findsOneWidget);
    expect(
      find.descendant(of: find.byType(WhatShouldIDoScreen), matching: find.text('Why?')),
      findsOneWidget,
    );
    expect(find.text('Give me something easier →'), findsOneWidget);

    // Tap "Give me something easier →"
    await tester.tap(find.text('Give me something easier →'));
    await tester.pumpAndSettle();

    // Should switch to lower load alternative
    expect(find.byType(WhatShouldIDoScreen), findsOneWidget);
  });

  testWidgets('5. User Accent Customization: Alters theme accent color dynamically', (WidgetTester tester) async {
    final themeProvider = ThemeProvider();
    expect(themeProvider.selectedAccent, FlowAccent.cyan);
    expect(themeProvider.accentColor, FlowColors.accentCyan);

    await themeProvider.setAccent(FlowAccent.rose);
    expect(themeProvider.selectedAccent, FlowAccent.rose);
    expect(themeProvider.accentColor, FlowColors.accentRose);

    await themeProvider.setAccent(FlowAccent.lime);
    expect(themeProvider.selectedAccent, FlowAccent.lime);
    expect(themeProvider.accentColor, FlowColors.accentLime);
  });

  testWidgets('6. Responsiveness: Renders on small 320px and 360px screens without RenderFlex overflow', (WidgetTester tester) async {
    final appState = AppStateProvider();

    // 1. Test 320px width
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    expect(find.byType(TodayDashboardTab), findsOneWidget);
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 2. Test 360px width
    tester.view.physicalSize = const Size(360, 740);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('7. Take a Break Lifecycle: Real state transition into 15-minute recharge session, countdown, and return to task', (WidgetTester tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify initial task state
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(find.text('Take a break'), findsOneWidget);

    // Tap "Take a break" to start real 15-minute recharge session
    await tester.tap(find.text('Take a break'));
    await tester.pumpAndSettle();

    // Verify state transition into active break session
    expect(appState.isBreakActive, isTrue);
    expect(find.text('RECHARGE BREAK'), findsOneWidget);
    expect(find.text('Taking a breather'), findsOneWidget);
    expect(find.textContaining('remaining'), findsOneWidget);
    expect(find.text('Resume Work'), findsOneWidget);

    // Tap "Resume Work" to finish break and seamlessly return to recommended task
    await tester.tap(find.text('Resume Work'));
    await tester.pumpAndSettle();

    expect(appState.isBreakActive, isFalse);
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(find.text('Start'), findsWidgets);
  });

  testWidgets('8. Post-Task Completion: Shows feeling feedback sheet and records feedback', (WidgetTester tester) async {
    final appState = AppStateProvider();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Tap "Start" to begin focus session
    await tester.tap(find.text('Start').first);
    await tester.pumpAndSettle();

    // Verify Running status with Done button
    expect(find.text('Done'), findsOneWidget);

    // Tap "Done" to complete task
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Feedback bottom sheet appears
    expect(find.text('How did that feel?'), findsOneWidget);
    expect(find.text('😫'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);

    // Tap emoji reaction (4 = 🔥)
    await tester.tap(find.text('🔥'));
    await tester.pumpAndSettle();

    // Duration options appear
    expect(find.text('About right'), findsOneWidget);
    await tester.tap(find.text('About right'));
    await tester.pumpAndSettle();

    // Tap Done to submit feedback
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Verify feedback was recorded in learning engine
    expect(appState.learningEngine.history.isNotEmpty, isTrue);
  });
}
