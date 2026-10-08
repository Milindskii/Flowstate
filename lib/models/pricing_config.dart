/// Pro pricing as the app shows it.
///
/// The server owns the price (backend core/economy_config.py -> GET /api/v1/subscription/plans). [defaultPlans] is the
/// offline fallback and mirrors those numbers, so there is one number to change in two obvious places. The app never
/// derives entitlement from any of this: whether a user is Pro comes only from the server-verified status.
class ProPlanConfig {
  final String id;
  final String title;
  final String billingPeriod; // 'monthly'
  final String displayPrice; // "₹89 / month"
  final int? monthlyPriceInr;
  final String dailyPriceDisplay; // "₹2.97/day": the headline
  final String billingDisclosure; // "₹89 billed monthly": always shown with the headline
  final bool purchasable; // server flag: store billing is live
  final bool isBestValue;
  final String status;
  final List<String> features;

  const ProPlanConfig({
    required this.id,
    required this.title,
    required this.billingPeriod,
    required this.displayPrice,
    this.monthlyPriceInr,
    this.dailyPriceDisplay = '',
    this.billingDisclosure = '',
    this.purchasable = false,
    this.isBestValue = false,
    this.status = 'pricing_set',
    this.features = const [],
  });

  /// "₹2.97/day" from a monthly price over a 30-day month, rounded half-up to the paisa.
  static String dailyPriceFor(int monthlyInr) {
    final paise = (monthlyInr * 100 / 30);
    final rounded = (paise + 0.5).floor(); // half-up
    return '₹${(rounded / 100).toStringAsFixed(2)}/day';
  }

  factory ProPlanConfig.fromJson(Map<String, dynamic> p) {
    final monthly = (p['monthly_price_inr'] as num?)?.toInt();
    return ProPlanConfig(
      id: (p['plan_id'] ?? p['id'] ?? 'flowstate_pro_monthly') as String,
      title: (p['title'] ?? p['name'] ?? 'Monthly') as String,
      billingPeriod: p['billing_period'] as String? ?? 'monthly',
      displayPrice: (p['price_display'] ?? p['display_price'] ?? '') as String,
      monthlyPriceInr: monthly,
      dailyPriceDisplay: p['daily_price_display'] as String? ?? (monthly != null ? dailyPriceFor(monthly) : ''),
      billingDisclosure: p['billing_disclosure'] as String? ?? (monthly != null ? '₹$monthly billed monthly' : ''),
      purchasable: p['purchasable'] as bool? ?? false,
      isBestValue: p['is_best_value'] as bool? ?? false,
      status: (p['status'] ?? p['pricing_note'] ?? 'pricing_set') as String,
      features: (p['features'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  static const List<ProPlanConfig> defaultPlans = [
    ProPlanConfig(
      id: 'flowstate_pro_monthly',
      title: 'Monthly',
      billingPeriod: 'monthly',
      displayPrice: '₹89 / month',
      monthlyPriceInr: 89,
      dailyPriceDisplay: '₹2.97/day',
      billingDisclosure: '₹89 billed monthly',
      purchasable: false,
      features: [
        'More AI Brain Dumps',
        'Advanced personalization',
        'More planning flexibility',
        'Future Pro features',
      ],
    ),
  ];
}
