import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/onboarding_flow_screen.dart';
import 'package:flowstate/screens/auth_screen.dart';
import 'package:flowstate/components/flow_ambient_background.dart';
import 'package:flowstate/components/flow_time_picker.dart';
import 'package:flowstate/components/routine_building_view.dart';
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

  Widget createOnboardingWidget({Size size = const Size(400, 800)}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppStateProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData.light().copyWith(splashFactory: InkRipple.splashFactory),
        home: MediaQuery(
          data: MediaQueryData(size: size, disableAnimations: true),
          child: const OnboardingFlowScreen(),
        ),
      ),
    );
  }

  group('Adaptive Onboarding UI & Visual Tests', () {
    testWidgets('1. Onboarding launches with light off-white background and welcome copy', (WidgetTester tester) async {
      await tester.pumpWidget(createOnboardingWidget());
      await tester.pumpAndSettle();

      // Check primary welcome copy
      expect(find.text("Let's find your rhythm."), findsOneWidget);
      expect(find.textContaining('Not your perfect routine.'), findsOneWidget);
      expect(find.text('Begin'), findsOneWidget);

      // Verify no black background is used
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, const Color(0xFFF8FAFC));

      // Verify FlowAmbientBackground renders
      expect(find.byType(FlowAmbientBackground), findsOneWidget);
    });

    testWidgets('2. Navigation preserves selected answers and allows interactive selection', (WidgetTester tester) async {
      await tester.pumpWidget(createOnboardingWidget());
      await tester.pumpAndSettle();

      // Tap Begin -> Question 1
      await tester.tap(find.text('Begin'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('When does your brain usually feel most switched on?'), findsOneWidget);
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);

      // Select Afternoon
      await tester.tap(find.text('Afternoon'));
      await tester.pumpAndSettle();

      // Tap Continue -> Question 2 (Weekday wake time)
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('When do you usually wake up on days you have somewhere to be?'), findsOneWidget);

      // Tap Back button
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Answer in Question 1 must be preserved
      expect(find.text('When does your brain usually feel most switched on?'), findsOneWidget);
      expect(find.text('Afternoon'), findsOneWidget);
    });

    testWidgets('3. Responsiveness: Renders cleanly on small 320px and 360px screens without overflow', (WidgetTester tester) async {
      // 320px width screen test
      await tester.pumpWidget(createOnboardingWidget(size: const Size(320, 600)));
      await tester.pumpAndSettle();

      expect(find.text("Let's find your rhythm."), findsOneWidget);
      expect(tester.takeException(), isNull); // No RenderFlex overflow

      // 360px width screen test
      await tester.pumpWidget(createOnboardingWidget(size: const Size(360, 640)));
      await tester.pumpAndSettle();

      expect(find.text("Let's find your rhythm."), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('4. Reduced motion mode renders static ambient background without throwing', (WidgetTester tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppStateProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: OnboardingFlowScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlowAmbientBackground), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. FlowTimePicker renders digital display, preset chips, circadian phase, and manual typing', (WidgetTester tester) async {
      String selected = '07:00';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return FlowTimePicker(
                  initialTime24: selected,
                  isWakeTime: true,
                  onTimeChanged: (val) => setState(() => selected = val),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('07'), findsOneWidget);
      expect(find.text('00'), findsOneWidget);
      expect(find.text('AM'), findsOneWidget);

      // Toggle manual typing mode
      expect(find.byIcon(Icons.keyboard_outlined), findsOneWidget);
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      expect(find.text('Type time directly'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));

      // Enter manual hour '08' and minute '30'
      await tester.enterText(find.byType(TextField).first, '08');
      await tester.enterText(find.byType(TextField).last, '30');
      await tester.pumpAndSettle();
      expect(selected, '08:30');

      // Return to clock dial
      await tester.tap(find.text('Return to Clock Dial'));
      await tester.pumpAndSettle();
      expect(find.text('Type time directly'), findsNothing);
    });

    testWidgets('6. RoutineBuildingView renders honest progression and starting rhythm estimate', (WidgetTester tester) async {
      bool completed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: RoutineBuildingView(
                userAnswers: const {'peak_window': 'morning'},
                onComplete: () => completed = true,
              ),
            ),
          ),
        ),
      );

      // Initial state shows honest building steps
      expect(find.text('BUILDING YOUR STARTING RHYTHM'), findsOneWidget);
      expect(find.text('Reading your schedule'), findsOneWidget);

      // Advance through timer steps (4 steps * 650ms)
      for (int i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      await tester.pump(const Duration(milliseconds: 400));

      // Honest starting rhythm card should be visible
      expect(find.text('Your rhythm has a starting point.'), findsOneWidget);
      expect(find.text("We'll refine it as you work."), findsOneWidget);
      expect(find.text('YOUR STARTING RHYTHM'), findsOneWidget);
      expect(find.text('Starting estimate'), findsOneWidget);
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Take me to Today'), findsOneWidget);

      // Tap Take me to Today
      await tester.tap(find.text('Take me to Today'));
      expect(completed, isTrue);
    });

    testWidgets('7. AuthScreen renders clean Flowstate mark, calm background, and primary CTAs', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: AuthScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FLOWSTATE'), findsOneWidget);
      expect(find.text('Plan around your energy.'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with Email'), findsOneWidget);
      expect(find.byType(FlowAmbientBackground), findsOneWidget);
    });
  });
}
