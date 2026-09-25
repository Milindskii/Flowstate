import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pricing_config.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Screen: Pro Subscription with Spotify-inspired premium simplicity.
/// Does NOT use fake prices or simulated purchases.
class ProSubscriptionScreen extends StatefulWidget {
  const ProSubscriptionScreen({super.key});

  @override
  State<ProSubscriptionScreen> createState() => _ProSubscriptionScreenState();
}

class _ProSubscriptionScreenState extends State<ProSubscriptionScreen> {
  int _selectedPlanIndex = 1; // Default to Yearly (Best Value)

  void _onContinuePressed(BuildContext context) {
    FlowHaptics.lightTap();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(ctx),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
        title: Text(
          'Google Play Billing',
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(ctx)).copyWith(fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Google Play manages your subscription.\n\nOfficial Play Store billing will activate upon production release. In development, prices are intentionally TBD to prevent unauthorized charges.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(ctx)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Understood',
              style: FlowTypography.labelLarge(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final accent = themeProvider.resolveAccent(context);
    final pageMargin = FlowSpacing.pageMargin(context);
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final textMuted = FlowColors.textMutedOf(context);
    final cardBg = FlowColors.surface(context);
    final borderColor = FlowColors.border(context);

    final plans = ProPlanConfig.defaultPlans;

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          tooltip: 'Back',
          onPressed: () {
            FlowHaptics.lightTap();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'GO PRO',
          style: FlowTypography.titleSmall(color: textPrimary).copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 12),
              // Pro Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(FlowRadii.badge),
                  border: Border.all(color: accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'FLOWSTATE PRO',
                      style: FlowTypography.labelSmall(color: accent).copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Headline
              Text(
                'Flowstate, without limits.',
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Sub-copy
              Text(
                'Plan your day.\nUnderstand your workload.\nGet more AI planning.',
                style: FlowTypography.bodyLarge(color: textSecondary).copyWith(
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),

              // Feature Highlights Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    _buildFeatureItem(context, 'More AI Brain Dumps', accent),
                    const SizedBox(height: 14),
                    _buildFeatureItem(context, 'Advanced personalization', accent),
                    const SizedBox(height: 14),
                    _buildFeatureItem(context, 'More planning flexibility', accent),
                    const SizedBox(height: 14),
                    _buildFeatureItem(context, 'Future Pro features', accent),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Plan Selectors: Monthly vs Yearly
              Row(
                children: [
                  for (int i = 0; i < plans.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: _buildPlanCard(
                        context,
                        plan: plans[i],
                        isSelected: _selectedPlanIndex == i,
                        accent: accent,
                        onTap: () {
                          FlowHaptics.selection();
                          setState(() => _selectedPlanIndex = i);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Primary CTA: Continue with Pro
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  key: const Key('pro_continue_button'),
                  onPressed: () => _onContinuePressed(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                  ),
                  child: Text(
                    'Continue with Pro',
                    style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Safe Disclaimers
              Text(
                'Cancel anytime.\nGoogle Play manages your subscription.',
                style: FlowTypography.labelSmall(color: textMuted).copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(BuildContext context, String text, Color accent) {
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, color: accent, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required ProPlanConfig plan,
    required bool isSelected,
    required Color accent,
    required VoidCallback onTap,
  }) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final borderColor = isSelected ? accent : FlowColors.border(context);
    final bg = isSelected ? accent.withValues(alpha: 0.08) : FlowColors.surface(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: FlowRadii.cardRadius,
          border: Border.all(color: borderColor, width: isSelected ? 2.0 : 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: [
                Text(
                  plan.title,
                  style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w800),
                ),
                if (plan.isBestValue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: FlowColors.accentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(FlowRadii.badge),
                    ),
                    child: Text(
                      'Best value',
                      style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                plan.displayPrice,
                style: FlowTypography.headlineMedium(color: textPrimary).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pricing coming soon',
              style: FlowTypography.labelSmall(color: textSecondary).copyWith(
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
