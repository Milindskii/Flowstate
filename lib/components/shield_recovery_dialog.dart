import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_notice.dart';
import 'noya_shield_gate.dart' show formatShieldWait;

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
  bool _activated = false;

  Future<void> _handleActivateShield(FlowProvider flow, int streak) async {
    if (_isUsing || _activated) return; // a repeated tap never sends a second request
    setState(() => _isUsing = true);
    final success = await flow.useStreakShield();
    if (!mounted) return;
    setState(() {
      _isUsing = false;
      _activated = success;
    });
    if (success) {
      NoyaNoticeCenter.instance.success(
          streak > 0 ? 'Your $streak-day streak is protected today.' : 'Your streak is protected today.',
          title: 'Shield activated 🛡️');
      Navigator.of(context).pop();
    } else {
      NoyaNoticeCenter.instance.failure(flow.overview.profile.shieldActiveToday
          ? 'Your Shield is already active today.'
          : "Couldn't activate a Shield. Try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = Provider.of<FlowProvider>(context);
    final profile = flow.overview.profile;
    final shieldsCount = profile.shieldsAvailable;
    final streak = profile.currentStreak;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeToday = profile.shieldActiveToday || _activated;
    final wait = profile.untilNextShieldAt(DateTime.now());

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
            '🛡️ $shieldsCount / ${profile.shieldMax} Shields',
            key: const Key('shield_dialog_balance'),
            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          // The countdown is the server's clock (see FlowProfile.untilNextShieldAt): the device clock cannot move it.
          Text(
            wait == null
                ? (shieldsCount >= profile.shieldMax ? 'You have the most Shields you can hold' : 'Current streak: $streak days')
                : (wait == Duration.zero ? 'Next Shield arriving now' : 'Next Shield in ${formatShieldWait(wait)}'),
            key: const Key('shield_dialog_next'),
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Explanatory container
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? FlowColors.surfaceDark : FlowColors.lightCardElevated,
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(
                color: isDark ? FlowColors.borderDark : FlowColors.lightBorder,
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
                  'Earn Shields with a 7-day focus streak or your weekly quest, and Flowstate adds one free every 3 days while you are below the limit. Shields protect your streak and pay for AI planning; they are never used without your say-so.',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Action Buttons
          if (activeToday) ...[
            Container(
              key: const Key('shield_active_today'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: FlowColors.positive.withValues(alpha: 0.12),
                borderRadius: FlowRadii.buttonRadius,
              ),
              child: Text(
                '✓ Shield active today',
                textAlign: TextAlign.center,
                style: FlowTypography.labelLarge(color: FlowColors.positive).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context))),
            ),
          ] else if (shieldsCount > 0) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                key: const Key('shield_activate_button'),
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
              wait == null
                  ? 'No Shields right now. Build a 7-day focus streak or finish your weekly quest to earn one.'
                  : 'No Shields right now. Your next free one arrives in ${formatShieldWait(wait)}.',
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
