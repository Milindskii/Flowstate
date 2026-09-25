import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';

/// Screen displaying the Refund Policy and No-Hidden-Fees Guarantee.
class RefundPolicyScreen extends StatelessWidget {
  const RefundPolicyScreen({super.key});

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
          'Refund Policy',
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
                  '100% Free Progression Guarantee',
                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Zero Hidden Fees. Zero Pay-to-Win.',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Flowstate is designed to empower your natural focus rhythms, not exploit your attention or wallet with artificial scarcity or microtransactions.',
                style: FlowTypography.bodyMedium(color: textSecondary),
              ),
              const SizedBox(height: 24),

              _buildPolicySection(
                context,
                title: '1. In-App Progression & Virtual Items',
                content:
                    'All focus rewards in Flowstate—including Noya evolutions, companion animals (Otter, Owl, Capybara), ambient soundscapes, and Flow Shields—are earned solely through authentic focus sessions. We do not sell progression items, level skips, or shields for real money. You cannot be charged for using Flowstate\'s companion features.',
              ),

              _buildPolicySection(
                context,
                title: '2. 14-Day Full Refund Policy on Paid Tiers',
                content:
                    'Should Flowstate introduce any optional premium cloud or team workspace subscription in the future, we offer an unconditional 14-day money-back guarantee.\n\n'
                    'If you are dissatisfied with any optional paid service for any reason within 14 days of purchase, email Milindkrishnan24@gmail.com for a 100% full refund with zero questions asked.',
              ),

              _buildPolicySection(
                context,
                title: '3. How to Request a Refund',
                content:
                    'To initiate a refund:\n'
                    '1. Send an email to Milindkrishnan24@gmail.com from your registered account email.\n'
                    '2. State your order number or account email.\n'
                    '3. Refunds are processed back to your original payment method within 3–5 business days.',
              ),

              _buildPolicySection(
                context,
                title: '4. Billing & Contact Operations',
                content:
                    'Developer: Milind Krishnan, Independent Developer\n'
                    'Location: Chennai, Tamil Nadu, India\n'
                    'Billing & Support: Milindkrishnan24@gmail.com\n'
                    'Entity Status: Solo / Independent Developer project (not an incorporated company or registered entity).',
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
