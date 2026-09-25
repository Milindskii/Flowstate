import 'package:flutter/material.dart';
import '../../theme/flow_colors.dart';
import '../../theme/flow_haptics.dart';
import '../../theme/flow_radii.dart';
import '../../theme/flow_spacing.dart';
import '../../theme/flow_typography.dart';

/// Screen displaying the Cookie & Local Storage Policy.
class CookiePolicyScreen extends StatelessWidget {
  const CookiePolicyScreen({super.key});

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
          'Local Storage & Preferences',
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
                  'Zero Advertising Trackers Policy',
                  style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Mobile Storage & Preferences',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Flowstate operates as a native mobile application. We do not use browser tracking cookies inside the native app; all persistence relies on essential local mobile storage.',
                style: FlowTypography.bodyMedium(color: textSecondary),
              ),
              const SizedBox(height: 24),

              _buildPolicySection(
                context,
                title: '1. What Technologies We Use',
                content:
                    '• SharedPreferences / Local App Storage: Stores your local visual settings (Light/Dark mode, accent color, visual density) and offline cached tasks so the app operates with zero lag.\n'
                    '• Secure Session Tokens: Securely stores cryptographic JWT session tokens to keep you logged in between sessions without transmitting your password.',
              ),

              _buildPolicySection(
                context,
                title: '2. Strictly Zero Advertising Cookies',
                content:
                    'We do NOT use:\n'
                    '• Third-party advertising cookies (e.g. Google DoubleClick, Facebook Pixel).\n'
                    '• Cross-site tracking scripts or device fingerprinting.\n'
                    '• Marketing retargeting beacons.\n\n'
                    'Your activity inside Flowstate is never sold or shared with data brokers.',
              ),

              _buildPolicySection(
                context,
                title: '3. Managing Your Storage Preferences',
                content:
                    'Because all stored keys are strictly essential for app operation, disabling local storage would prevent the app from functioning. However, you can wipe all local storage anytime by signing out or tapping "Delete Account" in Profile & Settings.',
              ),

              _buildPolicySection(
                context,
                title: '4. Contact',
                content:
                    'Questions about our storage practices? Contact us:\n'
                    'Milindkrishnan24@gmail.com',
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
