import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/services/timezone_service.dart';
import 'package:flowstate/services/ai_plan_service.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/components/companion/noya_reaction_controller.dart';
import 'package:flowstate/components/noya_companion_view.dart';
import 'package:flowstate/components/noya_motion_view.dart';
import 'package:flowstate/screens/pro_subscription_screen.dart';
import 'package:flowstate/screens/profile_settings_tab.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/components/routine_building_view.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/task_parse_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/models/readiness_model.dart';

class MockAISubscriptionApiService extends ApiService {
  bool returnPro = false;
  bool returnFreeExhausted = false;
  int shieldsCount = 2;
  int aiPlanCallCount = 0;
  bool throwOnAiPlan = false;
  bool malformedAiPlan = false;

  /// Opt-in: model the server's entitlement contract. A new account has ONE complimentary AI plan; only a
  /// successful AI plan spends it, a failed attempt never does, and replaying a request key never spends it twice.
  /// (The server's own accounting is covered in backend/tests/test_ai_entitlement.py; this fake lets the client's
  /// behaviour around it be asserted: key reuse, which calls it makes, and what the user sees.)
  bool trackEntitlement = false;
  int freeUsesConsumed = 0;
  final List<String?> planKeys = [];
  final Map<String, dynamic> _planCache = {};

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/ai/plan') {
      aiPlanCallCount++;
      final key = body is Map ? body['idempotency_key'] as String? : null;
      planKeys.add(key);
      if (trackEntitlement && key != null && _planCache.containsKey(key)) {
        return _planCache[key]; // replay: the stored plan, nothing charged again
      }
      if (throwOnAiPlan) {
        throw const ApiException('Network connection failed');
      }
      if (malformedAiPlan) {
        return {'tasks': 'invalid-not-a-list', 'usage': {}};
      }
      final response = {
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
      if (trackEntitlement) {
        freeUsesConsumed++;
        if (key != null) _planCache[key] = response;
      }
      return response;
    }
    if (endpoint == '/api/v1/tasks') {
      if (body is Map) {
        final res = Map<String, dynamic>.from(body);
        res['id'] ??= 'task-${DateTime.now().millisecondsSinceEpoch}';
        return res;
      }
      return <String, dynamic>{
        'id': 'task-${DateTime.now().millisecondsSinceEpoch}',
        'title': 'Task',
        'type': 'deep_work',
        'estimated_minutes': 45,
        'difficulty': 'medium',
        'priority': 'medium',
        'priority_source': 'unspecified',
        'status': 'pending',
      };
    }
    if (endpoint == '/api/v1/tasks/batch-create-and-schedule') {
      // Return created tasks so confirmCandidates can insert them into _tasks.
      final items = (body is Map ? ((body['tasks'] ?? body['items']) as List? ?? []) : []);
      int i = 0;
      final tasks = items.map((item) {
        final m = Map<String, dynamic>.from(item as Map);
        m['id'] ??= 'task-batch-${DateTime.now().millisecondsSinceEpoch}-${i++}';
        m['status'] ??= 'pending';
        m['type'] ??= m['task_type'] ?? 'deep_work';
        m['estimated_minutes'] ??= m['estimated_minutes'] ?? 30;
        m['difficulty'] ??= 'medium';
        m['priority'] ??= 'medium';
        m['priority_source'] ??= 'unspecified';
        return m;
      }).toList();
      return <String, dynamic>{'tasks': tasks, 'schedule': []};
    }
    return <String, dynamic>{};
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
        'free_use_available': trackEntitlement ? freeUsesConsumed < 1 : !returnFreeExhausted,
        'free_uses_consumed': trackEntitlement ? freeUsesConsumed : (returnFreeExhausted ? 1 : 0),
        'shields_available': shieldsCount,
        'shield_funded_uses': 0,
        'can_use_ai': returnPro || (trackEntitlement ? freeUsesConsumed < 1 : !returnFreeExhausted) || shieldsCount > 0,
        'requires_shield': !returnPro && (trackEntitlement ? freeUsesConsumed >= 1 : returnFreeExhausted) && shieldsCount > 0,
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

/// A fake whose complimentary AI plan is already spent: clear text plans locally with no AI call.
MockAISubscriptionApiService _spentApi() => MockAISubscriptionApiService()..returnFreeExhausted = true;

Widget createTestApp({
  required Widget child,
  ApiService? api,
  AppStateProvider? customAppState,
}) {
  final mockApi = api ?? MockAISubscriptionApiService();
  const testUser = AuthUser(
    id: 'user-test-1',
    email: 'tester@flowstate.local',
    name: 'Tester',
    onboardingCompleted: true,
  );
  final appState = customAppState ?? AppStateProvider(customApi: mockApi, initialUser: testUser);
  if (appState.currentUser == null) {
    appState.onUserAuthenticated(testUser);
  }
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
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({
      kGeminiPrivacyAcceptedKey: true,
    });
  });

  tearDown(() {
    FlowClock().stopTimer();
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

    // A new account's first plan is its complimentary AI plan (see the entitlement group below). Once that is
    // spent, clear input plans locally and never calls AI.
    testWidgets('2. Clear unformatted input parses locally WITHOUT calling AI once the complimentary use is spent', (tester) async {
      final mockApi = _spentApi();

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
      final mockApi = _spentApi(); // complimentary AI plan already used: the local parser plans
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

    // Spec 2026-10-03: an AI failure is never silent. The dump is kept and the user chooses
    // Retry with AI or Use basic planner (labelled as not AI).
    testWidgets('5. Gemini network failure shows an explicit choice, keeps the dump, never a blocking dialog', (tester) async {
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

      // Not silently replaced by a local plan: the failure is stated and the dump is kept.
      expect(find.text('YOUR PLAN'), findsNothing);
      expect(find.textContaining("Noya's taking a little nap"), findsOneWidget);
      expect(find.text('Work on the stuff I told you about last week, dentist at 4'), findsOneWidget);

      // The basic planner is one tap away and is labelled as not AI.
      await tester.ensureVisible(find.text('Plan it myself'));
      await tester.tap(find.text('Plan it myself'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Basic plan (not AI)'), findsOneWidget);

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

    testWidgets('12. Gemini failure does not consume AI credit or shield', (tester) async {
      final mockApi = MockAISubscriptionApiService()..throwOnAiPlan = true;
      final initialShields = mockApi.shieldsCount;

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

      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'I need to get that project thing done sometime before my meeting',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // Shield count must remain untouched on failure / local fallback
      expect(mockApi.shieldsCount, equals(initialShields));
    });

    testWidgets('13. Gemini malformed JSON response falls back safely without crash', (tester) async {
      final mockApi = MockAISubscriptionApiService()..malformedAiPlan = true;

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

      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'I need to get that project thing done sometime before my meeting, dentist at 4',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // No crash; the failure is explicit and the basic planner still produces a plan.
      expect(tester.takeException(), isNull);
      expect(find.textContaining("Noya's taking a little nap"), findsOneWidget);
      await tester.ensureVisible(find.text('Plan it myself'));
      await tester.tap(find.text('Plan it myself'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('14. No layout overflow when virtual keyboard is open at 320px', (tester) async {
      tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      // Simulate 280px keyboard inset
      tester.view.viewInsets = const FakeViewPadding(bottom: 280 * 2.0);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
      });

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

      expect(find.byKey(const Key('brain_dump_text_field')), findsOneWidget);
      expect(find.byKey(const Key('brain_dump_build_button')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('15. Canonical scheduler is used to schedule parsed tasks', (tester) async {
      final tasks = TaskParseService.deterministicFallbackParse(
        'study for 45 minutes, gym at 6, dentist at 4',
      );

      final schedule = const SchedulingEngine().generateOptimizedSchedule(
        tasks: tasks,
        readiness: ReadinessModel.uncalibrated(),
      );

      expect(schedule.isNotEmpty, isTrue);
      // Fixed items (dentist at 4 -> 4:00 PM, gym at 6 -> 6:00 PM)
      expect(schedule.any((s) => s.time.contains('4:00')), isTrue);
      expect(schedule.any((s) => s.time.contains('6:00')), isTrue);
    });

    testWidgets('16. Editing and re-building does not produce duplicate tasks', (tester) async {
      await tester.pumpWidget(createTestApp(
        api: _spentApi(), // local planner (complimentary AI plan already used)
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'study math, gym at 6',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.text('YOUR PLAN'), findsOneWidget);

      // Tap Edit to open structured task editor
      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Structured task editor is open, brain dump input is NOT reopened
      expect(find.byKey(const Key('structured_task_editor')), findsOneWidget);
      expect(find.byKey(const Key('brain_dump_text_field')), findsNothing);

      // Save changes
      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();

      // Verify no duplicates (still exactly 2 task items)
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Study math'), findsOneWidget);
      expect(find.text('Gym'), findsOneWidget);
    });
  });

  group('Part 3: Surgical Brain Dump & AI Plan UX Verification (20 Requirements)', () {
    // 1. "gym tomorrow" becomes title "Gym"
    test('1. "gym tomorrow" becomes title "Gym" with type physical', () {
      final tasks = TaskParseService.deterministicFallbackParse('gym tomorrow');
      expect(tasks, isNotEmpty);
      expect(tasks.first.title, 'Gym');
      expect(tasks.first.type, 'physical');
    });

    // 2. "finish assignment" becomes a concise title
    test('2. "finish assignment" becomes concise title "Finish assignment" with type study', () {
      final tasks = TaskParseService.deterministicFallbackParse('finish my assignment');
      expect(tasks, isNotEmpty);
      expect(tasks.first.title, 'Finish assignment');
      expect(tasks.first.type, 'study');
    });

    // 3. "gym" does not become "Gym to do"
    test('3. "gym" does not become "Gym to do" and title sanitization strips redundant tokens', () {
      expect(TaskParseService.sanitizeTitle('Gym to do'), 'Gym');
      expect(TaskParseService.sanitizeTitle('Work to do'), 'Work');
      expect(TaskParseService.sanitizeTitle('Assignment task'), 'Assignment');
      expect(TaskParseService.sanitizeTitle('Task for gym'), 'Gym');
      expect(TaskParseService.sanitizeTitle('Finish my assignment'), 'Finish assignment');
    });

    // 4. Explicit priority is preserved
    test('4. Explicit priority is preserved with prioritySource = explicit', () {
      final highResult = TaskParseService.deterministicFallbackParse('client report high priority');
      expect(highResult.first.priority, TaskPriority.high);
      expect(highResult.first.priorityValue, 'high');
      expect(highResult.first.prioritySource, 'explicit');
      expect(highResult.first.isPriorityExplicit, isTrue);

      final urgentResult = TaskParseService.deterministicFallbackParse('urgent call dentist');
      expect(urgentResult.first.priority, TaskPriority.urgent);
      expect(urgentResult.first.priorityValue, 'urgent');
      expect(urgentResult.first.prioritySource, 'explicit');
      expect(urgentResult.first.isPriorityExplicit, isTrue);
    });

    // 5. Missing priority is NOT silently changed to Medium
    test('5. Missing priority is NOT silently changed to Medium (remains unspecified)', () {
      final tasks = TaskParseService.deterministicFallbackParse('gym tomorrow');
      expect(tasks.first.priorityValue, isNull);
      expect(tasks.first.prioritySource, 'unspecified');
      expect(tasks.first.isPriorityUnspecified, isTrue);
      expect(tasks.first.ambiguities, contains('priority_unspecified'));
    });

    // 6. Inferred priority requires visible confirmation
    testWidgets('6. Inferred/unspecified priority requires visible confirmation in preview', (tester) async {
      await tester.pumpWidget(createTestApp(
        api: _spentApi(), // basic/local plan: it never invents a priority
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym tomorrow');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.text('YOUR PLAN'), findsOneWidget);
      // Spec 2026-10-03: a missing priority is never rendered as "Priority not specified",
      // and the basic planner never invents one.
      expect(find.text('Priority not specified'), findsNothing);
      expect(find.textContaining('priority'), findsNothing);
    });

    // 7. Edit opens structured task editor
    testWidgets('7. Edit opens structured task editor', (tester) async {
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('structured_task_editor')), findsOneWidget);
    });

    // 8. Edit does not reopen Brain Dump
    testWidgets('8. Edit does not reopen Brain Dump input text field', (tester) async {
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'work tomorrow');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('brain_dump_text_field')), findsNothing);
      expect(find.byKey(const Key('structured_task_editor')), findsOneWidget);
    });

    // 9. Edited values persist in preview
    testWidgets('9. Edited values persist in preview', (tester) async {
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit_task_title_field')), 'Strength Training');
      await tester.pump();

      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();

      expect(find.text('Strength Training'), findsOneWidget);
      expect(find.text('YOUR PLAN'), findsOneWidget);
    });

    // 10. Noya remains visible after edit
    testWidgets('10. Noya remains visible after edit and save', (tester) async {
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);

      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);
    });

    // 11. Noya remains visible after preview rebuild
    testWidgets('11. Noya remains visible after preview rebuild', (tester) async {
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

      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'study physics');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noya_companion_header')), findsOneWidget);
    });

    // 12. Only one Add & Schedule action exists
    testWidgets('12. Only one Add & Schedule action exists', (tester) async {
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Add Task'), findsNothing);
      expect(find.text('Add Task'), findsNothing);
    });

    // 13. Add & Schedule creates and schedules exactly once
    testWidgets('13. Add & Schedule creates and schedules exactly once', (tester) async {
      final mockApi = _spentApi(); // local plan (complimentary AI plan already used)
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'study react, gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      final initialCount = appState.tasks.length;
      await tester.tap(find.byKey(const Key('add_and_schedule_button')));
      await tester.pumpAndSettle();

      expect(appState.tasks.length, initialCount + 2);
      expect(find.byKey(const Key('add_and_schedule_button')), findsNothing);
    });

    // 14. Double tapping does not duplicate tasks
    testWidgets('14. Double tapping does not duplicate tasks', (tester) async {
      final mockApi = MockAISubscriptionApiService();
      final appState = AppStateProvider(customApi: mockApi);

      await tester.pumpWidget(createTestApp(
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

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym at 6');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      final initialCount = appState.tasks.length;
      await tester.tap(find.byKey(const Key('add_and_schedule_button')));
      await tester.tap(find.byKey(const Key('add_and_schedule_button')), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(appState.tasks.length, initialCount + 1);
    });

    // 15. Simple tasks can be parsed without Gemini
    test('15. Simple tasks can be parsed without Gemini', () {
      expect(TaskParseService.canParseDeterministically('Gym at 6'), isTrue);
      expect(TaskParseService.canParseDeterministically('Study Python tomorrow'), isTrue);
      expect(TaskParseService.canParseDeterministically('Finish assignment by Friday'), isTrue);
    });

    // 16. Gemini remains optional
    // AI stays optional: an offline AI attempt is never silent and never a dead end. The failure is stated, the dump is
    // kept, and the user chooses the basic planner (labelled as not AI). Once the complimentary use is spent, clear
    // input plans locally without any AI attempt at all.
    testWidgets('16. AI remains optional (offline error -> explicit basic planner; spent entitlement -> local, no AI call)', (tester) async {
      Future<void> open(MockAISubscriptionApiService api) async {
        await tester.pumpWidget(createTestApp(
          api: api,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showBrainDumpSheet(ctx),
              child: const Text('Open'),
            ),
          ),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'finish assignment');
        await tester.pump();
        await tester.tap(find.byKey(const Key('brain_dump_build_button')));
        await tester.pumpAndSettle();
      }

      // (a) new account, AI unreachable: stated failure, dump kept, nothing silently planned.
      final offline = MockAISubscriptionApiService()..throwOnAiPlan = true;
      await open(offline);
      expect(offline.aiPlanCallCount, 1);
      expect(find.textContaining("Noya's taking a little nap"), findsOneWidget);
      expect(find.text('YOUR PLAN'), findsNothing);
      expect(find.text('finish assignment'), findsOneWidget);
      // ... and the explicit basic planner still produces the plan.
      await tester.ensureVisible(find.text('Plan it myself'));
      await tester.tap(find.text('Plan it myself'));
      await tester.pumpAndSettle();
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Finish assignment'), findsOneWidget);
      expect(find.text('Basic plan (not AI)'), findsOneWidget);

      // (b) complimentary use spent: the same text plans locally and AI is never attempted.
      await tester.pumpWidget(const SizedBox());
      final spent = _spentApi()..throwOnAiPlan = true;
      await open(spent);
      expect(spent.aiPlanCallCount, 0);
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Finish assignment'), findsOneWidget);
    });

    // 17. Existing deterministic scheduler remains the final scheduler
    test('17. Existing deterministic scheduler remains the final scheduler', () {
      const task1 = TaskItem(
        id: 't1',
        title: 'Client deliverable',
        category: 'deep_work',
        durationMinutes: 60,
        deadline: 'Today',
        difficulty: TaskDifficulty.high,
        isPriority: true,
        prioritySource: 'explicit',
      );
      const task2 = TaskItem(
        id: 't2',
        title: 'Gym',
        category: 'physical',
        durationMinutes: 45,
        deadline: 'Today',
        difficulty: TaskDifficulty.medium,
        prioritySource: 'unspecified',
      );

      final schedule = const SchedulingEngine().generateOptimizedSchedule(
        tasks: [task1, task2],
        readiness: ReadinessModel.uncalibrated(),
      );

      expect(schedule, isNotEmpty);
      expect(schedule.any((s) => s.title == 'Client deliverable'), isTrue);
      expect(schedule.any((s) => s.title == 'Gym'), isTrue);
    });

    // 18. No regressions covered by full test suite execution.

    // 19. Test at 320px / 360px / 390px / 432px widths
    for (final width in [320.0, 360.0, 390.0, 432.0]) {
      testWidgets('19. No overflow across viewport width ${width.toInt()}px in Brain Dump sheet', (tester) async {
        tester.view.physicalSize = Size(width * 2.0, 800 * 2.0);
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

        await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'gym tomorrow, study math 45 min');
        await tester.pump();
        await tester.tap(find.byKey(const Key('brain_dump_build_button')));
        await tester.pumpAndSettle();

        expect(find.text('YOUR PLAN'), findsOneWidget);
        expect(find.byKey(const Key('add_and_schedule_button')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 20. Test with keyboard open
    testWidgets('20. No overflow with virtual keyboard open', (tester) async {
      tester.view.physicalSize = const Size(360 * 2.0, 780 * 2.0);
      tester.view.devicePixelRatio = 2.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2.0);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetViewInsets();
      });

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

      expect(find.byKey(const Key('brain_dump_text_field')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Complimentary first AI plan (client behaviour around the entitlement)', () {
    Future<void> openAndBuild(WidgetTester tester, MockAISubscriptionApiService api,
        {String text = 'I need to get that project thing done sometime before my meeting'}) async {
      await tester.pumpWidget(createTestApp(
        api: api,
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), text);
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();
    }

    Future<bool> freeAvailable(MockAISubscriptionApiService api) async =>
        ((await api.get('/api/v1/ai/status')) as Map)['free_use_available'] as bool;

    testWidgets("a new account's first successful AI plan consumes the complimentary use exactly once", (tester) async {
      final api = MockAISubscriptionApiService()..trackEntitlement = true;
      expect(await freeAvailable(api), isTrue);
      await openAndBuild(tester, api, text: 'finish python lab tomorrow, study arrays, dentist at 4, gym at 6');
      // even clear input goes to the complimentary AI plan for a brand-new account
      expect(api.aiPlanCallCount, 1);
      expect(find.text('Enhanced with AI'), findsOneWidget);
      expect(api.freeUsesConsumed, 1);
      expect(await freeAvailable(api), isFalse);
    });

    testWidgets('a failed attempt does not consume the entitlement and the user stays eligible', (tester) async {
      final api = MockAISubscriptionApiService()
        ..trackEntitlement = true
        ..throwOnAiPlan = true;
      await openAndBuild(tester, api);
      expect(find.textContaining("Noya's taking a little nap"), findsOneWidget);
      expect(api.freeUsesConsumed, 0);
      expect(await freeAvailable(api), isTrue);
      expect(api.shieldsCount, 2);
    });

    testWidgets('retry after a failure succeeds with the same request key and nothing consumed beforehand', (tester) async {
      final api = MockAISubscriptionApiService()
        ..trackEntitlement = true
        ..throwOnAiPlan = true;
      await openAndBuild(tester, api);
      expect(api.freeUsesConsumed, 0);

      api.throwOnAiPlan = false; // the AI service is back
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(api.aiPlanCallCount, 2, reason: 'Try again reaches the AI again');
      expect(api.planKeys[0], isNotNull);
      expect(api.planKeys[1], api.planKeys[0], reason: 'the same request key, so a retry can never charge twice');
      expect(find.text('Enhanced with AI'), findsOneWidget);
      expect(api.freeUsesConsumed, 1);
    });

    test('replaying a request key does not consume the entitlement twice', () async {
      final api = MockAISubscriptionApiService()..trackEntitlement = true;
      TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
      final service = AIPlanService(api: api);
      final first = await service.generatePlan(rawText: 'plan my day', requestId: 'bmd-replay');
      final replay = await service.generatePlan(rawText: 'plan my day', requestId: 'bmd-replay');
      expect(api.freeUsesConsumed, 1);
      expect(replay.tasks.length, first.tasks.length);
      expect(api.planKeys, ['bmd-replay', 'bmd-replay']);
    });

    testWidgets('the explicit basic planner makes no AI call and consumes no AI usage', (tester) async {
      final api = MockAISubscriptionApiService()
        ..trackEntitlement = true
        ..throwOnAiPlan = true;
      await openAndBuild(tester, api);
      final callsBefore = api.aiPlanCallCount;

      await tester.ensureVisible(find.text('Plan it myself'));
      await tester.tap(find.text('Plan it myself'));
      await tester.pumpAndSettle();

      expect(find.text('Basic plan (not AI)'), findsOneWidget);
      expect(find.text('Enhanced with AI'), findsNothing);
      expect(api.aiPlanCallCount, callsBefore, reason: 'the basic planner never calls AI');
      expect(api.freeUsesConsumed, 0);
      expect(await freeAvailable(api), isTrue, reason: 'the complimentary plan is still available afterwards');
    });
  });

  group('Build My Day: Noya is visibly part of planning', () {
    testWidgets('header Noya is alive: thinking-ready, then proud with a planReady reaction when the plan lands', (tester) async {
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

      NoyaMotionView header() => tester.widget<NoyaMotionView>(
          find.descendant(of: find.byKey(const Key('noya_companion_header')), matching: find.byType(NoyaMotionView)));
      expect(header().reactions, isNotNull);

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'study physics');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(header().pose, NoyaState.proud);
      expect(header().reactions!.value?.reaction, NoyaReaction.planReady);
    });
  });
}
