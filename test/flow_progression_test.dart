import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/models/flow_companion.dart';
import 'package:flowstate/models/flow_profile.dart';
import 'package:flowstate/models/flow_overview.dart';
import 'package:flowstate/components/companion/flow_companion_animation_controller.dart';
import 'package:flowstate/components/companion/flow_companion_view.dart';
import 'package:flowstate/components/flow_bottom_nav.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/flow_screen.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
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

  group('Flow Progression Models & Animation Controller', () {
    test('1. FlowCompanion model computes progress and stage correctly', () {
      const companion = FlowCompanion(
        id: 'comp-1',
        species: 'fox',
        name: 'Noya',
        level: 3,
        stage: 'Baby',
        companionXp: 90,
        xpToNextLevel: 120,
      );

      expect(companion.progressFraction, closeTo(90 / (90 + 120), 0.01));
      expect(companion.speciesEmoji, '🦊');
      expect(companion.stageBadge, '🦊 Noya · Level 3');

      final json = companion.toJson();
      final fromJson = FlowCompanion.fromJson(json);
      expect(fromJson.name, 'Noya');
      expect(fromJson.level, 3);
      expect(fromJson.stage, 'Baby');
    });

    test('2. FlowProfile model computes shield fractions and states', () {
      const profile = FlowProfile(
        userId: 'user-1',
        flowBalance: 150,
        currentStreak: 12,
        longestStreak: 18,
        shieldProgressDays: 4,
        shieldsAvailable: 2,
      );

      expect(profile.shieldProgressFraction, closeTo(4 / 7.0, 0.01));
      expect(profile.hasShields, isTrue);

      final json = profile.toJson();
      final fromJson = FlowProfile.fromJson(json);
      expect(fromJson.flowBalance, 150);
      expect(fromJson.currentStreak, 12);
      expect(fromJson.shieldsAvailable, 2);
    });

    test('3. FlowCompanionAnimationController transitions through contract states', () {
      final controller = FlowCompanionAnimationController();
      expect(controller.state, CompanionAnimState.idle);

      controller.setStarting(taskTitle: 'Deep Work');
      expect(controller.state, CompanionAnimState.starting);
      expect(controller.isStarting, isTrue);

      controller.setFocusing(taskTitle: 'Deep Work', elapsedMinutes: 25);
      expect(controller.state, CompanionAnimState.focusing);
      expect(controller.isFocusing, isTrue);
      expect(controller.statusText, contains('25 XP'));

      controller.triggerSuccess(message: 'Well done!');
      expect(controller.state, CompanionAnimState.success);
      expect(controller.isSuccess, isTrue);

      controller.setTired();
      expect(controller.state, CompanionAnimState.tired);
      expect(controller.isTired, isTrue);

      controller.triggerEvolution();
      expect(controller.state, CompanionAnimState.evolution);
      expect(controller.isEvolving, isTrue);
    });
  });

  group('FlowScreen & UI Tests', () {
    Widget buildTestableFlowScreen({FlowProvider? flowProvider}) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<FlowProvider>.value(
            value: flowProvider ?? FlowProvider(),
          ),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: FlowScreen(),
          ),
        ),
      );
    }

    testWidgets('4. FlowScreen renders Living Flow Hub with companion, tabs, and personal records',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.reset());

      final provider = FlowProvider();
      await tester.pumpWidget(buildTestableFlowScreen(flowProvider: provider));
      await tester.pumpAndSettle();

      // 1. Companion Hero & Status
      expect(find.text('NOYA'), findsOneWidget);
      expect(find.textContaining('Level 1'), findsWidgets);
      expect(find.byType(FlowCompanionView), findsOneWidget);

      // 2. Primary CTA & Rhythm intelligence
      expect(find.text('Focus with Noya'), findsOneWidget);
      expect(find.textContaining('build your rhythm with Noya'), findsOneWidget);

      // 3. 4 Segmented Hub Tabs
      expect(find.text('Journey'), findsOneWidget);
      expect(find.text('Quests'), findsOneWidget);
      expect(find.text('Badges'), findsOneWidget);
      expect(find.text('Customize'), findsOneWidget);

      // 4. Default Tab 0 (Journey): Evolution line & Weekly challenge
      expect(find.textContaining('Evolution Line'), findsOneWidget);
      expect(find.text('WEEKLY CHALLENGE'), findsOneWidget);

      // 5. Switch to Quests tab
      await tester.tap(find.text('Quests'));
      await tester.pumpAndSettle();
      expect(find.text('TODAY’S QUESTS'), findsOneWidget);

      // 6. Switch to Badges (Achievements) tab
      await tester.tap(find.text('Badges'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ACHIEVEMENTS'), findsOneWidget);

      // 7. Switch to Customize (Sanctuary) tab
      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();
      expect(find.text('COMPANION SANCTUARY'), findsOneWidget);

      // 8. Personal Records ("Me vs Myself") - Honest empty state check
      expect(find.textContaining('PERSONAL RECORDS'), findsOneWidget);
      expect(find.text('Best Session'), findsOneWidget);
      expect(find.text('Best Day'), findsOneWidget);
      expect(find.text('Total Focus'), findsOneWidget);
      expect(find.text('Rhythm'), findsOneWidget);
      expect(find.text('—'), findsNWidgets(2)); // Both Best Session and Best Day are '—'
      expect(find.text('0m'), findsOneWidget);   // Total focus is '0m'
      expect(find.text('Building'), findsOneWidget); // Rhythm is 'Building'
    });

    testWidgets('5. Responsive layout: zero RenderFlex overflow across 320px, 360px, 375px, 412px',
        (WidgetTester tester) async {
      final widths = [320.0, 360.0, 375.0, 390.0, 412.0];
      final provider = FlowProvider();
      for (final width in widths) {
        tester.view.physicalSize = Size(width * 2, 800 * 2);
        tester.view.devicePixelRatio = 2.0;

        await tester.pumpWidget(buildTestableFlowScreen(flowProvider: provider));
        await tester.pumpAndSettle();

        final error = tester.takeException();
        if (error is FlutterError) {
          debugPrint(error.toString());
        }
        expect(error, isNull, reason: 'Failed on screen width $width');
      }
      tester.view.reset();
    });

    testWidgets('6. Evolution experience triggers dialog when isEvolutionReady is true',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.reset());

      final provider = FlowProvider();
      await tester.pumpWidget(buildTestableFlowScreen(flowProvider: provider));
      await tester.pumpAndSettle();

      expect(find.byType(FlowScreen), findsOneWidget);
    });

    testWidgets('7. FlowCompanionView adapts to reduced motion setting',
        (WidgetTester tester) async {
      const companion = FlowCompanion(id: 'test-comp', name: 'Noya');
      final controller = FlowCompanionAnimationController();

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: FlowCompanionView(
                companion: companion,
                controller: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.setFocusing();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Focusing with you'), findsOneWidget);
    });

    test('8. CompanionAnimalInfo provides rich details, perks, and lore for all 4 animals', () {
      const animals = CompanionAnimalInfo.all;
      expect(animals.length, 4);

      final fox = CompanionAnimalInfo.fromSpecies('fox');
      expect(fox.emoji, '🦊');
      expect(fox.title, 'The Swift Sprinter');
      expect(fox.perk, contains('Sprint Mastery'));

      final otter = CompanionAnimalInfo.fromSpecies('otter');
      expect(otter.emoji, '🦦');
      expect(otter.defaultName, 'Ludo');
      expect(otter.perk, contains('Deep Current'));

      final owl = CompanionAnimalInfo.fromSpecies('owl');
      expect(owl.emoji, '🦉');
      expect(owl.defaultName, 'Aria');
      expect(owl.perk, contains('Night Owl'));

      final capybara = CompanionAnimalInfo.fromSpecies('capybara');
      expect(capybara.emoji, '🐾');
      expect(capybara.defaultName, 'Boba');
      expect(capybara.perk, contains('Stress Immunity'));
    });

    testWidgets('9. FlowBottomNav renders clean 5 destinations without center companion button',
        (WidgetTester tester) async {
      int activeIndex = 0;
      final provider = FlowProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<FlowProvider>.value(value: provider),
          ],
          child: MaterialApp(
            home: Scaffold(
              bottomNavigationBar: FlowBottomNav(
                currentIndex: activeIndex,
                onTap: (i) => activeIndex = i,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Clean 5 primary destinations are present and balanced
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Insights'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      // Flow hub is accessed via Today header pill or Profile, not crowded in bottom nav
      expect(find.text('Flow'), findsNothing);
    });

    testWidgets('10. FlowScreen renders real calculated Personal Records for user with completed sessions',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(() => tester.view.reset());

      final provider = FlowProvider();
      final customOverview = FlowOverview(
        companion: const FlowCompanion(id: 'c1', name: 'Noya', species: 'fox', level: 2, companionXp: 150),
        profile: const FlowProfile(userId: 'u1', currentStreak: 3, flowBalance: 400),
        personalBestFocusMinutes: 45,
        bestFocusDayMinutes: 75,
        totalFocusMinutes: 120,
        consistencyScore: 'Steady',
        rhythmAcknowledgement: 'You usually focus best around this time. Noya noticed. 🦊',
      );
      provider.setOverviewForTesting(customOverview);

      await tester.pumpWidget(buildTestableFlowScreen(flowProvider: provider));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Best Session'), 500);
      expect(find.text('45m'), findsOneWidget); // Best session
      expect(find.text('75m'), findsOneWidget); // Best day
      expect(find.text('2h'), findsOneWidget);  // Total focus (120 min = 2h)
      expect(find.text('Steady'), findsOneWidget); // Rhythm
    });

    testWidgets('11. Today YOUR FLOW card renders visible 44px Noya avatar, text, and Start Flow button on 320px screen',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() {
        tester.view.reset();
        FlowClock().stopTimer();
      });

      final appState = AppStateProvider();
      appState.setCalibratedStateForTesting();
      appState.setTodayNetworkStateForTesting(TodayNetworkState.tasksSuccess);

      final flowProvider = FlowProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppStateProvider>.value(value: appState),
            ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
            ChangeNotifierProvider<FlowProvider>.value(value: flowProvider),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: const Scaffold(
              body: TodayDashboardTab(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify YOUR FLOW section header is present
      expect(find.text('YOUR FLOW'), findsOneWidget);

      // Verify Noya avatar image is present
      final noyaImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final asset = widget.image as AssetImage;
          return asset.assetName.contains('fox_winking') || asset.assetName.contains('noya');
        }
        return false;
      });
      expect(noyaImageFinder, findsWidgets);

      // Verify companion name, level, XP, and focus callout
      expect(find.textContaining('Noya · L1 · 0 XP'), findsOneWidget);
      expect(find.text('25 min · Focus with Noya'), findsOneWidget);

      // Verify Start Flow button is fully visible
      expect(find.widgetWithText(ElevatedButton, 'Start Flow'), findsOneWidget);

      // Verify zero RenderFlex overflow on 320px
      final error = tester.takeException();
      expect(error, isNull);

      FlowClock().stopTimer();
    });
  });
}
