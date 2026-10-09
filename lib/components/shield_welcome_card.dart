import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ai_plan_models.dart';
import '../providers/app_state_provider.dart';
import '../services/ai_plan_service.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';

/// The one-time welcome for a brand-new account: "You're ready! 🛡️🛡️ · 2 Shields added.", what a Shield is for, and
/// a small arrow that points at the Build My Day button right below it.
///
/// Server-owned and once per account: the card appears only while the server says `shield_welcome_pending`, and it
/// tells the server it was shown the moment it appears, so a restart, a login or another device never shows it again.
/// It never grants anything (the 2 Shields were added when the account was created) and it never blocks the screen:
/// one dismiss button, no steps.
class ShieldWelcomeCard extends StatefulWidget {
  /// The server's view of the account. Defaults to `GET /ai/status` for the signed-in user.
  final Future<AIUsageStatus?> Function()? loadStatus;

  /// Tells the server the welcome was shown. Defaults to `POST /ai/shield-welcome/seen`.
  final Future<void> Function()? markSeen;

  const ShieldWelcomeCard({super.key, this.loadStatus, this.markSeen});

  @override
  State<ShieldWelcomeCard> createState() => ShieldWelcomeCardState();
}

class ShieldWelcomeCardState extends State<ShieldWelcomeCard> with SingleTickerProviderStateMixin {
  late final AnimationController _point = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
  AIUsageStatus? _status;
  bool _visible = false;
  bool _animated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  AIPlanService? _service() {
    try {
      final app = Provider.of<AppStateProvider>(context, listen: false);
      return app.isAuthenticated ? AIPlanService(api: app.apiService) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    try {
      final status = widget.loadStatus != null ? await widget.loadStatus!() : await _service()?.getUsageStatus();
      if (!mounted || status == null || !status.shieldWelcomePending) return;
      setState(() {
        _status = status;
        _visible = true;
      });
      // Shown now, so never again: told to the server immediately (a restart must not bring it back).
      if (widget.markSeen != null) {
        await widget.markSeen!();
      } else {
        await _service()?.markShieldWelcomeSeen();
      }
    } catch (_) {}
  }

  /// Hides the card (the dismiss button, or the user pressing Build My Day, which is exactly what it pointed at).
  void dismiss() {
    if (!_visible) return;
    setState(() => _visible = false);
  }

  void _startPointing(BuildContext context) {
    if (_animated) return;
    _animated = true;
    if (MediaQuery.of(context).disableAnimations) {
      _point.value = 0.5; // reduced motion: the arrow just rests where it points
      return;
    }
    _point.repeat(reverse: true, count: 6); // a short nudge, then it rests
  }

  @override
  void dispose() {
    _point.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    _startPointing(context);
    final granted = _status?.shieldsAvailable ?? 2;
    final cost = _status?.shieldCost ?? AIUsageStatus.defaultShieldCost;
    final shieldWord = cost == 1 ? 'Shield' : 'Shields';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child),
      ),
      child: Container(
        key: const Key('shield_welcome_card'),
        margin: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              decoration: BoxDecoration(
                color: FlowColors.surfaceElevated(context),
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.accentCyan.withValues(alpha: 0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const NoyaCompanionView(state: NoyaState.cheering, size: 56, showAmbientGlow: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "You're ready! 🛡️🛡️",
                          key: const Key('shield_welcome_title'),
                          style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context))
                              .copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            for (var i = 0; i < granted.clamp(0, 3); i++)
                              Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(Icons.shield_rounded,
                                    key: Key('shield_welcome_icon_$i'), size: 16, color: FlowColors.accentCyan),
                              ),
                            const SizedBox(width: 3),
                            Text(
                              '$granted Shields added.',
                              key: const Key('shield_welcome_added'),
                              style: FlowTypography.labelMedium(color: FlowColors.accentCyan)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use $cost $shieldWord when Noya builds your day for you.',
                          key: const Key('shield_welcome_body'),
                          style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
                              .copyWith(fontSize: 12.5, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('shield_welcome_dismiss'),
                    tooltip: 'Dismiss',
                    onPressed: dismiss,
                    icon: Icon(Icons.close_rounded, size: 18, color: FlowColors.textMutedOf(context)),
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  ),
                ],
              ),
            ),
            // The pointer: the Build My Day button is directly under this card.
            AnimatedBuilder(
              animation: _point,
              builder: (context, child) => Transform.translate(offset: Offset(0, _point.value * 5), child: child),
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  key: const Key('shield_welcome_pointer'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Noya can build your day here',
                        style: FlowTypography.labelSmall(color: FlowColors.accentCyan)
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_downward_rounded, size: 16, color: FlowColors.accentCyan),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
