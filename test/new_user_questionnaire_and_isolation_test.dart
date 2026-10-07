import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/models/task_item.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('New User Questionnaire & Account Isolation Test Suite', () {
    test('1. Brand-new email/password account routes to Questionnaire BEFORE Today', () async {
      final appState = AppStateProvider();
      const newEmailUser = AuthUser(
        id: 'user-brand-new-1',
        email: 'brandnew@flowstate.app',
        name: 'BrandNew',
        onboardingCompleted: false,
      );

      await appState.onUserAuthenticated(newEmailUser);

      // Verify onboardingComplete is strictly FALSE for brand-new account
      expect(appState.onboardingComplete, isFalse);

      // Verify Today tasks are empty
      expect(appState.tasks, isEmpty);
    });

    test('2. Complete questionnaire persists responses and personalization state, then marks complete', () async {
      final appState = AppStateProvider();
      const user = AuthUser(
        id: 'user-brand-new-2',
        email: 'completer@flowstate.app',
        name: 'Completer',
        onboardingCompleted: false,
      );

      await appState.onUserAuthenticated(user);
      expect(appState.onboardingComplete, isFalse);

      // Simulate questionnaire response with afternoon peak
      appState.updatePersonalData(
        appState.personalData.copyWith(
          focusPeak: 'Afternoon',
          wakeTime: '08:00',
          bedtime: '00:00',
        ),
      );

      // Mark onboarding complete
      await appState.markOnboardingComplete();

      expect(appState.onboardingComplete, isTrue);
      expect(appState.personalData.focusPeak, equals('Afternoon'));
      expect(appState.personalData.wakeTime, equals('08:00'));

      // Verify persistent storage under user-scoped key
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('flowstate_onboarding_complete_${user.id}'), isTrue);
    });

    test('3. Restart app with same completed account skips questionnaire', () async {
      // User previously completed onboarding: stored in user-scoped preferences
      SharedPreferences.setMockInitialValues({
        'flowstate_onboarding_complete_user-completed-3': true,
      });

      const returningUser = AuthUser(
        id: 'user-completed-3',
        email: 'returning3@flowstate.app',
        name: 'Returning3',
        onboardingCompleted: true,
      );

      final appState = AppStateProvider(initialUser: returningUser);
      await appState.onUserAuthenticated(returningUser);

      expect(appState.onboardingComplete, isTrue);
    });

    test('4. Logout and login with same completed account skips questionnaire', () async {
      final appState = AppStateProvider();
      const user = AuthUser(
        id: 'user-relogin-4',
        email: 'relogin@flowstate.app',
        name: 'Relogin',
        onboardingCompleted: false,
      );

      await appState.onUserAuthenticated(user);
      await appState.markOnboardingComplete();
      expect(appState.onboardingComplete, isTrue);

      // Logout
      await appState.logout();
      expect(appState.currentUser, isNull);
      expect(appState.onboardingComplete, isFalse);

      // Relogin with same account (now backend/local records it as completed)
      const sameUserCompleted = AuthUser(
        id: 'user-relogin-4',
        email: 'relogin@flowstate.app',
        name: 'Relogin',
        onboardingCompleted: true,
      );
      await appState.onUserAuthenticated(sameUserCompleted);

      expect(appState.onboardingComplete, isTrue);
    });

    test('5. Second brand-new account (Account B) MUST see questionnaire even if Account A completed it', () async {
      final appState = AppStateProvider();

      // Account A completes questionnaire
      const userA = AuthUser(
        id: 'user-account-A',
        email: 'alice@flowstate.app',
        name: 'Alice',
        onboardingCompleted: false,
      );
      await appState.onUserAuthenticated(userA);
      await appState.markOnboardingComplete();
      expect(appState.onboardingComplete, isTrue);

      // Account A logs out
      await appState.logout();
      expect(appState.currentUser, isNull);
      expect(appState.onboardingComplete, isFalse);

      // Account B logs in / signs up (brand new user)
      const userB = AuthUser(
        id: 'user-account-B',
        email: 'bob@flowstate.app',
        name: 'Bob',
        onboardingCompleted: false,
      );
      await appState.onUserAuthenticated(userB);

      // Account B MUST NOT inherit Account A's completed state!
      expect(appState.onboardingComplete, isFalse,
          reason: "Account B is a new account and must see the questionnaire");
      expect(appState.currentUser!.id, equals('user-account-B'));
    });

    test('6. Account A data (tasks, focus, personalization) never appears for Account B', () async {
      final appState = AppStateProvider();

      // Account A signs in and adds private tasks
      const userA = AuthUser(
        id: 'user-account-A',
        email: 'alice@flowstate.app',
        name: 'Alice',
        onboardingCompleted: true,
      );
      await appState.onUserAuthenticated(userA);
      await appState.addTask(
        title: 'Alice Private NDA Project',
        durationMinutes: 60,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Work',
      );
      expect(appState.tasks.length, equals(1));
      expect(appState.tasks.first.title, contains('Alice Private'));

      // Logout Account A
      await appState.logout();
      expect(appState.tasks, isEmpty);

      // Account B signs in
      const userB = AuthUser(
        id: 'user-account-B',
        email: 'bob@flowstate.app',
        name: 'Bob',
        onboardingCompleted: false,
      );
      await appState.onUserAuthenticated(userB);

      // Account B has zero tasks and cannot see Alice's tasks
      expect(appState.tasks, isEmpty);
      expect(appState.currentUser!.name, equals('Bob'));
      expect(appState.onboardingComplete, isFalse);
    });

    test('7. Incomplete onboarding restores saved answers and step when user logs in again', () async {
      const userId = 'user-incomplete-7';
      // Simulate partial onboarding progress saved to SharedPreferences
      final partialAnswers = {
        'peak_window': 'afternoon',
        'wake_weekday': '08:30',
        'sleep_time': '00:30',
      };
      SharedPreferences.setMockInitialValues({
        'flowstate_onboarding_answers_$userId': jsonEncode(partialAnswers),
        'flowstate_onboarding_step_$userId': 3,
      });

      const user = AuthUser(
        id: userId,
        email: 'incomplete@flowstate.app',
        name: 'Incomplete',
        onboardingCompleted: false,
      );

      final appState = AppStateProvider();
      await appState.onUserAuthenticated(user);

      // Still incomplete
      expect(appState.onboardingComplete, isFalse);

      // Verify partial answers exist in SharedPreferences for this user
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('flowstate_onboarding_answers_$userId');
      expect(savedStr, isNotNull);
      final decoded = jsonDecode(savedStr!) as Map<String, dynamic>;
      expect(decoded['peak_window'], equals('afternoon'));
      expect(prefs.getInt('flowstate_onboarding_step_$userId'), equals(3));
    });

    test('8. Personalization: changing peak window directly changes personal data and schedule engine profile', () async {
      final appState = AppStateProvider();
      const user = AuthUser(
        id: 'user-persona-8',
        email: 'persona@flowstate.app',
        name: 'Persona',
        onboardingCompleted: false,
      );

      await appState.onUserAuthenticated(user);

      // Initially morning
      expect(appState.personalData.focusPeak, equals('Morning'));

      // User selects Evening in questionnaire
      appState.updatePersonalData(
        appState.personalData.copyWith(focusPeak: 'Evening'),
      );
      expect(appState.personalData.focusPeak, equals('Evening'));

      // Add a deep work task
      await appState.addTask(
        title: 'Deep Architecture Analysis',
        durationMinutes: 90,
        difficulty: TaskDifficulty.high,
        deadline: 'Today',
        category: 'Engineering',
        isPriority: true,
      );

      // Schedule recalculates using personal profile
      expect(appState.schedule, isNotEmpty);
    });

    test('9. FlowProvider reset clears in-memory state on logout', () {
      final flowProvider = FlowProvider();
      expect(flowProvider.isFocusing, isFalse);

      flowProvider.reset();
      expect(flowProvider.overview, isNotNull);
      expect(flowProvider.activeSessionId, isNull);
      expect(flowProvider.errorMessage, isNull);
    });

    test('10. AppStateProvider logout cleanly clears all user state from memory', () async {
      final appState = AppStateProvider();
      const user = AuthUser(
        id: 'user-cleanup-10',
        email: 'cleanup@flowstate.app',
        name: 'Cleanup',
        onboardingCompleted: true,
      );

      await appState.onUserAuthenticated(user);
      await appState.addTask(
        title: 'Task To Clear',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'General',
      );
      appState.setPreferredActiveTask(appState.tasks.first.id);

      expect(appState.tasks, isNotEmpty);
      expect(appState.preferredActiveTaskId, isNotNull);

      // Execute logout
      await appState.logout();

      expect(appState.currentUser, isNull);
      expect(appState.tasks, isEmpty);
      expect(appState.schedule, isEmpty);
      expect(appState.todaySnapshot, isNull);
      expect(appState.preferredActiveTaskId, isNull);
      expect(appState.deferredTaskIds, isEmpty);
      expect(appState.onboardingComplete, isFalse);
    });
  });
}
