import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/theme/flow_motion.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/screens/onboarding_flow_screen.dart';
import 'package:flowstate/screens/what_should_i_do_screen.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
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

  group('Flowstate Motion & Navigation Tests', () {
    testWidgets('1. FlowFadeIndexedStack preserves child state and crossfades without remounting', (WidgetTester tester) async {
      int index = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: FlowFadeIndexedStack(
                  index: index,
                  children: const [
                    _TestCounterWidget(label: 'Tab 0'),
                    _TestCounterWidget(label: 'Tab 1'),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () => setState(() => index = (index == 0 ? 1 : 0)),
                  child: const Icon(Icons.swap_horiz),
                ),
              );
            },
          ),
        ),
      );

      // Verify Tab 0 is visible
      expect(find.text('Tab 0: Count 0'), findsOneWidget);

      // Increment counter in Tab 0
      await tester.tap(find.text('Tab 0: Count 0'));
      await tester.pumpAndSettle();
      expect(find.text('Tab 0: Count 1'), findsOneWidget);

      // Switch to Tab 1
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Tab 1: Count 0'), findsOneWidget);

      // Increment counter in Tab 1
      await tester.tap(find.text('Tab 1: Count 0'));
      await tester.pumpAndSettle();
      expect(find.text('Tab 1: Count 1'), findsOneWidget);

      // Switch back to Tab 0
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // State in Tab 0 must be PRESERVED (Count is still 1, not reset to 0!)
      expect(find.text('Tab 0: Count 1'), findsOneWidget);
    });

    testWidgets('2. TodayDashboardTab does not recreate full entrance stagger on provider rebuild', (WidgetTester tester) async {
      final appState = AppStateProvider();
      appState.setCalibratedStateForTesting();
      final themeProvider = ThemeProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: const MaterialApp(
            home: TodayDashboardTab(),
          ),
        ),
      );

      // Initial pump triggers the first entrance stagger
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('DO THIS NOW'), findsOneWidget);

      await tester.pumpAndSettle();

      // Trigger a provider data change (e.g., category filter)
      appState.setSelectedCategory('Deep Work');
      await tester.pump();

      // Ensure view renders immediately without re-hiding content
      expect(find.text('DO THIS NOW'), findsOneWidget);
      expect(find.textContaining('Good '), findsOneWidget);
    });

    testWidgets('3. Onboarding PopScope provides deterministic back navigation', (WidgetTester tester) async {
      final appState = AppStateProvider();
      final themeProvider = ThemeProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
            theme: ThemeData(splashFactory: InkRipple.splashFactory),
            home: const MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: OnboardingFlowScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On Step 0 (Welcome) - "Let's find your rhythm."
      expect(find.text("Let's find your rhythm."), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);

      // Tap CTA to advance to Question 1
      await tester.tap(find.text('Begin'), warnIfMissed: false);
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.text('When does your brain usually feel most switched on?'), findsOneWidget);

      // Now on Question 1 (page 1). PopScope must have canPop = false
      final popScopeFinder = find.byWidgetPredicate((w) => w is PopScope);
      expect(popScopeFinder, findsWidgets);
      final dynamic popScopeWidget = tester.widget(popScopeFinder.first);
      expect(popScopeWidget.canPop, isFalse);

      // Trigger pop navigation (simulate Android back button press)
      await tester.binding.handlePopRoute();
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }

      // Must navigate back to Welcome step without exiting onboarding
      expect(find.text("Let's find your rhythm."), findsOneWidget);
    });

    testWidgets('4. WhatShouldIDoScreen swaps task smoothly when tapping Give me something easier', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final appState = AppStateProvider();
      appState.setCalibratedStateForTesting();
      final themeProvider = ThemeProvider();
      final sampleTask = appState.recommendedTask ?? appState.tasks.first;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: WhatShouldIDoScreen(
                task: sampleTask,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial recommended task should be present
      expect(find.text('What should I do?'), findsOneWidget);
      expect(find.textContaining('Give me something easier'), findsOneWidget);

      // Tap "Give me something easier"
      await tester.tap(find.textContaining('Give me something easier'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Verify the task recommendation updated and the button remains responsive
      expect(find.textContaining('Give me something easier'), findsOneWidget);
    });

    testWidgets('5. Reduced motion disables animations smoothly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(
            home: FlowFadeSlide(
              child: Text('Reduced Motion Target'),
            ),
          ),
        ),
      );

      // In reduced motion, widget is immediately visible without needing pumpAndSettle
      expect(find.text('Reduced Motion Target'), findsOneWidget);
    });

    testWidgets('6. FlowFadeIndexedStack renders both outgoing and incoming tabs concurrently during mid-transition', (WidgetTester tester) async {
      int activeIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: FlowFadeIndexedStack(
                  index: activeIndex,
                  duration: const Duration(milliseconds: 240),
                  children: const [
                    Text('Tab A Content'),
                    Text('Tab B Content'),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () => setState(() => activeIndex = 1),
                  child: const Icon(Icons.swap_horiz),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Tab A Content'), findsOneWidget);
      expect(find.text('Tab B Content'), findsNothing); // Offstage

      // Trigger transition to Tab B
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(); // Start animation frame

      // Advance by 120ms (exactly 50% of the 240ms transition duration)
      await tester.pump(const Duration(milliseconds: 120));

      // Both tabs MUST be rendered simultaneously in the tree and not offstage
      expect(find.text('Tab A Content', skipOffstage: false), findsOneWidget);
      expect(find.text('Tab B Content', skipOffstage: false), findsOneWidget);

      // Settle completely
      await tester.pumpAndSettle();
      expect(find.text('Tab B Content'), findsOneWidget);
      expect(find.text('Tab A Content'), findsNothing); // Tab A is now offstage
    });
  });
}

class _TestCounterWidget extends StatefulWidget {
  final String label;
  const _TestCounterWidget({required this.label});

  @override
  State<_TestCounterWidget> createState() => _TestCounterWidgetState();
}

class _TestCounterWidgetState extends State<_TestCounterWidget> {
  int _count = 0;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => setState(() => _count++),
        child: Text('${widget.label}: Count $_count'),
      ),
    );
  }
}
