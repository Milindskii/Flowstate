import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';

/// Screen displaying the formal Terms of Service.
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);
    final pageMargin = FlowSpacing.pageMargin(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        title: Text(
          'Terms of Service',
          style: FlowTypography.titleMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: cardBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          tooltip: 'Back',
          onPressed: () {
            FlowHaptics.lightTap();
            Navigator.of(context).pop();
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: borderColor, height: 1.0),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FlowRadii.badge),
                ),
                child: Text(
                  'Last Revised: September 2026',
                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Terms of Service',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Please read these Terms of Service carefully before using Flowstate. By accessing or using our application, you agree to be bound by these terms.',
                style: FlowTypography.bodyMedium(color: textSecondary),
              ),
              const SizedBox(height: 24),

              // Non-medical alert box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: FlowColors.accentAmber.withValues(alpha: 0.1),
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: FlowColors.accentAmber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: FlowColors.accentAmber, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Important Non-Medical Disclaimer',
                            style: FlowTypography.titleSmall(color: FlowColors.accentAmber).copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Flowstate is an organizational productivity tool based on personal focus blocks and circadian rhythms. Flowstate is NOT a medical device and does not provide clinical diagnosis, medical advice, therapy, or treatment for sleep disorders or mental health conditions.',
                            style: FlowTypography.bodySmall(color: textPrimary).copyWith(height: 1.45),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              _buildTermsSection(
                context,
                title: '1. Account Registration & Age Requirement',
                content:
                    'To use Flowstate, you must register with a valid email. Flowstate is configured exclusively for adult users (18 years of age and older) for initial launch as a founder decision to eliminate processing of minor data for V1 release. You are responsible for safeguarding your credentials.',
              ),

              _buildTermsSection(
                context,
                title: '2. Progression & 100% Free Economy Guarantee',
                content:
                    'All progression mechanics in Flowstate—including companion stages (Noya), Flow Points, focus soundscapes, and Flow Shields—are earned solely through authentic focus sessions and discipline. Flow Points are in-app virtual badges with zero real-world currency value and cannot be sold, exchanged, or purchased with real money.',
              ),

              _buildTermsSection(
                context,
                title: '3. Acceptable Use Policy',
                content:
                    'You agree not to:\n'
                    '• Attempt to farm points or progression using automated bots or headless scripts.\n'
                    '• Reverse engineer or decompile the application client or backend APIs.\n'
                    '• Interfere with server rate limiters or security mechanisms.',
              ),

              _buildTermsSection(
                context,
                title: '4. Account Termination & Data Erasure',
                content:
                    'You may delete your account and all associated data at any time from within the app (Profile > Legal Hub > Delete Account) or online via our dedicated web deletion request page prior to store release. Upon processing, your account and all associated data are permanently expunged from our database.',
              ),

              _buildTermsSection(
                context,
                title: '5. Developer Identity & Contact',
                content:
                    'Developer: Milind Krishnan, Independent Developer\n'
                    'Location: Chennai, Tamil Nadu, India\n'
                    'Entity Status: Solo / Independent Developer project (not an incorporated company or registered entity).\n'
                    'Support & Privacy Contact: Milindkrishnan24@gmail.com',
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTermsSection(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: FlowTypography.bodyMedium(color: textSecondary).copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}
