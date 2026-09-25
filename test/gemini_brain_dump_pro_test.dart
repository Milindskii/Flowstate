import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/screens/ai_plan_preview_sheet.dart';
import 'package:flowstate/screens/pro_subscription_screen.dart';
import 'package:flowstate/screens/profile_settings_tab.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';

class MockAISubscriptionApiService extends ApiService {
  bool returnPro = false;
  bool returnFreeExhausted = false;
  int shieldsCount = 2;

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
}) {
  final mockApi = api ?? MockAISubscriptionApiService();
  final appState = AppStateProvider(customApi: mockApi);
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

  // 1. Microphone is gone
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

    // Verify Brain dump UI is open
    expect(find.text('What else is on your plate?'), findsOneWidget);
    expect(find.text('Just write it out.'), findsOneWidget);

    // Verify microphone icon is completely gone
    expect(find.byIcon(Icons.mic), findsNothing);
    expect(find.byIcon(Icons.mic_none), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsNothing);
    expect(find.byIcon(Icons.mic_off), findsNothing);
    expect(find.textContaining('Voice'), findsNothing);
  });

  // 2. Brain Dump text input works
  testWidgets('2. Brain Dump text input works naturally with unformatted input', (tester) async {
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

    final textField = find.byKey(const Key('brain_dump_text_field'));
    expect(textField, findsOneWidget);

    const naturalText = 'finish my python lab tomorrow, study arrays, call the dentist at 4, gym at 6';
    await tester.enterText(textField, naturalText);
    await tester.pump();

    expect(find.text(naturalText), findsOneWidget);
  });

  // 3. Build button works
  testWidgets('3. Build button enables only on valid input and triggers action', (tester) async {
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

    final buildButtonFinder = find.byKey(const Key('brain_dump_build_button'));
    expect(buildButtonFinder, findsOneWidget);

    // Initially, Build button is disabled (ElevatedButton onPressed is null)
    final initialButton = tester.widget<ElevatedButton>(buildButtonFinder);
    expect(initialButton.onPressed, isNull);

    // Enter text
    await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Study Python tonight');
    await tester.pump();

    // Now button should be enabled
    final enabledButton = tester.widget<ElevatedButton>(buildButtonFinder);
    expect(enabledButton.onPressed, isNotNull);
  });

  // 4. Confirmation state works
  testWidgets('4. Confirmation state works for inferred or uncertain task details', (tester) async {
    final uncertainPlan = AIPlanResult(
      tasks: const [
        ExtractedTaskItem(
          title: 'Python lab',
          type: 'study',
          estimatedMinutes: 60,
          difficulty: 'high',
          priority: 'high',
          prioritySource: 'inferred',
          deadline: 'tomorrow',
          needsConfirmation: true,
        ),
      ],
      needsConfirmation: true,
    );

    await tester.pumpWidget(createTestApp(
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showAIPlanPreviewSheet(ctx, planResult: uncertainPlan),
          child: const Text('Preview'),
        ),
      ),
    ));

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    // Confirmation header and prompt
    expect(find.text("Flowstate isn't completely sure about this."), findsOneWidget);
    expect(find.text('Is this correct?'), findsOneWidget);

    // Inferred priority is highlighted
    expect(find.textContaining('High priority (Inferred)'), findsOneWidget);

    // Confirm and Edit buttons are visible
    expect(find.byKey(const Key('yes_build_day_button')), findsOneWidget);
    expect(find.byKey(const Key('edit_button')), findsOneWidget);
  });

  // 5. Shield confirmation works
  testWidgets('5. Shield confirmation sheet displays consequence and handles acceptance', (tester) async {
    bool? confirmed;

    await tester.pumpWidget(createTestApp(
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            confirmed = await showShieldConfirmationSheet(
              ctx,
              shieldsAvailable: 2,
              freeRemaining: 0,
            );
          },
          child: const Text('Open Shield Sheet'),
        ),
      ),
    ));

    await tester.tap(find.text('Open Shield Sheet'));
    await tester.pumpAndSettle();

    // UI elements
    expect(find.text('Use a Shield?'), findsOneWidget);
    expect(find.text('You have 0 free AI plans remaining.'), findsOneWidget);
    expect(find.textContaining('Shields can also protect your Flow streak.'), findsOneWidget);
    expect(find.text('Available: 2 Shields'), findsOneWidget);

    // Tap Use 1 Shield
    await tester.tap(find.byKey(const Key('use_1_shield_button')));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  // 6. Free AI exhausted state works
  testWidgets('6. Free AI exhausted state shows Go Pro navigation prompt', (tester) async {
    bool wentPro = false;

    await tester.pumpWidget(createTestApp(
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () {
            showAIExhaustedSheet(
              ctx,
              onGoPro: () => wentPro = true,
            );
          },
          child: const Text('Open Exhausted'),
        ),
      ),
    ));

    await tester.tap(find.text('Open Exhausted'));
    await tester.pumpAndSettle();

    expect(find.text("You've used your free AI plan."), findsOneWidget);
    expect(find.text('Use a Shield for another plan or upgrade to Pro.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('go_pro_exhausted_button')));
    await tester.pumpAndSettle();

    expect(wentPro, isTrue);
  });

  // 7. Go Pro opens from Profile
  testWidgets('7. Go Pro section inside Profile opens ProSubscriptionScreen', (tester) async {
    final mockApi = MockAISubscriptionApiService()..returnPro = false;

    await tester.pumpWidget(createTestApp(
      api: mockApi,
      child: const ProfileSettingsTab(),
    ));

    await tester.pumpAndSettle();

    // Verify "GO PRO" card is in Profile
    expect(find.text('GO PRO'), findsOneWidget);
    expect(find.text('More planning power for your Flow.'), findsOneWidget);

    // Tap Explore Pro
    final exploreBtn = find.byKey(const Key('explore_pro_button'));
    expect(exploreBtn, findsOneWidget);
    await tester.tap(exploreBtn);
    await tester.pumpAndSettle();

    // Verify ProSubscriptionScreen is now open
    expect(find.text('Flowstate, without limits.'), findsOneWidget);
  });

  // 8. Pro screen renders Monthly/Yearly
  testWidgets('8. Pro screen renders Monthly and Yearly option cards with toggling', (tester) async {
    await tester.pumpWidget(createTestApp(
      child: const ProSubscriptionScreen(),
    ));

    await tester.pumpAndSettle();

    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(find.text('Best value'), findsOneWidget);
    expect(find.text('Continue with Pro'), findsOneWidget);

    // Tap Monthly
    await tester.tap(find.text('Monthly'));
    await tester.pumpAndSettle();

    // Tap Yearly
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
  });

  // 9. No fake prices
  testWidgets('9. Pro screen shows no fake prices or fake discounts', (tester) async {
    await tester.pumpWidget(createTestApp(
      child: const ProSubscriptionScreen(),
    ));

    await tester.pumpAndSettle();

    // Verify fallback prices are TBD placeholder
    expect(find.text('₹— / month'), findsOneWidget);
    expect(find.text('₹— / year'), findsOneWidget);
    expect(find.text('Pricing coming soon'), findsNWidgets(2));

    // Verify no fake prices like ₹199 or ₹999 or fake percentage savings
    expect(find.textContaining('₹199'), findsNothing);
    expect(find.textContaining('₹999'), findsNothing);
    expect(find.textContaining('% off'), findsNothing);
  });

  // 10A. Free profile renders GO PRO
  testWidgets('10A. Free profile renders GO PRO and Explore Pro', (tester) async {
    final freeApi = MockAISubscriptionApiService()..returnPro = false;
    await tester.pumpWidget(createTestApp(
      api: freeApi,
      child: const ProfileSettingsTab(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('GO PRO'), findsOneWidget);
    expect(find.text('Explore Pro'), findsOneWidget);
  });

  // 10B. Pro profile renders verified FLOWSTATE PRO state
  testWidgets('10B. Pro profile renders backend-verified FLOWSTATE PRO state', (tester) async {
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

  // 11. Narrow Android screens have no overflow
  testWidgets('11. Narrow Android screen displays without layout overflow', (tester) async {
    // 320x640 narrow test viewport
    tester.view.physicalSize = const Size(320 * 2.0, 640 * 2.0);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Test Pro Subscription Screen
    await tester.pumpWidget(createTestApp(
      child: const ProSubscriptionScreen(),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Test Shield Confirmation Sheet
    await tester.pumpWidget(createTestApp(
      child: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () => showShieldConfirmationSheet(ctx, shieldsAvailable: 1),
          child: const Text('Show'),
        ),
      ),
    ));
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
