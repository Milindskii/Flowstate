import 'package:flutter/material.dart';
import 'legal_constants.dart';
import 'legal_widgets.dart';

/// Privacy & Data Policy. Every category below was checked against the app and server code; anything that
/// could not be confirmed is left out here and tracked as an open decision in docs/legal/open-decisions.md.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const List<LegalSection> sections = [
    LegalSection('1. What we collect and why', [
      LegalBlock.paragraph('Flowstate only handles the information below. Nothing else is collected.'),
      LegalBlock.list([
        'Account: your email address, and a display name if you set one. Needed to sign in and keep your plan across devices. Required. Sign-in is handled by Supabase.',
        'Your agreement: that you accepted the Terms and Privacy Policy and confirmed you are $kMinimumAge or older, with the time you did so. Needed to open an account. Required.',
        'Setup questions: your answers about when you feel most focused, wake-up times on weekdays and weekends, bedtime, how long you take to feel awake, which kinds of work drain you, what happens when you are tired, what disrupts you, how long you focus before a break, your main goal, how predictable your energy is, how your routine adapts on days with big schedule shifts (asked only when relevant), and your device time zone. Used to tune when tasks are scheduled. Part of setup. Two follow-up answers (what predicts a good day, what changes your schedule) stay on your device.',
        'Tasks and schedule: task titles, categories, durations, deadlines, fixed times, priority, routines, and what you complete, skip, move or miss. Needed to plan and show your day, calendar and insights. Required to use the planner.',
        'Optional reflections: focus, energy, difficulty and distraction ratings you give after a task. Used to improve your suggestions over time. Optional.',
        'Progress and purchases: Flow Points, Shields, streak and Noya progress, and, if you subscribe or buy something, its status and the store order reference. We never see your card or payment details; the app store handles payment.',
        'Settings: your accent colour and display preferences.',
        'Privacy requests: if you send us one, your email address and message.',
        'Technical data: request identifiers, error codes, timing, and rate-limit counters that help us keep the service secure and working.',
      ]),
      LegalBlock.paragraph(
        'Flowstate does not collect your location, contacts, photos or health-sensor data. The app does not include advertising or '
        'third-party analytics or crash-reporting tools. Reminders, if you turn them on, are created on your device.',
      ),
    ]),
    LegalSection('2. Build My Day and AI processing', [
      LegalBlock.paragraph(
        'Build My Day turns your notes into a plan. Simple lists can be organized on your device. When your notes need more '
        'interpretation, they are sent to Flowstate\'s servers and, from there, to an external AI service: Google\'s Gemini API.',
      ),
      LegalBlock.list([
        'Sent: the text you typed, today\'s date and your time zone. Your email, name, password and sign-in token are not part of the request.',
        'When you adjust today\'s plan by typing a message, your message and the titles, times and durations of today\'s open tasks are also sent, so the request makes sense.',
        'Purpose: to extract structured tasks (titles, durations, deadlines, fixed times) for you to review. The AI does not build your schedule; Flowstate\'s own scheduling logic does, and nothing is added until you confirm.',
        'Stored by us: the structured result of the request and a one-way fingerprint (hash) of it that prevents duplicate charges. We do not keep a copy of your raw text in a separate record.',
        'Google processes the text under its own terms for the Gemini API, which also govern how long it keeps that text. Flowstate does not control Google\'s retention.',
        'Your choice: you are shown a short notice before your first AI request and can cancel without anything being sent. You can always add tasks manually or use the basic planner instead.',
      ]),
      LegalBlock.paragraph('Please avoid typing sensitive information (such as health details or passwords) into your notes.'),
    ]),
    LegalSection('3. Who else handles your data', [
      LegalBlock.list([
        'Supabase: sign-in and account authentication, and the database that stores your Flowstate data.',
        'Google (Gemini API): processes Build My Day text as described above.',
        'Your app store: processes payments and subscriptions if you buy anything, and tells us whether a purchase is valid.',
        'Our hosting provider: runs the Flowstate server that handles your requests.',
      ]),
      LegalBlock.paragraph('We do not sell your personal data and we do not share it for advertising.'),
    ]),
    LegalSection('4. Where data is kept', [
      LegalBlock.paragraph(
        'On your device: cached tasks, settings, setup progress and your sign-in session, so the app works smoothly. '
        'Signing out or deleting your account clears this.',
      ),
      LegalBlock.paragraph(
        'On our servers: the account, setup answers, tasks, history and progress described above, for as long as your account exists.',
      ),
    ]),
    LegalSection('5. Keeping and deleting your data', [
      LegalBlock.list([
        'Deactivate: pauses your account and keeps your data so you can come back by signing in again.',
        'Delete: in Profile > Legal & Privacy Hub, "Permanent Account & Data Deletion" permanently removes your account record and the data linked to it from Flowstate\'s database, including tasks, setup answers, history and progress. It cannot be undone.',
        'What deletion does not yet cover: your sign-in record at Supabase is not removed by the in-app button, and a privacy request you submitted is kept without a link to your account. Email us and we will handle these manually.',
        'We have not yet set fixed retention periods for server logs or backups.',
        'Text already sent to Google is subject to Google\'s own retention, not ours.',
      ]),
    ]),
    LegalSection('6. Your choices and rights', [
      LegalBlock.list([
        'See what we hold: Legal & Privacy Hub > "View My Stored Data".',
        'Export: Legal & Privacy Hub > "Data Portability & Export" copies a JSON summary (account, preferences, tasks, progress) to your clipboard. It does not yet include all history. Email us for anything else.',
        'Ask us to correct, delete or explain your data: use "Submit Grievance / Inquiry" in the Legal & Privacy Hub, or email us.',
        'Depending on where you live, the law may give you additional rights. We will respond as the law requires.',
      ]),
    ]),
    LegalSection('7. Security', [
      LegalBlock.paragraph(
        'You must be signed in to read or change your data, and each account can reach only its own records. '
        'No system is perfectly secure, so please use a strong, unique password.',
      ),
    ]),
    LegalSection('8. Age', [
      LegalBlock.paragraph(
        'Flowstate is for people who are $kMinimumAge or older. We do not knowingly create accounts for anyone younger. '
        'If you think a younger person has an account, email us and we will review and remove it.',
      ),
    ]),
    LegalSection('9. Changes to this policy', [
      LegalBlock.paragraph(
        'When this policy changes, we update the date at the top. For significant changes we may also show a notice in the app.',
      ),
    ]),
    LegalSection('10. Contact', [
      LegalBlock.paragraph(
        'Milind Krishnan, independent developer, Chennai, Tamil Nadu, India (not an incorporated company).\n'
        'Privacy questions and requests: $kLegalContactEmail\n'
        'This policy describes current practice and has not been reviewed by a lawyer.',
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      appBarTitle: 'Privacy & Data Policy',
      headline: 'Your data, plainly explained',
      updatedLabel: 'Last updated: $kLegalLastUpdated',
      intro:
          'Flowstate collects what it needs to plan your day. This page explains what that is, who handles it, and how you can control it.',
      afterIntro: LegalSummaryNote(
        text: 'In short: your account, setup answers and tasks are stored on Flowstate\'s servers. Build My Day text may also go to an '
            'external AI service to be turned into tasks. We don\'t sell your data, and you can export or delete it from Settings.',
        icon: Icons.lock_outline_rounded,
      ),
      sections: sections,
    );
  }
}
