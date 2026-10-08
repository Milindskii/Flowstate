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
  final int? yearlyPriceInr;
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
    this.yearlyPriceInr,
    this.dailyPriceDisplay = '',
    this.billingDisclosure = '',
    this.purchasable = false,
    this.isBestValue = false,
    this.status = 'pricing_set',
    this.features = const [],
  });

  /// "₹2.97/day" from a monthly price over a 30-day month, rounded half-up to the paisa.
  static String dailyPriceFor(int monthlyInr) => _daily(monthlyInr, 30);

  /// "₹2.74/day" from a yearly price over 365 days, rounded half-up to the paisa.
  static String dailyPriceForYearly(int yearlyInr) => _daily(yearlyInr, 365);

  static String _daily(int priceInr, int days) {
    final paise = (priceInr * 100 / days);
    final rounded = (paise + 0.5).floor(); // half-up
    return '₹${(rounded / 100).toStringAsFixed(2)}/day';
  }

  bool get isYearly => billingPeriod == 'yearly';

  factory ProPlanConfig.fromJson(Map<String, dynamic> p) {
    final monthly = (p['monthly_price_inr'] as num?)?.toInt();
    final yearly = (p['yearly_price_inr'] as num?)?.toInt();
    return ProPlanConfig(
      id: (p['plan_id'] ?? p['id'] ?? 'flowstate_pro_monthly') as String,
      title: (p['title'] ?? p['name'] ?? 'Monthly') as String,
      billingPeriod: p['billing_period'] as String? ?? 'monthly',
      displayPrice: (p['price_display'] ?? p['display_price'] ?? '') as String,
      monthlyPriceInr: monthly,
      yearlyPriceInr: yearly,
      dailyPriceDisplay: p['daily_price_display'] as String? ??
          (yearly != null ? dailyPriceForYearly(yearly) : (monthly != null ? dailyPriceFor(monthly) : '')),
      billingDisclosure: p['billing_disclosure'] as String? ??
          (yearly != null ? '₹$yearly billed yearly' : (monthly != null ? '₹$monthly billed monthly' : '')),
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
    ProPlanConfig(
      id: 'flowstate_pro_yearly',
      title: 'Yearly',
      billingPeriod: 'yearly',
      displayPrice: '₹999 / year',
      yearlyPriceInr: 999,
      dailyPriceDisplay: '₹2.74/day',
      billingDisclosure: '₹999 billed yearly',
      purchasable: false,
      isBestValue: true,
      features: [
        'More AI Brain Dumps',
        'Advanced personalization',
        'More planning flexibility',
        'Future Pro features',
      ],
    ),
  ];
}
