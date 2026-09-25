/// Centralized pricing and Google Play SKU configuration model.
///
/// Production prices will be fetched dynamically from Google Play In-App Billing.
/// In V1 / development, prices are intentionally TBD / 'Pricing coming soon'
/// with zero hardcoded fake prices.
class ProPlanConfig {
  final String id;
  final String title;
  final String billingPeriod; // 'monthly' | 'yearly'
  final String displayPrice;
  final bool isBestValue;
  final String status;
  final List<String> features;

  const ProPlanConfig({
    required this.id,
    required this.title,
    required this.billingPeriod,
    required this.displayPrice,
    this.isBestValue = false,
    this.status = 'pricing_coming_soon',
    this.features = const [],
  });

  static const List<ProPlanConfig> defaultPlans = [
    ProPlanConfig(
      id: 'flowstate_pro_monthly',
      title: 'Monthly',
      billingPeriod: 'monthly',
      displayPrice: '₹— / month',
      isBestValue: false,
      status: 'pricing_coming_soon',
      features: [
        'More AI Brain Dumps',
        'Advanced personalization',
        'More planning flexibility',
        'Future Pro features',
      ],
    ),
    ProPlanConfig(
      id: 'flowstate_pro_yearly',
      title: 'Yearly',
      billingPeriod: 'yearly',
      displayPrice: '₹— / year',
      isBestValue: true,
      status: 'pricing_coming_soon',
      features: [
        'All Monthly features',
        'Best value commitment',
        'Continuous progression shield boosts',
      ],
    ),
  ];
}
