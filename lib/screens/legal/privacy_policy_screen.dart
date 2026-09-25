import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';

/// Screen displaying the authoritative Data Practices, AI Disclosures & User Rights Policy.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          'Privacy & Data Policy',
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
              // Notice Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FlowRadii.badge),
                ),
                child: Text(
                  'Data Practices & User Rights Notice · Effective: September 2026',
                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),

              // Legal Review Disclaimer Callout
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FlowColors.surface(context),
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18, color: FlowColors.accentCyan),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This privacy policy outlines our data practices, third-party AI integrations, and user rights. Note: Formal legal review by qualified counsel in your jurisdiction is required before claiming official compliance with regional frameworks.',
                        style: FlowTypography.bodySmall(color: textSecondary).copyWith(height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Your Data Belongs to You.',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'At Flowstate, privacy and data minimization are core design principles. We believe personal productivity data should be private, secure, and under your direct control.',
                style: FlowTypography.bodyMedium(color: textSecondary),
              ),
              const SizedBox(height: 24),

              _buildPolicySection(
                context,
                title: '1. What We Collect',
                content:
                    '• Account Credentials: Your email address and optional display name for authentication.\n'
                    '• Rhythm & Scheduling Preferences: Self-reported sleep hours, wake times, and energy peak windows to generate local scheduling suggestions.\n'
                    '• Tasks & Focus History: Task titles, categories, estimated durations, and completed focus session durations.\n'
                    '• Subjective Reflections: Optional qualitative ratings (e.g. Focused, Steady, Distracted) self-reported after focus sessions to calibrate personal productivity recommendations.',
              ),

              _buildPolicySection(
                context,
                title: '2. Subjective Productivity Data vs. Clinical Health Data',
                content:
                    'Flowstate collects self-reported subjective indicators (such as focus reflection, perceived energy levels, and task difficulty) solely for personal task prioritization and companion progression.\n\n'
                    '• Flowstate does NOT collect clinical or physiological biomarkers (e.g., heart rate, cortisol levels, EEG, or medical records).\n'
                    '• Flowstate is NOT a medical device and does not provide clinical diagnosis, psychiatric advice, therapy, or treatment for medical conditions.',
              ),

              _buildPolicySection(
                context,
                title: '3. AI Task Parsing & Google Gemini Disclosures (Google Play 2026)',
                content:
                    'Flowstate includes an optional AI Task Planning ("Brain Dump") feature powered by Google Gemini:\n\n'
                    '• What Data is Sent: When you submit notes through the Brain Dump input, the raw text of your task notes, along with your local timezone and current date, is transmitted securely to our FastAPI backend, which interfaces with Google Gemini (Google Generative Language API) solely for task understanding.\n'
                    '• Context Minimization: We enforce strict context minimization. We NEVER send passwords, authentication tokens, payment details, or unrelated personal profile records to Gemini.\n'
                    '• Purpose: Extracting structured task metadata (title, duration, priority, difficulty, deadline, and explicit fixed times) for your review and confirmation.\n'
                    '• Deterministic Scheduling: Gemini does NOT generate your calendar or final schedule. The local Flowstate deterministic scheduling engine remains the sole authority for arranging your day.\n'
                    '• Retention & Training: Task prompts sent via enterprise API are processed ephemerally and are not used to train Google public AI models.\n'
                    '• User Control: AI planning is 100% optional. You can manually create, schedule, and categorize all tasks without ever invoking natural language or AI services.',
              ),

              _buildPolicySection(
                context,
                title: '4. Third-Party Services & Data Security',
                content:
                    'We do not bundle third-party advertising SDKs, cross-app tracking libraries, or data-broker frameworks (zero AdMob, zero Meta Audience Network, zero Adjust/AppsFlyer).\n\n'
                    'HTTPS/TLS is required for production network traffic; exact TLS configuration depends on deployed hosting infrastructure and will be verified before production launch. Persistent database storage enforces isolated user partitions with strict user-level authorization.',
              ),

              _buildPolicySection(
                context,
                title: '5. Age Policy & Child Data Handling',
                content:
                    'Launch Policy (Founder Decision): Flowstate is configured exclusively for adult users (18 years of age and older) for its initial release as a risk-reduction product decision.\n\n'
                    'Under the India Digital Personal Data Protection Act, 2023, an individual under 18 is classified as a child. Flowstate does not knowingly process personal data of individuals under 18 years of age during V1 launch. Support for younger users is deferred to future releases pending verifiable parental-consent architecture and legal review.\n\n'
                    'If you believe a minor under 18 has registered an account, contact Milindkrishnan24@gmail.com for prompt verification and account erasure.',
              ),

              _buildPolicySection(
                context,
                title: '6. User Rights: Data Portability & Account Erasure',
                content:
                    'We provide functional tools supporting data access, portability, and erasure rights:\n\n'
                    '• Data Portability & Access: You can download your complete personal data archive in structured JSON format anytime from Settings > Legal & Compliance Hub.\n'
                    '• In-App Account Deletion: You can permanently erase your account, tasks, rhythm calibrations, and companion progression directly inside the app (Profile > Legal Hub > Permanent Account & Data Deletion).\n'
                    '• External Web Deletion Route: In accordance with Google Play requirements, a dedicated web-based deletion request page will be hosted and linked prior to production store launch without requiring the mobile app.',
              ),

              _buildPolicySection(
                context,
                title: '7. Developer Identity & Grievance Contact',
                content:
                    'Developer: Milind Krishnan, Independent Developer\n'
                    'Location: Chennai, Tamil Nadu, India\n'
                    'Status: Solo / Independent Developer project (not an incorporated company or registered entity)\n'
                    'Privacy, Support & Grievance Contact: Milindkrishnan24@gmail.com\n'
                    'SDF Status: No current notification/designation as a Significant Data Fiduciary has been identified.',
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPolicySection(
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
