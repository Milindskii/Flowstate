import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/models/onboarding_question.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/legal/legal_constants.dart';
import 'package:flowstate/screens/legal/legal_widgets.dart';
import 'package:flowstate/screens/legal/privacy_policy_screen.dart';
import 'package:flowstate/screens/legal/terms_of_service_screen.dart';
import 'package:flowstate/screens/onboarding_flow_screen.dart';
import 'package:flowstate/services/flow_clock.dart';

String _flatten(List<LegalSection> sections) => sections
    .expand((s) => [s.title, ...s.blocks.expand((b) => [if (b.text != null) b.text!, ...?b.bullets])])
    .join('\n');

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => FlowClock().stopTimer());

  group('Terms and Privacy copy', () {
    final terms = _flatten(TermsOfServiceScreen.sections);
    final privacy = _flatten(PrivacyPolicyScreen.sections);

    test('minimum age is 18 everywhere and no other age is claimed', () {
      expect(kMinimumAge, 18);
      for (final doc in [terms, privacy]) {
        expect(doc, contains('$kMinimumAge'));
        expect(doc, isNot(contains('16')));
        expect(doc, isNot(contains('13')));
        expect(doc, isNot(contains('parental')));
      }
    });

    test('no Google Play availability claims', () {
      for (final doc in [terms, privacy]) {
        expect(doc.toLowerCase(), isNot(contains('google play')));
        expect(doc.toLowerCase(), isNot(contains('play store')));
      }
    });

    test('Privacy Policy still discloses external AI processing and names the provider', () {
      expect(privacy, contains('Gemini'));
      expect(privacy.toLowerCase(), contains('external ai service'));
    });

    test('Privacy Policy makes no unverified retention, encryption or training promises', () {
      final lower = privacy.toLowerCase();
      expect(lower, isNot(contains('encrypt')));
      expect(lower, isNot(contains('not used to train')));
      expect(lower, isNot(contains('ephemeral')));
      expect(lower, isNot(contains('complete personal data archive')));
    });
  });

  group('Build My Day privacy notice', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('gate names no provider, links to the policy, and Cancel returns false', (tester) async {
      bool? result;
      await tester.pumpWidget(host(Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await checkAndShowGeminiPrivacyDisclosure(context),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('How Build My Day uses your notes'), findsOneWidget);
      expect(find.textContaining('Gemini'), findsNothing);
      expect(find.textContaining('Google'), findsNothing);
      expect(find.byKey(const Key('privacy_policy_link')), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kGeminiPrivacyAcceptedKey), isNot(true), reason: 'cancel must not record acceptance');
    });

    testWidgets('policy link opens the Privacy Policy', (tester) async {
      await tester.pumpWidget(host(Builder(
        builder: (context) => TextButton(onPressed: () => showBuildMyDayPrivacyInfo(context), child: const Text('open')),
      )));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy_done_button')), findsOneWidget);
      await tester.tap(find.byKey(const Key('privacy_policy_link')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });

    testWidgets('renders in dark theme without overflow', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(body: BuildMyDayPrivacySheet(requireChoice: true)),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Legal documents render in both themes', () {
    for (final dark in [false, true]) {
      testWidgets('Terms and Privacy ${dark ? 'dark' : 'light'}', (tester) async {
        for (final screen in <Widget>[const TermsOfServiceScreen(), const PrivacyPolicyScreen()]) {
          await tester.pumpWidget(MaterialApp(theme: dark ? ThemeData.dark() : ThemeData.light(), home: screen));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('Last updated: $kLegalLastUpdated'), findsOneWidget);
        }
      });
    }
  });

  group('Questionnaire is unchanged', () {
    test('12 core questions, 2 adaptive follow-ups, same ids in the same order', () {
      final all = OnboardingQuestionSet.getCoreQuestions();
      expect(all.where((q) => !q.isAdaptiveFollowUp).length, 12);
      expect(all.where((q) => q.isAdaptiveFollowUp).length, 2);
      expect(all.map((q) => q.id).toList(), [
        'peak_window',
        'wake_weekday',
        'wake_weekend',
        'schedule_shift_adaptation',
        'sleep_time',
        'sleep_inertia',
        'draining_work',
        'tired_reaction',
        'session_disruptor',
        'focus_duration',
        'primary_goal',
        'energy_predictability',
        'unpredictable_cue',
        'schedule_disruptors',
      ]);
    });

    test('answer ids are unchanged', () {
      Map<String, List<String>> ids() => {
            for (final q in OnboardingQuestionSet.getCoreQuestions()) q.id: q.options.map((o) => o.id).toList(),
          };
      final m = ids();
      expect(m['peak_window'], ['morning', 'midday', 'afternoon', 'evening']);
      expect(m['sleep_inertia'], ['almost_immediately', '15_30_min', '30_60_min', '1_2_hours', 'more_than_2_hours']);
      expect(m['draining_work'],
          ['coding', 'studying', 'problem_solving', 'writing', 'creative', 'meetings', 'admin', 'planning']);
      expect(m['tired_reaction'],
          ['distracted', 'procrastinate', 'slower', 'mistakes', 'switch_tasks', 'can_still_work']);
      expect(m['session_disruptor'], [
        'phone', 'social_media', 'noise', 'interruptions', 'racing_thoughts', 'too_little_time',
        'too_difficult', 'dont_know_where_to_start', 'other'
      ]);
      expect(m['focus_duration'], ['15_25_min', '25_40_min', '40_60_min', '60_90_min', '90_plus_min', 'depends']);
      expect(m['primary_goal'],
          ['start_difficult', 'stop_procrastinating', 'plan_my_day', 'stay_focused', 'use_energy_better', 'finish_on_time']);
      expect(m['energy_predictability'],
          ['very_predictable', 'mostly_predictable', 'changes_a_lot', 'completely_unpredictable']);
      expect(m['schedule_disruptors'],
          ['college', 'work_shifts', 'commute', 'gym_sports', 'family', 'irregular_sleep', 'nothing_major']);
    });
  });

  group('Questionnaire screen', () {
    Widget app() => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => AppStateProvider()),
            ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ],
          child: const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: Size(400, 800), disableAnimations: true),
              child: OnboardingFlowScreen(),
            ),
          ),
        );

    testWidgets('welcome explains personalization, makes no "stored locally" claim, and links to the policy',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.textContaining('stored locally'), findsNothing);
      await tester.tap(find.byKey(const Key('onboarding_privacy_link')));
      await tester.pumpAndSettle();
      expect(find.textContaining('personalize your plan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('onboarding_privacy_policy_button')));
      await tester.pumpAndSettle();
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    });

    testWidgets('each question shows progress and a why-we-ask line', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Begin'));
      await tester.pumpAndSettle();
      // Default answers (07:00 vs 08:30 wake) trigger the schedule-shift follow-up, so 12 core + 1 = 13 pages.
      expect(find.text('Question 1 of 13'), findsOneWidget);
      expect(find.byKey(const Key('why_peak_window')), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 13'), findsOneWidget);
    });
  });
}
