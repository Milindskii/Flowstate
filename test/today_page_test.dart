import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/screens/what_should_i_do_screen.dart';
import 'package:flowstate/screens/focus_ritual_screen.dart';
import 'package:flowstate/components/timeline_current_time_marker.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/theme/flow_colors.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/screens/main_shell.dart';
import 'package:flowstate/components/flow_bottom_nav.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/screens/add_task_sheet.dart';

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
    FocusRitualScreen.defaultSkipCountdown = true;
    FocusRitualScreen.defaultTimerControllerFactory =
        (t) => FakeFocusTimerController(targetSeconds: t);
  });

  tearDown(() {
    FlowClock().stopTimer();
    FocusRitualScreen.defaultSkipCountdown = false;
    FocusRitualScreen.defaultTimerControllerFactory = null;
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
      child: MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const TodayDashboardTab(),
      ),
    );
  }

  testWidgets('1. Calibrated State: Renders 5-level action screen hierarchy (Header, Readiness, DO THIS NOW, Timeline, What Now)', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.setCalibratedStateForTesting();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // 1. Header: Dynamic time-of-day greeting (not hardcoded)
    expect(find.textContaining('Good '), findsOneWidget);

    // 2. Compact Readiness: Contextual line and "Why?" affordance
    expect(find.text('YOUR RHYTHM'), findsOneWidget);
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
    expect(find.textContaining('Start'), findsWidgets);
    expect(find.text('Later'), findsOneWidget);

    // 4. Timeline with NOW marker widget
    expect(find.text('UP NEXT'), findsOneWidget);
    expect(find.byType(TimelineCurrentTimeMarker), findsOneWidget);

    // 5. Floating "What now?" escape hatch action
    expect(find.text('What now?'), findsOneWidget);
  });

  testWidgets('2. New User State: Renders "What do you need to get done?" and uncalibrated state without fake scores', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.clearAllTasksForNewUserState();

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify greeting for new user
    expect(find.textContaining('👋'), findsOneWidget);

    // Verify Empty State callouts
    expect(find.text("What's on your plate?"), findsOneWidget);
    expect(find.text("Add everything you need to get done and we'll organize it."), findsOneWidget);
    expect(find.text('Build my day'), findsOneWidget);
    expect(find.text('+ Add one task'), findsOneWidget);
    expect(find.text('Dump everything at once or add tasks individually.'), findsOneWidget);
    expect(find.text('✦ FLOW'), findsOneWidget);
    expect(find.text('Lock in with Noya.'), findsOneWidget);
    expect(find.text('25 minutes. One thing. No distractions.'), findsOneWidget);
    expect(find.text('Start Flow'), findsOneWidget);

    // Verify removed clutter is not present
    expect(find.text('Your day is empty'), findsNothing);
    expect(find.text('Add your task'), findsNothing);
    expect(find.text('+ Add your first task'), findsNothing);
    expect(find.text('Tell Flowstate what I need to do'), findsNothing);
    expect(find.text('Add 3 tasks. We’ll help organize them.'), findsNothing);

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
    appState.setCalibratedStateForTesting();
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
    appState.setCalibratedStateForTesting();

    // 1. Test 320px width
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

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
    appState.setCalibratedStateForTesting();
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
    expect(find.textContaining('Start'), findsWidgets);
  });

  testWidgets('8. Post-Task Completion: Shows feeling feedback sheet and records feedback', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appState = AppStateProvider();
    appState.setCalibratedStateForTesting();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Tap "Start Focus" to begin canonical Focus Ritual session
    await tester.tap(find.textContaining('Start').first);
    await tester.pumpAndSettle();

    // Verify Focus Ritual Screen is open with Done action
    expect(find.byType(FocusRitualScreen), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // Tap "Done" to complete session
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Mode A (Task focus) prompts task completion status
    if (find.text('Yes, mark complete').evaluate().isNotEmpty) {
      await tester.tap(find.text('Yes, mark complete'));
      await tester.pumpAndSettle();
    }

    // Feedback section appears in scrollable view
    await tester.ensureVisible(find.text('How did that feel?'));
    expect(find.text('How did that feel?'), findsOneWidget);
    expect(find.text('😫'), findsOneWidget);
    expect(find.text('🔥'), findsOneWidget);

    // Tap emoji reaction (4 = 🔥)
    await tester.ensureVisible(find.text('🔥'));
    await tester.tap(find.text('🔥'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Duration options appear
    await tester.ensureVisible(find.text('About right'));
    expect(find.text('About right'), findsOneWidget);
    await tester.tap(find.text('About right'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Tap Done to submit feedback
    await tester.ensureVisible(find.text('Done'));
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Verify feedback was recorded in learning engine
    expect(appState.learningEngine.history.isNotEmpty, isTrue);
  });

  testWidgets('9. Free Flow Mode: Completes without task completion prompt', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const FocusRitualScreen(task: null, initialMinutes: 25),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Flow'), findsOneWidget);
    expect(find.textContaining('Focus with Noya'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    // Tap Done to finish Free Flow
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    // Mode B must NOT ask "Finished the task?"
    expect(find.textContaining('Finished the task?'), findsNothing);
    expect(find.text('Flow Complete 🎉'), findsOneWidget);
  });

  testWidgets('10. Regression Test: Normal Focus navigation launches FocusRitualScreen with radial timer and no horizontal timer', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.setCalibratedStateForTesting();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify Start Focus button exists on Today
    expect(find.text('Start Focus'), findsOneWidget);

    // Tap Start Focus
    await tester.tap(find.text('Start Focus'));
    await tester.pumpAndSettle();

    // Canonical FocusRitualScreen is open
    expect(find.byType(FocusRitualScreen), findsOneWidget);

    // Center radial ring is present (FocusRadialTimerPainter)
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FocusRadialTimerPainter),
      findsOneWidget,
    );

    // Legacy horizontal timer bar must NOT be visible
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('11. Regression Test: 3-2-1 Countdown Ritual displays before radial focus stage', (WidgetTester tester) async {
    // Reset skip countdown to explicitly test 3-2-1 ritual flow
    FocusRitualScreen.defaultSkipCountdown = false;

    final appState = AppStateProvider();
    appState.setCalibratedStateForTesting();
    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Tap Start Focus
    expect(find.text('Start Focus'), findsOneWidget);
    await tester.tap(find.text('Start Focus'));
    await tester.pump(); // Initiate route push
    await tester.pump(const Duration(milliseconds: 300)); // Finish route push transition

    // 3-2-1 countdown screen is visible
    expect(find.byType(FocusRitualScreen), findsOneWidget);
    expect(find.text('GET READY TO FOCUS'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // Advance 900ms -> countdown to 2
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('2'), findsOneWidget);

    // Advance 900ms -> countdown to 1
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('1'), findsOneWidget);

    // Complete countdown into active radial focus stage
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pumpAndSettle();

    // Active radial timer is now visible
    expect(
      find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FocusRadialTimerPainter),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('12. Fresh authenticated user + successful /today with 0 tasks renders empty state, NOT offline error', (WidgetTester tester) async {
    final appState = AppStateProvider();
    await appState.onUserAuthenticated(const AuthUser(
      id: 'fresh-user-1',
      email: 'fresh@flowstate.app',
      name: 'FreshUser',
      onboardingCompleted: true,
    ));
    appState.setTodayNetworkStateForTesting(TodayNetworkState.emptySuccess);

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify empty state is cleanly rendered with Action Launchpad
    expect(find.text("What's on your plate?"), findsOneWidget);
    expect(find.text('Build my day'), findsOneWidget);
    expect(find.text('+ Add one task'), findsOneWidget);
    expect(find.text('✦ FLOW'), findsOneWidget);
    expect(find.text('Start Flow'), findsOneWidget);

    // Verify tapping "+ Add one task" opens normal task creation sheet
    await tester.tap(find.text('+ Add one task'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTaskSheet), findsOneWidget);

    // Verify NO offline or server error screen is displayed
    expect(find.text('We couldn’t update your plan.'), findsNothing);
    expect(find.text('Check your connection or try again.'), findsNothing);
    expect(find.text('Server error'), findsNothing);
  });

  testWidgets('13. Network failure with 0 tasks renders usable empty state with redirect, never a blank offline error', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.clearAllTasksForNewUserState();
    appState.setTodayNetworkStateForTesting(
      TodayNetworkState.networkFailure,
      errorMessage: 'We couldn’t update your plan.',
    );

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify that Today page does NOT show a blank screen or blocking full-screen error
    expect(find.text('Check your connection or try again.'), findsNothing);
    expect(find.text('Retry'), findsNothing);

    // Verify empty state is rendered with Action Launchpad
    expect(find.text("What's on your plate?"), findsOneWidget);
    expect(find.text('Build my day'), findsOneWidget);
    expect(find.text('+ Add one task'), findsOneWidget);
    expect(find.text('Offline mode. Tasks you add will sync when connected.'), findsNothing);

    // Verify tapping "+ Add one task" opens normal task creation sheet
    await tester.tap(find.text('+ Add one task'));
    await tester.pumpAndSettle();
    expect(find.byType(AddTaskSheet), findsOneWidget);
  });

  testWidgets('14. Tasks present renders normal Today with YOUR RHYTHM, DO THIS NOW, YOUR FLOW, UP NEXT', (WidgetTester tester) async {
    final appState = AppStateProvider();
    appState.setCalibratedStateForTesting();
    appState.setTodayNetworkStateForTesting(TodayNetworkState.tasksSuccess);

    await tester.pumpWidget(createTestWidget(appState: appState));
    await tester.pumpAndSettle();

    // Verify the 4 distinct section badges
    expect(find.text('YOUR RHYTHM'), findsOneWidget);
    expect(find.text('DO THIS NOW'), findsOneWidget);
    expect(find.text('YOUR FLOW'), findsOneWidget);
    expect(find.text('UP NEXT'), findsOneWidget);
  });

  testWidgets('15. Verify bottom-nav order is Today, Tasks, Calendar, Insights, Profile', (WidgetTester tester) async {
    final appState = AppStateProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: appState),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(
          home: MainShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify all 5 tab labels exist in FlowBottomNav
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.text('Today')), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.text('Tasks')), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.text('Calendar')), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.text('Insights')), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.text('Profile')), findsOneWidget);

    // Verify tab icons match restored order:
    // Index 0: Today active -> Icons.today_rounded
    // Index 1: Tasks inactive -> Icons.assignment_outlined
    // Index 2: Calendar inactive -> Icons.calendar_month_outlined
    // Index 3: Insights inactive -> Icons.insights_outlined
    // Index 4: Profile inactive -> Icons.person_outline_rounded
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.byIcon(Icons.today_rounded)), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.byIcon(Icons.assignment_outlined)), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.byIcon(Icons.calendar_month_outlined)), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.byIcon(Icons.insights_outlined)), findsOneWidget);
    expect(find.descendant(of: find.byType(FlowBottomNav), matching: find.byIcon(Icons.person_outline_rounded)), findsOneWidget);
  });

  testWidgets('16. Verify Today is the default tab on fresh launch (index 0)', (WidgetTester tester) async {
    final freshState = AppStateProvider();
    expect(freshState.currentNavIndex, equals(0));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: freshState),
          ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ],
        child: const MaterialApp(
          home: MainShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify TodayDashboardTab is visible by default
    expect(find.byType(TodayDashboardTab), findsOneWidget);
    expect(freshState.currentNavIndex, equals(0));
  });
}
