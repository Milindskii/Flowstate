import 'package:flutter/material.dart';
import 'legal_constants.dart';
import 'legal_widgets.dart';

/// Terms of Service. Plain-language, written against what Flowstate actually does today.
/// Age eligibility is read from [kMinimumAge] so it cannot drift from the Privacy Policy or sign-up screen.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  static const List<LegalSection> sections = [
    LegalSection('1. About Flowstate', [
      LegalBlock.paragraph(
        'Flowstate is a day-planning and focus app. You add tasks, turn rough notes into a plan with Build My Day, '
        'see your day on a calendar, track routines, and build a streak with Noya, your companion.',
      ),
      LegalBlock.paragraph(
        'Flowstate is operated by an independent developer, not an incorporated company. Contact details are in section 11.',
      ),
    ]),
    LegalSection('2. Who can use Flowstate', [
      LegalBlock.paragraph(
        'You must be at least $kMinimumAge years old to create an account. When you sign up, you confirm that you meet this requirement.',
      ),
      LegalBlock.paragraph(
        'If we learn that an account belongs to someone under $kMinimumAge, we may close it and delete its data.',
      ),
    ]),
    LegalSection('3. Your account', [
      LegalBlock.list([
        'Sign up with a valid email address and keep your login details to yourself.',
        'You are responsible for activity under your account. Tell us if you think it has been accessed without your permission.',
        'You can pause your account (deactivate) or permanently delete it from Profile > Legal & Privacy Hub.',
      ]),
    ]),
    LegalSection('4. Planning suggestions and AI assistance', [
      LegalBlock.paragraph(
        'Flowstate suggests when to do things based on your answers, your tasks and your past activity. These are suggestions, '
        'not guarantees. You decide what to do and when, and you can change any plan.',
      ),
      LegalBlock.paragraph(
        'Build My Day can use AI to turn your notes into structured tasks. AI output can be wrong or incomplete, so check each plan '
        'before you confirm it. Your tasks are only added after you confirm them. What is shared when you use it is explained in the '
        'Privacy Policy.',
      ),
      LegalBlock.paragraph(
        'Please do not rely on Flowstate for deadlines or commitments where a missed or mistimed reminder could cause serious harm.',
      ),
    ]),
    LegalSection('5. Not medical advice', [
      LegalBlock.paragraph(
        'Flowstate is a productivity tool. It is not a medical device and does not diagnose, treat or give advice about sleep disorders, '
        'mental health or any medical condition. Questions about sleep, energy and focus are used only to tune your schedule.',
      ),
    ]),
    LegalSection('6. Shields, points and your companion', [
      LegalBlock.paragraph(
        'Flow Points, Shields, streaks and Noya are in-app features. They have no cash value, cannot be sold or transferred, and '
        'may be adjusted if we change how the app works or to correct errors.',
      ),
      LegalBlock.paragraph(
        'Some features may be offered as optional purchases, such as a Pro subscription or Shield packs. Where offered, the price and '
        'terms are shown before you buy, payment is handled by your app store, and the store\'s own billing and refund rules apply. '
        'Availability can change over time.',
      ),
    ]),
    LegalSection('7. Acceptable use', [
      LegalBlock.paragraph('Please do not:'),
      LegalBlock.list([
        'use bots, scripts or other automation to earn points, Shields or progress;',
        'try to bypass limits, security measures or billing checks, or interfere with the service;',
        'reverse engineer the app or its servers, or probe them for weaknesses;',
        'use the service to break the law or to harm others.',
      ]),
    ]),
    LegalSection('8. Third-party services', [
      LegalBlock.paragraph(
        'Flowstate relies on outside providers for sign-in and hosting, for AI-assisted planning, and, where you buy something, for payments. '
        'Their own terms and privacy practices also apply to what they handle. The Privacy Policy lists what is shared with them.',
      ),
    ]),
    LegalSection('9. Availability and changes', [
      LegalBlock.paragraph(
        'We work to keep Flowstate running, but it is provided "as is" and may sometimes be unavailable, slow or contain errors. '
        'We may change or remove features, and may announce significant changes inside the app.',
      ),
    ]),
    LegalSection('10. Responsibility', [
      LegalBlock.paragraph(
        'To the extent the law allows, Flowstate is not responsible for losses that come from relying on its suggestions, from missed '
        'or delayed reminders, or from interruptions to the service. Nothing in these Terms limits any right you have under law '
        'that cannot be limited by agreement.',
      ),
    ]),
    LegalSection('11. Contact', [
      LegalBlock.paragraph(
        'Developer: Milind Krishnan, independent developer, Chennai, Tamil Nadu, India.\n'
        'Questions, privacy requests and support: $kLegalContactEmail',
      ),
    ]),
    LegalSection('12. Updates to these Terms', [
      LegalBlock.paragraph(
        'We may update these Terms as Flowstate changes. The "Last updated" date above shows the current version. '
        'For significant changes we may also show a notice in the app. Continuing to use Flowstate after an update means you accept the updated Terms.',
      ),
      LegalBlock.paragraph(
        'These Terms are a plain-language summary of how Flowstate works and have not been reviewed by a lawyer.',
      ),
    ]),
  ];

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      appBarTitle: 'Terms of Service',
      headline: 'Terms of Service',
      updatedLabel: 'Last updated: $kLegalLastUpdated',
      intro: 'These are the ground rules for using Flowstate. By creating an account or using the app, you agree to them.',
      sections: sections,
    );
  }
}
