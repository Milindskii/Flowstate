import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/screens/ai_plan_preview_sheet.dart';
import 'package:flowstate/screens/pro_subscription_screen.dart';
import 'package:flowstate/screens/profile_settings_tab.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/components/routine_building_view.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/task_parse_service.dart';

class MockAISubscriptionApiService extends ApiService {
  bool returnPro = false;
  bool returnFreeExhausted = false;
  int shieldsCount = 2;
  int aiPlanCallCount = 0;
  bool throwOnAiPlan = false;

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/ai/plan') {
      aiPlanCallCount++;
      if (throwOnAiPlan) {
        throw const ApiException('Network connection failed');
      }
      return {
        'tasks': [
          {
            'title': 'Project deliverable',
            'estimated_minutes': 45,
            'difficulty': 'high',
            'priority': 'high',
            'priority_source': 'explicit',
            'type': 'deep_work',
          }
        ],
        'ambiguities': [],
        'needs_confirmation': false,
        'usage': {
          'is_pro': false,
          'subscription_tier': 'free',
          'free_use_available': false,
          'free_uses_consumed': 1,
          'shields_available': 2,
          'shield_funded_uses': 0,
          'can_use_ai': true,
          'requires_shield': true,
          'hourly_requests_remaining': 4,
        }
      };
    }
    return {};
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/auth/me') {
      return {
        'id': 'user-test-1',
        'email': 'tester@flowstate.local',
        'name': 'Tester',
        'onboarding_completed': true,
      };
    }
    if (endpoint == '/api/v1/ai/status') {
      return {
        'is_pro': returnPro,
        'subscription_tier': returnPro ? 'pro' : 'free',
        'free_use_available': !returnFreeExhausted,
        'free_uses_consumed': returnFreeExhausted ? 1 : 0,
        'shields_available': shieldsCount,
        'shield_funded_uses': 0,
        'can_use_ai': returnPro || !returnFreeExhausted || shieldsCount > 0,
        'requires_shield': !returnPro && returnFreeExhausted && shieldsCount > 0,
        'hourly_requests_remaining': 5,
      };
    }
    if (endpoint == '/api/v1/subscription/status') {
      return {
        'is_pro': returnPro,
        'subscription_tier': returnPro ? 'pro' : 'free',
        'status': returnPro ? 'active' : 'inactive',
        'auto_renew': returnPro,
      };
    }
    if (endpoint == '/api/v1/subscription/plans') {
      return [
        {
          'id': 'monthly',
          'name': 'Monthly',
          'display_price': '₹— / month',
          'billing_period': 'monthly',
          'is_best_value': false,
          'savings_text': null,
          'pricing_note': 'Pricing coming soon',
        },
        {
          'id': 'yearly',
          'name': 'Yearly',
          'display_price': '₹— / year',
          'billing_period': 'yearly',
          'is_best_value': true,
          'savings_text': null,
          'pricing_note': 'Pricing coming soon',
        },
      ];
    }
    if (endpoint == '/api/v1/tasks') {
      return {'items': [], 'total': 0};
    }
    if (endpoint == '/api/v1/today') {
      return {
        'user': {'id': 'user-test-1', 'email': 'tester@flowstate.local'},
        'date': '2026-09-25',
        'lifecycle_state': 'new_user',
        'readiness': {'score': null, 'max_score': 100, 'confidence': 0.0, 'is_calibrated': false, 'factors': [], 'hourly_rhythm': []},
        'current_recommendation': null,
        'ai_brief': {'title': 'FLOWSTATE', 'message': "Let's build your day.", 'action_label': 'Plan'},
        'workload_summary': {'total_minutes': 0, 'completed_minutes': 0, 'task_count': 0, 'completed_count': 0},
        'tasks': [],
        'schedule': [],
      };
    }
    return {};
  }
}

Widget createTestApp({
  required Widget child,
  ApiService? api,
  AppStateProvider? customAppState,
}) {
  final mockApi = api ?? MockAISubscriptionApiService();
  final appState = customAppState ?? AppStateProvider(customApi: mockApi);
  final themeProvider = ThemeProvider();
  final flowProvider = FlowProvider(api: mockApi);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStateProvider>.value(value: appState),
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<FlowProvider>.value(value: flowProvider),
    ],
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: false,
        splashFactory: NoSplash.splashFactory,
      ),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      kGeminiPrivacyAcceptedKey: true,
    });
  });

  // ---------------------------------------------------------------------------
  // PART 1: Rhythm Screen Responsiveness (Fixing 23px RenderFlex Overflow)
  // ---------------------------------------------------------------------------
  group('Part 1: Starting Rhythm Screen Responsiveness', () {
    for (final width in [320.0, 360.0, 390.0, 432.0]) {
      testWidgets('No RenderFlex overflow on Rhythm screen at ${width.toInt()}px width', (tester) async {
        tester.view.physicalSize = Size(width * 2.0, 800 * 2.0);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestApp(
          child: RoutineBuildingView(
            userAnswers: const {'peak_window': 'morning'},
            onComplete: () {},
          ),
        ));

        // Advance timers so honest progression reveals the Starting Rhythm Card
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();

        // Verify the card is visible and no overflow occurred
        expect(find.byKey(const ValueKey('starting_rhythm_card')), findsOneWidget);
        expect(find.text('YOUR STARTING RHYTHM'), findsOneWidget);
        expect(find.text('Starting estimate'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ---------------------------------------------------------------------------
  // PART 2: Offline-Friendly Brain Dump + Local-First Planning UX
  // ---------------------------------------------------------------------------
  group('Part 2: Offline-Friendly Brain Dump & Scheduling UX', () {
    testWidgets('1. Microphone is completely removed from Brain Dump UI', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('What else is on your plate?'), findsOneWidget);
      expect(find.text('Just write it out.'), findsOneWidget);

      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsNothing);
      expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
      expect(find.textContaining('Voice'), findsNothing);
    });

    testWidgets('2. Clear unformatted input parses locally WITHOUT calling Gemini', (tester) async {
      final mockApi = MockAISubscriptionApiService();

      await tester.pumpWidget(createTestApp(
        api: mockApi,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      const naturalText = 'finish python lab tomorrow, study arrays, dentist at 4, gym at 6';
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), naturalText);
      await tester.pump();

      // Tap Build my day
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // Core rule: Gemini is NOT called for clear, unambiguous input!
      expect(mockApi.aiPlanCallCount, equals(0));

      // Plan Preview appears with "Planned by Flowstate"
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Planned by Flowstate'), findsOneWidget);

      // Verify Add & Schedule button is visible
      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
      expect(find.text('Add & Schedule'), findsOneWidget);
    });

    testWidgets('3. Local parser schedules tasks; user confirmation creates tasks', (tester) async {
      final mockApi = MockAISubscriptionApiService();
      final appState = AppStateProvider(customApi: mockApi);

      await tester.pumpWidget(createTestApp(
        api: mockApi,
        customAppState: appState,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Dentist at 4, gym at 6');
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // In preview mode: tasks are NOT added to appState yet!
      expect(appState.tasks.isEmpty, isTrue);

      // Now tap Add & Schedule
      await tester.tap(find.byKey(const Key('add_and_schedule_button')));
      await tester.pumpAndSettle();

      // Sheet closed and tasks are now confirmed in appState!
      expect(appState.tasks.length, equals(2));
      expect(appState.tasks.any((t) => t.title.toLowerCase().contains('dentist')), isTrue);
      expect(appState.tasks.any((t) => t.title.toLowerCase().contains('gym')), isTrue);
    });

    testWidgets('4. Ambiguous input triggers Gemini enhancement', (tester) async {
      final mockApi = MockAISubscriptionApiService();

      await tester.pumpWidget(createTestApp(
        api: mockApi,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Ambiguous input containing relative meeting dependency
      const ambiguousInput = 'I need to get that project thing done sometime before my meeting';
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), ambiguousInput);
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // Gemini was called because input is ambiguous
      expect(mockApi.aiPlanCallCount, equals(1));
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Enhanced with AI'), findsOneWidget);
    });

    testWidgets('5. Gemini network failure falls back seamlessly to local parser without blocking dialog', (tester) async {
      final mockApi = MockAISubscriptionApiService()..throwOnAiPlan = true;

      await tester.pumpWidget(createTestApp(
        api: mockApi,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Ambiguous text that would attempt Gemini
      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'Work on the stuff I told you about last week, dentist at 4',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // NO blocking error dialog!
      expect(find.textContaining('Low internet connection'), findsNothing);

      // Successfully fell back to local parser and displays subtle explanation
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Planned by Flowstate'), findsOneWidget);
      expect(find.textContaining("AI planning isn't available right now, so Flowstate used its built-in planner."), findsOneWidget);

      // Add & Schedule is ready and visible
      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
    });

    testWidgets('6. Empty input disables Build button and blank text prompts user', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final buildBtnFinder = find.byKey(const Key('brain_dump_build_button'));
      final button = tester.widget<ElevatedButton>(buildBtnFinder);
      expect(button.onPressed, isNull);
    });

    test('7. Explicit priorities, durations, and times are preserved', () {
      final tasks = TaskParseService.deterministicFallbackParse(
        'study for 45 minutes high priority, gym at 6, dentist at 4 low priority, submit thesis by Friday urgent',
      );

      expect(tasks.length, equals(4));

      // Study
      final study = tasks.firstWhere((t) => t.title.toLowerCase().contains('study'));
      expect(study.durationMinutes, equals(45));
      expect(study.priority, equals(TaskPriority.high));

      // Gym
      final gym = tasks.firstWhere((t) => t.title.toLowerCase().contains('gym'));
      expect(gym.scheduledStart, isNotNull);
      expect(gym.scheduledStart!.hour, equals(18)); // 6 PM

      // Dentist
      final dentist = tasks.firstWhere((t) => t.title.toLowerCase().contains('dentist'));
      expect(dentist.scheduledStart, isNotNull);
      expect(dentist.scheduledStart!.hour, equals(16)); // 4 PM
      expect(dentist.priority, equals(TaskPriority.low));

      // Thesis
      final thesis = tasks.firstWhere((t) => t.title.toLowerCase().contains('thesis'));
      expect(thesis.priority, equals(TaskPriority.urgent));
      expect(thesis.deadline, equals('Friday'));
    });

    testWidgets('8. Add & Schedule button stays pinned and visible on narrow 320px width', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Many tasks to test scrollability while CTA is pinned
      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'finish python lab tomorrow, study arrays, dentist at 4, gym at 6, buy groceries, call mom, read book',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
      expect(find.byKey(const Key('edit_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('9. Go Pro section inside Profile opens ProSubscriptionScreen', (tester) async {
      final mockApi = MockAISubscriptionApiService()..returnPro = false;

      await tester.pumpWidget(createTestApp(
        api: mockApi,
        child: const ProfileSettingsTab(),
      ));

      await tester.pumpAndSettle();

      expect(find.text('GO PRO'), findsOneWidget);
      final exploreBtn = find.byKey(const Key('explore_pro_button'));
      expect(exploreBtn, findsOneWidget);
      await tester.tap(exploreBtn);
      await tester.pumpAndSettle();

      expect(find.text('Flowstate, without limits.'), findsOneWidget);
    });

    testWidgets('10. Pro screen renders Monthly and Yearly option cards without fake prices', (tester) async {
      await tester.pumpWidget(createTestApp(
        child: const ProSubscriptionScreen(),
      ));

      await tester.pumpAndSettle();

      expect(find.text('Monthly'), findsOneWidget);
      expect(find.text('Yearly'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('₹— / month'), findsOneWidget);
      expect(find.text('₹— / year'), findsOneWidget);
      expect(find.textContaining('₹199'), findsNothing);
      expect(find.textContaining('% off'), findsNothing);
    });

    testWidgets('11. Backend owns Pro entitlement verified state', (tester) async {
      final proApi = MockAISubscriptionApiService()..returnPro = true;
      await tester.pumpWidget(createTestApp(
        api: proApi,
        child: const ProfileSettingsTab(key: Key('pro_profile_tab')),
      ));
      await tester.pumpAndSettle();
      expect(find.text('FLOWSTATE PRO'), findsOneWidget);
      expect(find.text('Your plan is active.'), findsOneWidget);
      expect(find.text('Manage Subscription'), findsOneWidget);
    });
  });
}
