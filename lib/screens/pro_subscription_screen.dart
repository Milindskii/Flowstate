import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/pricing_config.dart';
import '../providers/app_state_provider.dart';
import '../services/ai_plan_service.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Flowstate Pro: what it adds, two plans (monthly / yearly) priced per day with the billing amount always stated, and
/// one clear action. Prices come from one config (ProPlanConfig / the server). No payment exists yet, so the action
/// says so: nothing is purchased, charged or unlocked here.
class ProSubscriptionScreen extends StatefulWidget {
  const ProSubscriptionScreen({super.key});

  @override
  State<ProSubscriptionScreen> createState() => _ProSubscriptionScreenState();
}

class _ProSubscriptionScreenState extends State<ProSubscriptionScreen> {
  // The server owns the price; until it answers (or if it cannot) the mirrored fallback is shown.
  List<ProPlanConfig> _plans = ProPlanConfig.defaultPlans;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final state = Provider.of<AppStateProvider>(context, listen: false);
      final plans = await AIPlanService(api: state.apiService).getProPlans();
      if (mounted && plans.isNotEmpty) setState(() => _plans = plans);
    } catch (_) {}
  }

  String _selectedId = ProPlanConfig.defaultPlans.last.id; // yearly: the better value, preselected (not purchased)

  void _onContinuePressed(BuildContext context) {
    FlowHaptics.lightTap();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('pro_not_open_dialog'),
        backgroundColor: FlowColors.surface(ctx),
        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.cardLargeRadius),
        title: Text(
          'Subscribing is not open yet',
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(ctx)).copyWith(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Nothing was charged and your plan has not changed. Flowstate will tell you here when Pro can be purchased.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Got it', style: FlowTypography.labelLarge(color: FlowColors.accentCyan).copyWith(fontWeight: FontWeight.w700)),
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

    final plans = _plans;
    final selected = plans.firstWhere((p) => p.id == _selectedId, orElse: () => plans.first);
    final features = plans.first.features.isNotEmpty ? plans.first.features : ProPlanConfig.defaultPlans.first.features;

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
        title: Text('Flowstate Pro',
            style: FlowTypography.titleSmall(color: textPrimary).copyWith(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Flowstate, without limits.',
                        style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800, height: 1.2),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    for (final f in features.take(4)) ...[
                      _buildFeatureItem(context, f, accent),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    // One row of plans: the same card, the better value marked, the selection a clear ring.
                    LayoutBuilder(builder: (context, c) {
                      final cards = [
                        for (final plan in plans)
                          _buildPlanCard(context, plan: plan, accent: accent, selected: plan.id == selected.id),
                      ];
                      if (c.maxWidth < 300) return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 10), child: w)]);
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < cards.length; i++) ...[
                              if (i > 0) const SizedBox(width: 10),
                              Expanded(child: cards[i]),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(pageMargin, 8, pageMargin, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                      child: Text('Continue with ${selected.title}',
                          style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w800, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Billing disclosure stays visible: what is billed, how often, and that it is not open yet.
                  Text(
                    selected.billingDisclosure.isEmpty ? 'Cancel anytime.' : '${selected.billingDisclosure}. Cancel anytime.',
                    key: const Key('pro_footer_disclosure'),
                    style: FlowTypography.labelSmall(color: textSecondary).copyWith(fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text('Purchasing is not open yet.', style: FlowTypography.labelSmall(color: textMuted), textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
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
          child: Text(text,
              style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _buildPlanCard(BuildContext context, {required ProPlanConfig plan, required Color accent, required bool selected}) {
    final textPrimary = FlowColors.textPrimaryOf(context);
    final textSecondary = FlowColors.textSecondaryOf(context);
    final period = plan.title.toUpperCase();
    return Semantics(
      button: true,
      selected: selected,
      label: '${plan.title} plan, ${plan.dailyPriceDisplay}, ${plan.billingDisclosure}${plan.isBestValue ? ', best value' : ''}',
      excludeSemantics: true,
      child: InkWell(
        key: Key('pro_plan_${plan.billingPeriod}'),
        borderRadius: FlowRadii.cardRadius,
        onTap: () {
          FlowHaptics.selection();
          setState(() => _selectedId = plan.id);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.1) : FlowColors.surface(context),
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(color: selected ? accent : FlowColors.border(context), width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(period,
                        style: FlowTypography.labelSmall(color: textSecondary).copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.1)),
                  ),
                  if (plan.isBestValue)
                    Container(
                      key: const Key('pro_best_value_badge'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: accent, borderRadius: FlowRadii.pillRadius),
                      child: Text('BEST VALUE',
                          style: FlowTypography.labelSmall(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w800, fontSize: 9.5)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  plan.dailyPriceDisplay.isNotEmpty ? plan.dailyPriceDisplay : plan.displayPrice,
                  key: Key('pro_daily_price_${plan.billingPeriod}'),
                  style: FlowTypography.headlineMedium(color: textPrimary).copyWith(fontWeight: FontWeight.w800, fontSize: 24),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                plan.billingDisclosure,
                key: Key('pro_billing_${plan.billingPeriod}'),
                style: FlowTypography.bodySmall(color: textSecondary).copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
