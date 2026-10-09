import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/shield_wallet.dart';
import '../providers/flow_provider.dart';
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';
import 'noya_notice.dart';
import 'noya_shield_gate.dart' show formatShieldWait;

FlowProvider? _maybeFlow(BuildContext context, {bool listen = true}) {
  try {
    return Provider.of<FlowProvider>(context, listen: listen);
  } catch (_) {
    return null; // screens pumped without the Flow layer (tests, previews) simply show no Shield UI
  }
}

String _shields(int n) => '$n ${n == 1 ? 'Shield' : 'Shields'}';

/// The account's Shield balance, exactly as the server last reported it. Tapping it opens Noya's Shield popup.
/// Renders nothing where the Flow layer is not provided.
class ShieldBalancePill extends StatelessWidget {
  const ShieldBalancePill({super.key});

  @override
  Widget build(BuildContext context) {
    final flow = _maybeFlow(context);
    if (flow == null || !flow.hasServerShieldBalance) return const SizedBox.shrink();
    final n = flow.shieldBalance;
    final empty = n <= 0;
    final color = empty ? FlowColors.textMutedOf(context) : FlowColors.accentCyan;
    return Semantics(
      button: true,
      label: '${_shields(n)}. Open Shields',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('shield_balance_pill'),
        borderRadius: FlowRadii.pillRadius,
        onTap: () {
          FlowHaptics.selection();
          ShieldWalletPopup.show(context);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32, minWidth: 44),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: FlowRadii.pillRadius,
              border: Border.all(color: color.withValues(alpha: 0.30)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 15, color: color),
                const SizedBox(width: 4),
                Text('$n',
                    key: const Key('shield_balance_value'),
                    style: FlowTypography.labelMedium(color: color).copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Noya's Shield popup: the balance and every way to get more. At zero it is the "out of Shields" popup — sleeping
/// Noya, the balance, watch rewarded ads, buy the ₹20 pack, or dismiss. Every number comes from the server wallet.
class ShieldWalletPopup extends StatefulWidget {
  /// Shown as an extra quiet action ("Earn free in Flow Hub"). Null hides it.
  final VoidCallback? onFlowHub;

  const ShieldWalletPopup({super.key, this.onFlowHub});

  static Future<void> show(BuildContext context, {VoidCallback? onFlowHub}) {
    final flow = _maybeFlow(context, listen: false);
    if (flow == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<FlowProvider>.value(
        value: flow,
        child: ShieldWalletPopup(onFlowHub: onFlowHub),
      ),
    );
  }

  @override
  State<ShieldWalletPopup> createState() => _ShieldWalletPopupState();
}

class _ShieldWalletPopupState extends State<ShieldWalletPopup> {
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeFlow(context, listen: false)?.loadWallet();
    });
  }

  Future<void> _run(Future<ShieldEarnOutcome> Function() action) async {
    if (_busy) return; // one request per tap: the provider also collapses repeats into one
    setState(() {
      _busy = true;
      _status = null;
    });
    final outcome = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = outcome.message;
    });
    if (outcome.status == ShieldEarnStatus.verified) {
      NoyaNoticeCenter.instance.success(outcome.message, title: 'Shields');
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = Provider.of<FlowProvider>(context);
    final wallet = flow.wallet;
    final balance = flow.shieldBalance;
    final empty = balance <= 0;
    final ads = wallet?.ads ?? const AdOffer();
    final pack = wallet?.pack ?? const PackOffer();
    final wait = wallet?.untilNextRefill;
    final muted = FlowColors.textMutedOf(context);
    const accent = FlowColors.accentCyan;

    return AlertDialog(
      key: const Key('shield_wallet_popup'),
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
      contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            NoyaCompanionView(state: empty ? NoyaState.sleepy : NoyaState.encouraging, size: 72, showAmbientGlow: true),
            const SizedBox(height: 10),
            Text(
              empty ? "Oh no, you're out of Shields!" : 'Your Shields',
              key: const Key('shield_popup_title'),
              textAlign: TextAlign.center,
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              empty ? '0 Shields' : 'You have ${_shields(balance)}.',
              key: const Key('shield_popup_balance'),
              textAlign: TextAlign.center,
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              empty
                  ? 'Shields are needed for AI-powered planning, like Build My Day and Replan.'
                  : (wallet != null
                      ? 'Build My Day ${_shields(wallet.costBuildMyDay)} · Replan ${_shields(wallet.costReplan)} · Streak restore ${_shields(wallet.costStreakRestore)}'
                      : 'Used for AI-powered planning and streak protection.'),
              key: const Key('shield_popup_explanation'),
              textAlign: TextAlign.center,
              style: FlowTypography.labelSmall(color: muted),
            ),
            if (wait != null && !empty) ...[
              const SizedBox(height: 2),
              Text(
                wait == Duration.zero ? 'A free Shield is ready.' : 'Next free Shield in ${formatShieldWait(wait)}.',
                key: const Key('shield_popup_refill'),
                textAlign: TextAlign.center,
                style: FlowTypography.labelSmall(color: muted),
              ),
            ],
            const SizedBox(height: 16),
            _OptionButton(
              key: const Key('shield_popup_watch_ads'),
              icon: Icons.play_circle_outline_rounded,
              title: 'Watch ${ads.adsPerReward} Ads',
              subtitle: ads.enabled
                  ? '${ads.progress}/${ads.adsPerReward} ads watched · earns ${_shields(ads.shieldsPerReward)}'
                  : 'Coming soon',
              enabled: ads.enabled && !_busy && ads.dailyRemaining > 0,
              onTap: () => _run(flow.watchRewardedAd),
            ),
            const SizedBox(height: 8),
            _OptionButton(
              key: const Key('shield_popup_buy_pack'),
              icon: Icons.shopping_bag_outlined,
              title: 'Get Shields for ${pack.priceDisplay}',
              subtitle: pack.enabled ? '${_shields(pack.units)} · One-time purchase' : 'Coming soon',
              enabled: pack.enabled && !_busy,
              onTap: () => _run(flow.buyShieldPack),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
            ],
            if (_status != null) ...[
              const SizedBox(height: 10),
              Text(_status!,
                  key: const Key('shield_popup_status'),
                  textAlign: TextAlign.center,
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
            ],
            const SizedBox(height: 6),
            if (widget.onFlowHub != null)
              TextButton(
                key: const Key('shield_popup_flow_hub'),
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onFlowHub!();
                },
                child: const Text('Earn free in Flow Hub'),
              ),
            TextButton(
              key: const Key('shield_popup_dismiss'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(empty ? 'Not Now' : 'Dismiss',
                  style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context))),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _OptionButton({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? FlowColors.textPrimaryOf(context) : FlowColors.textMutedOf(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: enabled ? onTap : null,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: FlowRadii.cardRadius,
              border: Border.all(
                  color: enabled ? FlowColors.accentCyan.withValues(alpha: 0.45) : FlowColors.border(context)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: enabled ? FlowColors.accentCyan : fg),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: FlowTypography.labelLarge(color: fg).copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Noya explains that the streak slipped and offers persistent 7-hour recovery with 1 Shield or 5 Ads.
class StreakRestorePopup extends StatefulWidget {
  final StreakRecovery recovery;

  const StreakRestorePopup({super.key, required this.recovery});

  static const _prefKey = 'flowstate_streak_restore_dismissed';

  static Future<bool> maybeShow(BuildContext context) async {
    final flow = _maybeFlow(context, listen: false);
    if (flow == null) return false;
    final rec = flow.streakRecovery;
    if (!rec.eligible && !rec.expired) return false;
    final now = FlowClock().now;
    final marker = '${now.year}-${now.month}-${now.day}|${rec.streak}|${rec.missedDays}';
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_prefKey) == marker) return false;
      await prefs.setString(_prefKey, marker);
    } catch (_) {}
    if (!context.mounted) return false;
    await show(context, rec);
    return true;
  }

  static Future<void> show(BuildContext context, StreakRecovery recovery) {
    final flow = _maybeFlow(context, listen: false);
    if (flow == null) return Future.value();
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<FlowProvider>.value(
        value: flow,
        child: StreakRestorePopup(recovery: recovery),
      ),
    );
  }

  @override
  State<StreakRestorePopup> createState() => _StreakRestorePopupState();
}

class _StreakRestorePopupState extends State<StreakRestorePopup> {
  bool _busy = false;
  String? _error;

  Future<void> _restore(FlowProvider flow, {String method = 'shield'}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await flow.restoreStreak(expectedCost: widget.recovery.cost, restoreMethod: method);
    if (!mounted) return;
    if (outcome.restored) {
      FlowHaptics.success();
      NoyaNoticeCenter.instance.success(outcome.message, title: 'Streak restored 🔥');
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = outcome.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flow = Provider.of<FlowProvider>(context);
    final rec = widget.recovery;
    final balance = flow.shieldBalance;
    final canAfford = balance >= rec.cost;
    final expired = rec.expired;

    return AlertDialog(
      key: const Key('streak_restore_popup'),
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
      contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [ShieldBalancePill()],
          ),
          const SizedBox(height: 4),
          const NoyaCompanionView(state: NoyaState.sleepy, size: 72, showAmbientGlow: true),
          const SizedBox(height: 10),
          Text(
            expired ? 'Streak recovery expired' : 'Restore your streak',
            key: const Key('streak_restore_title'),
            textAlign: TextAlign.center,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            expired
                ? "The 7-hour recovery window has expired. Complete a task today to start a fresh streak!"
                : "Your ${rec.streak}-day streak has ended and can still be recovered.",
            key: const Key('streak_restore_body'),
            textAlign: TextAlign.center,
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
          ),
          if (!expired) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: FlowColors.accentAmber.withValues(alpha: 0.12),
                borderRadius: FlowRadii.pillRadius,
                border: Border.all(color: FlowColors.accentAmber.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.timer_outlined, size: 15, color: FlowColors.accentAmber),
                  const SizedBox(width: 6),
                  Text(
                    rec.formatRemainingTime(),
                    key: const Key('streak_restore_countdown'),
                    style: FlowTypography.labelMedium(color: FlowColors.accentAmber).copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Option A: 1 Shield
            _OptionButton(
              key: const Key('streak_restore_button'),
              icon: Icons.shield_outlined,
              title: canAfford ? 'Restore with ${_shields(rec.cost)}' : 'Get Shields',
              subtitle: canAfford ? 'Deducts 1 Shield atomically' : '0 Shields available · Tap to get more',
              enabled: !_busy,
              onTap: () {
                if (canAfford) {
                  _restore(flow, method: 'shield');
                } else {
                  Navigator.of(context).pop();
                  ShieldWalletPopup.show(context);
                }
              },
            ),
            const SizedBox(height: 8),
            // Option B: 5 Ads
            _OptionButton(
              key: const Key('streak_restore_option_ads'),
              icon: Icons.play_circle_outline_rounded,
              title: 'Restore by watching ${rec.adsRequired} ads',
              subtitle: rec.canRestoreWithAds
                  ? '${rec.adsProgress}/${rec.adsRequired} ads watched · Ready to restore'
                  : (flow.wallet?.ads.enabled ?? false)
                      ? '${rec.adsProgress}/${rec.adsRequired} ads watched'
                      : 'Coming soon',
              enabled: !_busy && (flow.wallet?.ads.enabled ?? false) && rec.canRestoreWithAds,
              onTap: () => _restore(flow, method: 'ads'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                key: const Key('streak_restore_error'),
                textAlign: TextAlign.center,
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
          ],
          const SizedBox(height: 12),
          TextButton(
            key: const Key('streak_restore_dismiss'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text(expired ? 'Got it' : 'Not Now',
                style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context))),
          ),
        ],
      ),
    );
  }
}
