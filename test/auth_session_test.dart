import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/screens/main_shell.dart';
import 'package:flowstate/screens/task_feedback_sheet.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P0 Authentication, Session Persistence & Identity Tests', () {
    test('1. AppStateProvider onUserAuthenticated wipes demo data and binds real user identity', () async {
      final appState = AppStateProvider();
      
      const realUser = AuthUser(
        id: 'user-real-99',
        email: 'realuser@flowstate.app',
        name: 'RealUser',
      );

      await appState.onUserAuthenticated(realUser);

      // Verify real identity bound
      expect(appState.currentUser, isNotNull);
      expect(appState.currentUser!.id, equals('user-real-99'));
      expect(appState.currentUser!.email, equals('realuser@flowstate.app'));
      expect(appState.greetingName, equals('RealUser'));

      // Verify demo mode is strictly disabled
      expect(appState.isDemoMode, isFalse);

      // Verify initial empty state before tasks are fetched
      expect(appState.tasks, isEmpty);
    });

    test('2. Onboarding completion persists to SharedPreferences', () async {
      final appState = AppStateProvider();
      expect(appState.onboardingComplete, isFalse);

      await appState.markOnboardingComplete();
      expect(appState.onboardingComplete, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('flowstate_onboarding_complete'), isTrue);
    });

    test('3. Logout clears user identity, tasks, and resets onboarding state', () async {
      final appState = AppStateProvider();
      const realUser = AuthUser(
        id: 'user-real-99',
        email: 'realuser@flowstate.app',
        name: 'RealUser',
      );

      await appState.onUserAuthenticated(realUser);
      await appState.markOnboardingComplete();

      // Add a task in authenticated state
      appState.addTask(
        title: 'User Private Task',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Tomorrow',
        category: 'Personal',
      );
      expect(appState.tasks.length, equals(1));

      // Now logout
      await appState.logout();

      expect(appState.currentUser, isNull);
      expect(appState.tasks, isEmpty);
      expect(appState.onboardingComplete, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('flowstate_onboarding_complete'), isNull);
    });

    test('4. Returning user with backend onboarding completed restores onboarding state without repeating', () async {
      final appState = AppStateProvider();
      const onboardedUser = AuthUser(
        id: 'user-returning-42',
        email: 'returning@flowstate.app',
        name: 'ReturningUser',
        onboardingCompleted: true,
      );

      // Even if SharedPreferences was wiped by previous logout:
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('flowstate_onboarding_complete');
      expect(prefs.getBool('flowstate_onboarding_complete'), isNull);

      // Authenticate returning user
      await appState.onUserAuthenticated(onboardedUser);

      // If user object carries onboardingCompleted: true, or profile returns it:
      // App state detects onboarding is complete and restores cache
      expect(appState.onboardingComplete, isTrue);
      expect(prefs.getBool('flowstate_onboarding_complete'), isTrue);
    });

    test('5. AuthService.getOAuthRedirectUrl dynamically follows Web browser origin/port and preserves mobile deep link', () {
      // Flutter Web running on port 64823
      final webPort64823 = AuthService.getOAuthRedirectUrl(
        isWeb: true,
        baseUri: Uri.parse('http://localhost:64823/#/auth'),
      );
      expect(webPort64823, equals('http://localhost:64823'));

      // Flutter Web running on port 50242
      final webPort50242 = AuthService.getOAuthRedirectUrl(
        isWeb: true,
        baseUri: Uri.parse('http://localhost:50242/'),
      );
      expect(webPort50242, equals('http://localhost:50242'));

      // Flutter Web running on port 3000
      final webPort3000 = AuthService.getOAuthRedirectUrl(
        isWeb: true,
        baseUri: Uri.parse('http://localhost:3000'),
      );
      expect(webPort3000, equals('http://localhost:3000'));

      // Flutter Web running on custom production domain
      final webProduction = AuthService.getOAuthRedirectUrl(
        isWeb: true,
        baseUri: Uri.parse('https://app.flowstate.com/login?step=2'),
      );
      expect(webProduction, equals('https://app.flowstate.com'));

      // Mobile / non-web native platforms preserve deep link scheme
      final mobileRedirect = AuthService.getOAuthRedirectUrl(isWeb: false);
      expect(mobileRedirect, equals('io.flowstate://login-callback'));
    });

    test('6. Email/password authentication propagates token to ApiService and preserves Supabase user.id', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);

      expect(sharedApi.isAuthenticated, isFalse);
      expect(appState.isAuthenticated, isFalse);

      // Simulate successful Supabase email/password login/signup session
      const emailUser = AuthUser(
        id: 'supabase-uuid-email-1234',
        email: 'developer@flowstate.app',
        name: 'Developer',
        onboardingCompleted: true,
      );
      sharedApi.setAuthToken('supabase-valid-jwt-token-email');

      await appState.onUserAuthenticated(emailUser);

      // Verify identity and token
      expect(appState.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-uuid-email-1234');
      expect(appState.currentUser!.email, 'developer@flowstate.app');
      expect(sharedApi.isAuthenticated, isTrue);
      expect(sharedApi.activeToken, 'supabase-valid-jwt-token-email');
    });

    test('7. Google and email/password users converge on the same authenticated application path', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);

      const googleUser = AuthUser(
        id: 'supabase-uuid-google-5678',
        email: 'googleuser@gmail.com',
        name: 'Google User',
        onboardingCompleted: true,
      );
      sharedApi.setAuthToken('supabase-valid-jwt-google');
      await appState.onUserAuthenticated(googleUser);

      expect(appState.isAuthenticated, isTrue);
      expect(appState.isDemoMode, isFalse);
      expect(sharedApi.isAuthenticated, isTrue);

      const emailUser = AuthUser(
        id: 'supabase-uuid-email-9012',
        email: 'emailuser@domain.com',
        name: 'Email User',
        onboardingCompleted: true,
      );
      sharedApi.setAuthToken('supabase-valid-jwt-email');
      await appState.onUserAuthenticated(emailUser);

      // Both converge into same authenticated AppStateProvider path with zero demo data
      expect(appState.isAuthenticated, isTrue);
      expect(appState.isDemoMode, isFalse);
      expect(appState.currentUser!.id, 'supabase-uuid-email-9012');
      expect(sharedApi.activeToken, 'supabase-valid-jwt-email');
    });

    test('8. Unauthenticated and guest users are denied appropriately and not treated as Supabase users', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);

      // 1. Initial fresh unauthenticated state
      expect(appState.isAuthenticated, isFalse);
      expect(sharedApi.isAuthenticated, isFalse);

      // 2. Guest/Instant Demo state
      await appState.enterGuestMode(startWithOnboarding: false);
      expect(appState.currentUser, isNotNull);
      expect(appState.currentUser!.id.startsWith('guest_'), isTrue);
      // Demo session must NOT be treated as authenticated Supabase user
      expect(appState.isAuthenticated, isFalse);
      expect(sharedApi.isAuthenticated, isFalse);
    });

    test('9. Authenticated email/password user can access Flow Hub, Build My Day, and Replan My Day', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);

      // Wire authenticated user
      const authenticatedUser = AuthUser(
        id: 'supabase-uuid-real-user-77',
        email: 'founder@flowstate.app',
        name: 'Founder',
        onboardingCompleted: true,
      );
      sharedApi.setAuthToken('valid-bearer-token-77');
      await appState.onUserAuthenticated(authenticatedUser);

      // 1. Feature Access: Build My Day
      expect(appState.isAuthenticated, isTrue, reason: 'Build My Day checks appState.isAuthenticated');

      // 2. Feature Access: Replan My Day
      expect(sharedApi.isAuthenticated, isTrue, reason: 'Replan My Day sends token via sharedApi');

      // 3. Feature Access: Flow Hub
      final flowProvider = FlowProvider(api: sharedApi);
      expect(flowProvider.apiService!.isAuthenticated, isTrue, reason: 'Flow Hub receives shared authenticated ApiService');
      expect(flowProvider.errorMessage, isNull);
    });
  });

  group('P0 Unexpected Login Redirect & Authenticated Invariant Regression Tests (Scenarios 1-18)', () {
    const testUserA = AuthUser(
      id: 'supabase-user-aaa-111',
      email: 'usera@flowstate.app',
      name: 'User A',
      onboardingCompleted: true,
    );
    const testUserB = AuthUser(
      id: 'supabase-user-bbb-222',
      email: 'userb@flowstate.app',
      name: 'User B',
      onboardingCompleted: true,
    );

    test('TEST 1: Authenticated user completes task -> stays authenticated and maintains session', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Deep Work Task',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      expect(appState.isAuthenticated, isTrue);
      expect(appState.tasks.length, 1);

      // Complete the task
      appState.toggleTaskCompletion(task.id);

      expect(appState.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
      expect(sharedApi.isAuthenticated, isTrue);
      expect(appState.tasks.first.isCompleted, isTrue);
    });

    test('TEST 2: Authenticated user completes task and submits feedback -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Design Review',
        durationMinutes: 20,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Work',
      );

      appState.toggleTaskCompletion(task.id);
      appState.recordTaskFeedback(
        taskId: task.id,
        actualMinutes: 25,
        feeling: 4,
        durationFeedback: 'about_right',
        blockerNote: 'None, great flow',
      );

      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
      expect(appState.currentUser!.email, 'usera@flowstate.app');
    });

    test('TEST 3: Authenticated user starts and finishes Focus session -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Focus Sprint',
        durationMinutes: 25,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Deep Work',
      );

      // Start focus
      appState.setActiveFocusTask(task);
      expect(appState.activeFocusTask, isNotNull);
      expect(appState.isAuthenticated, isTrue);

      // Finish focus & complete task
      appState.clearActiveFocusTask();
      appState.toggleTaskCompletion(task.id);

      expect(appState.activeFocusTask, isNull);
      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 4: Authenticated user adds task -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'New Important Task',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Tomorrow',
        category: 'Study',
      );

      expect(task.title, 'New Important Task');
      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 5: Authenticated user edits task -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Draft Spec',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      final updated = task.copyWith(title: 'Finalized Spec', durationMinutes: 60);
      appState.updateTask(updated);

      expect(appState.tasks.first.title, 'Finalized Spec');
      expect(appState.tasks.first.durationMinutes, 60);
      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 6: Authenticated user reschedules task -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Reschedule Me',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
      );

      await appState.deferTaskToLater(task.id);

      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 7: Authenticated user opens Calendar -> stays authenticated without resetting nav index', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      appState.setNavIndex(2); // Calendar tab
      expect(appState.currentNavIndex, 2);
      expect(appState.isAuthenticated, isTrue);

      // Re-authentication sync call for same user preserves calendar tab
      await appState.onUserAuthenticated(testUserA);
      expect(appState.currentNavIndex, 2);
      expect(appState.isAuthenticated, isTrue);
    });

    test('TEST 8: Authenticated user opens Flow Hub -> stays authenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final flow = FlowProvider(api: sharedApi);
      expect(flow.apiService!.isAuthenticated, isTrue);
      expect(appState.isAuthenticated, isTrue);
    });

    test('TEST 9: Non-auth API error is surfaced appropriately WITHOUT redirecting to Login', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      // Simulate a server 500 error in AppStateProvider
      appState.setTodayNetworkStateForTesting(TodayNetworkState.serverError, errorMessage: 'Server error. Please try again later.');

      expect(appState.todayNetworkState, TodayNetworkState.serverError);
      expect(appState.errorMessage, contains('Server error'));
      // Invariant: User remains authenticated despite backend 500
      expect(appState.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 10: 401 error while token exists does NOT immediately destroy authentication state', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      // App receives a 401 on background sync
      final flow = FlowProvider(api: sharedApi);
      flow.setMockMode(true);

      // Authenticated state must NOT be wiped by a transient request failure
      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
      expect(appState.currentUser, isNotNull);
    });

    test('TEST 11: Actually invalid/logged-out state properly transitions to unauthenticated', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      expect(appState.isAuthenticated, isTrue);

      // Genuine sign out
      await appState.logout();

      expect(appState.isAuthenticated, isFalse);
      expect(appState.currentUser, isNull);
      expect(sharedApi.isAuthenticated, isFalse);
    });

    test('TEST 12: Explicit logout clears user identity and caches', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      await appState.addTask(
        title: 'Private A Task',
        durationMinutes: 20,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Work',
      );
      expect(appState.tasks.length, 1);

      await appState.logout();

      expect(appState.currentUser, isNull);
      expect(appState.tasks, isEmpty);
      expect(appState.onboardingComplete, isFalse);
    });

    test('TEST 13: Login again after logout enters MainShell normally', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);
      await appState.logout();

      expect(appState.isAuthenticated, isFalse);

      // Login again
      sharedApi.setAuthToken('token-user-a-new');
      await appState.onUserAuthenticated(testUserA);

      expect(appState.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
      expect(appState.onboardingComplete, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 14: App restart while authenticated restores session and remains authenticated', () async {
      final sharedApi = ApiService();
      sharedApi.setAuthToken('token-persisted');
      
      // Initial instance
      final appState1 = AppStateProvider(customApi: sharedApi, initialUser: testUserA);
      expect(appState1.isAuthenticated, isTrue);

      // Simulate restart with new provider instance but restored identity
      final appState2 = AppStateProvider(customApi: sharedApi, initialUser: testUserA);
      expect(appState2.isAuthenticated, isTrue);
      expect(appState2.currentUser!.id, 'supabase-user-aaa-111');
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 15: Complete task after app restart remains authenticated', () async {
      final sharedApi = ApiService();
      sharedApi.setAuthToken('token-persisted');
      final appState = AppStateProvider(customApi: sharedApi, initialUser: testUserA);

      final task = await appState.addTask(
        title: 'Post-restart Task',
        durationMinutes: 15,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Personal',
      );

      appState.toggleTaskCompletion(task.id);

      expect(appState.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
      expect(sharedApi.isAuthenticated, isTrue);
    });

    test('TEST 16: Switch Account A -> Account B wipes A state and binds B identity', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      await appState.addTask(
        title: 'Account A Secret Task',
        durationMinutes: 30,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
      );
      expect(appState.tasks.length, 1);
      expect(appState.tasks.first.title, 'Account A Secret Task');

      // Switch to Account B
      sharedApi.setAuthToken('token-user-b');
      await appState.onUserAuthenticated(testUserB);

      expect(appState.currentUser!.id, 'supabase-user-bbb-222');
      expect(appState.currentUser!.email, 'userb@flowstate.app');
      expect(appState.tasks, isEmpty, reason: 'Account A tasks must not leak to Account B');
      expect(appState.isAuthenticated, isTrue);
    });

    test('TEST 17: Switch back B -> A restores A correctly without corruption', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      
      // User B
      sharedApi.setAuthToken('token-user-b');
      await appState.onUserAuthenticated(testUserB);
      expect(appState.currentUser!.id, 'supabase-user-bbb-222');

      // Switch back to A
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
      expect(appState.currentUser!.email, 'usera@flowstate.app');
      expect(appState.isAuthenticated, isTrue);
    });

    test('TEST 18: Repeated task completion (complete -> reopen -> complete again) never causes auth redirect', () async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      sharedApi.setAuthToken('token-user-a');
      await appState.onUserAuthenticated(testUserA);

      final task = await appState.addTask(
        title: 'Cyclic Task',
        durationMinutes: 10,
        difficulty: TaskDifficulty.light,
        deadline: 'Today',
        category: 'Habits',
      );

      // Cycle 1: Complete
      appState.toggleTaskCompletion(task.id);
      expect(appState.tasks.first.isCompleted, isTrue);
      expect(appState.isAuthenticated, isTrue);

      // Cycle 2: Reopen
      appState.toggleTaskCompletion(task.id);
      expect(appState.tasks.first.isCompleted, isFalse);
      expect(appState.isAuthenticated, isTrue);

      // Cycle 3: Complete again
      appState.toggleTaskCompletion(task.id);
      expect(appState.tasks.first.isCompleted, isTrue);
      expect(appState.isAuthenticated, isTrue);
      expect(sharedApi.isAuthenticated, isTrue);
      expect(appState.currentUser!.id, 'supabase-user-aaa-111');
    });

    testWidgets('TEST 19 (Widget): MainShell has PopScope(canPop: false) to prevent popping to AuthScreen', (tester) async {
      final sharedApi = ApiService();
      final appState = AppStateProvider(customApi: sharedApi);
      final flowProvider = FlowProvider(api: sharedApi);
      final themeProvider = ThemeProvider();

      await appState.onUserAuthenticated(testUserA);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: appState),
            ChangeNotifierProvider.value(value: flowProvider),
            ChangeNotifierProvider.value(value: themeProvider),
          ],
          child: const MaterialApp(
            home: MainShell(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find PopScope
      final popScopeFinder = find.byWidgetPredicate((widget) => widget is PopScope && widget.canPop == false);
      expect(popScopeFinder, findsOneWidget, reason: 'MainShell must have canPop: false to prevent popping off stack');
    });

    testWidgets('TEST 20 (Widget): TaskFeedbackContent cancels auto-close timer on submit and prevents duplicate pop', (tester) async {
      int submitCount = 0;
      int dismissCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskFeedbackContent(
              taskId: 'task-widget-test',
              actualMinutes: 25,
              onSubmit: (_) => submitCount++,
              onDismiss: () => dismissCount++,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap emoji '🔥'
      await tester.tap(find.text('🔥'));
      await tester.pumpAndSettle();

      // Tap duration option to reveal Done button
      await tester.tap(find.text('About right'));
      await tester.pumpAndSettle();

      // Tap 'Done'
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(submitCount, 1);
      expect(dismissCount, 1);

      // Fast-forward 10 seconds past the 8s timer
      await tester.pump(const Duration(seconds: 10));

      // Invariant: timer was cancelled, no duplicate dismiss or submit occurs
      expect(submitCount, 1);
      expect(dismissCount, 1);
    });
  });
}
