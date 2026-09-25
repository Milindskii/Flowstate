import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/models/task_item.dart';

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
  });
}
