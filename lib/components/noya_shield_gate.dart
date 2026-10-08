import 'package:flutter/material.dart';

import '../models/ai_plan_models.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';
import 'noya_motion_view.dart';

/// "1d 14h", "5h 20m", "12m", "under a minute": how long until the next free Shield, in the fewest useful words.
String formatShieldWait(Duration d) {
  if (d.inMinutes < 1) return 'under a minute';
  final days = d.inDays;
  final hours = d.inHours % 24;
  final minutes = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '${days}d ${hours}h' : '${days}d';
  if (d.inHours > 0) return minutes > 0 ? '${d.inHours}h ${minutes}m' : '${d.inHours}h';
  return '${d.inMinutes}m';
}

/// Noya explains, in place, that a genuinely AI-powered action needs Shields the account does not have: what needs
/// them, how many, the current balance, when the next free one lands, and how to earn more.
///
/// It is shown ONLY for an AI action. Everything deterministic in the planner (create, edit, reschedule, routines,
/// complete, skip, delete) works with zero Shields and never reaches this widget.
class NoyaShieldGate extends StatelessWidget {
  /// The server's view of the account (balance, price, cooldown). Never invented client-side.
  final AIUsageStatus status;

  /// What the Shields would have paid for, e.g. "An AI plan".
  final String action;

  /// "Earn a Shield": opens the place Shields are earned (Flow Hub). Null hides the button.
  final VoidCallback? onEarn;

  /// "Maybe later": dismisses the gate and keeps what the user typed.
  final VoidCallback onLater;

  /// Optional deterministic route ("Plan it myself") so a user with no Shields is never stuck.
  final VoidCallback? onManual;
  final String manualLabel;

  /// The clock the countdown runs against (injectable for tests).
  final DateTime Function() clock;

  const NoyaShieldGate({
    super.key,
    required this.status,
    this.action = 'An AI plan',
    this.onEarn,
    required this.onLater,
    this.onManual,
    this.manualLabel = 'Plan it myself',
    this.clock = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    final cost = status.shieldCost;
    final have = status.shieldsAvailable;
    final wait = status.untilNextShieldAt(clock());
    const accent = FlowColors.accentCyan;
    final muted = FlowColors.textMutedOf(context);

    final headline = have <= 0 ? "You're out of Shields." : "You don't have enough Shields.";
    final refill = wait == null
        ? "You're at the Shield limit."
        : wait == Duration.zero
            ? 'Your next free Shield is ready.'
            : 'Your next free Shield is available in ${formatShieldWait(wait)}.';

    return Container(
      key: const Key('noya_shield_gate'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Semantics(
            label: 'Noya',
            child: const NoyaMotionView(mood: NoyaMood.asleep, pose: NoyaState.sleepy, size: 44, showAmbientGlow: true),
          ),
          const SizedBox(height: 6),
          Text('Noya 🦊', style: FlowTypography.labelMedium(color: accent).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            headline,
            key: const Key('shield_gate_headline'),
            textAlign: TextAlign.center,
            style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '$action needs $cost Shields. You have $have.',
            key: const Key('shield_gate_balance'),
            textAlign: TextAlign.center,
            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 2),
          Text(
            refill,
            key: const Key('shield_gate_refill'),
            textAlign: TextAlign.center,
            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 6),
          Text(
            'Earn Shields with a 7-day streak or by finishing your weekly quest.',
            key: const Key('shield_gate_ways'),
            textAlign: TextAlign.center,
            style: FlowTypography.labelSmall(color: muted),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              if (onEarn != null)
                FilledButton(
                  key: const Key('shield_gate_earn'),
                  onPressed: onEarn,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 44),
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.pillRadius),
                  ),
                  child: const Text('Earn a Shield'),
                ),
              OutlinedButton(
                key: const Key('shield_gate_later'),
                onPressed: onLater,
                style: OutlinedButton.styleFrom(
                  foregroundColor: FlowColors.textPrimaryOf(context),
                  side: BorderSide(color: FlowColors.border(context)),
                  minimumSize: const Size(48, 44),
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.pillRadius),
                ),
                child: const Text('Maybe later'),
              ),
              if (onManual != null)
                TextButton(
                  key: const Key('use_basic_planner_button'),
                  onPressed: onManual,
                  child: Text(manualLabel),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
