import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Modal dialog for user-confirmed streak shield recovery and information.
/// Flowstate shields are 100% free, earned strictly through 7-day streaks,
/// and never auto-consumed or sold for real money.
class ShieldRecoveryDialog extends StatefulWidget {
  const ShieldRecoveryDialog({super.key});

  static Future<void> show(BuildContext context) {
    FlowHaptics.lightTap();
    return showDialog(
      context: context,
      builder: (_) => const ShieldRecoveryDialog(),
    );
  }

  @override
  State<ShieldRecoveryDialog> createState() => _ShieldRecoveryDialogState();
}

class _ShieldRecoveryDialogState extends State<ShieldRecoveryDialog> {
  bool _isUsing = false;

  Future<void> _handleActivateShield(FlowProvider flow, int streak) async {
    setState(() => _isUsing = true);
    final success = await flow.useStreakShield();
    if (!mounted) return;
    setState(() => _isUsing = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? 'Streak shield activated! Your $streak-day streak is preserved.'
            : 'Could not activate shield. Please try again.'),
        backgroundColor: success ? FlowColors.positive : FlowColors.accentAmber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flow = Provider.of<FlowProvider>(context);
    final profile = flow.overview.profile;
    final shieldsCount = profile.shieldsAvailable;
    final streak = profile.currentStreak;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon Header
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: FlowColors.accentCyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_outlined,
              color: FlowColors.accentCyan,
              size: 30,
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Streak Shields',
            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),

          Text(
            'Current Streak: $streak days\nAvailable Shields: $shieldsCount / 3',
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Explanatory container
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? FlowColors.darkCard : FlowColors.lightCardElevated,
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(
                color: isDark ? FlowColors.darkBorder : FlowColors.lightBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_outlined, size: 16, color: FlowColors.positive),
                    const SizedBox(width: 8),
                    Text(
                      '100% Free Progression',
                      style: FlowTypography.labelMedium(color: FlowColors.positive).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Shields are earned exclusively by completing 7 consecutive qualifying focus days. Shields are never auto-consumed—you decide when to activate one.',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          if (shieldsCount > 0) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isUsing ? null : () => _handleActivateShield(flow, streak),
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.accentCyan,
                  foregroundColor: FlowColors.textInverse,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: _isUsing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: FlowColors.textInverse),
                      )
                    : const Text(
                        'Activate 1 Shield',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Keep Shield For Later',
                style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)),
              ),
            ),
          ] else ...[
            Text(
              'No shields available yet. Build a 7-day focus streak to forge your next shield!',
              style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: FlowColors.border(context)),
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: Text('Close', style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(context))),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
