import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/pricing_config.dart';

void main() {
  test('₹89 a month is ₹2.97 a day (half-up), and the fallback mirrors the server', () {
    expect(ProPlanConfig.dailyPriceFor(89), '₹2.97/day');
    expect(ProPlanConfig.dailyPriceFor(90), '₹3.00/day');
    expect(ProPlanConfig.dailyPriceFor(100), '₹3.33/day');
    final fallback = ProPlanConfig.defaultPlans.first;
    expect(fallback.monthlyPriceInr, 89);
    expect(fallback.dailyPriceDisplay, ProPlanConfig.dailyPriceFor(89));
    expect(fallback.billingDisclosure, '₹89 billed monthly');
    expect(fallback.purchasable, isFalse);
  });

  test('the server plan shape parses, and the daily price never appears without the monthly billing line', () {
    final plan = ProPlanConfig.fromJson({
      'plan_id': 'flowstate_pro_monthly',
      'title': 'Monthly',
      'billing_period': 'monthly',
      'price_display': '₹89 / month',
      'monthly_price_inr': 89,
      'daily_price_display': '₹2.97/day',
      'billing_disclosure': '₹89 billed monthly',
      'purchasable': false,
    });
    expect(plan.dailyPriceDisplay, '₹2.97/day');
    expect(plan.billingDisclosure, '₹89 billed monthly');
    // an older response with only a monthly number still discloses the monthly billing
    final minimal = ProPlanConfig.fromJson({'plan_id': 'flowstate_pro_monthly', 'monthly_price_inr': 89});
    expect(minimal.dailyPriceDisplay, '₹2.97/day');
    expect(minimal.billingDisclosure, '₹89 billed monthly');
  });

  test('yearly: ₹999 a year is ₹2.74 a day, cheaper per day than monthly, marked best value, and not purchasable yet', () {
    expect(ProPlanConfig.dailyPriceForYearly(999), '₹2.74/day');
    final plans = ProPlanConfig.defaultPlans;
    expect(plans.map((p) => p.id), ['flowstate_pro_monthly', 'flowstate_pro_yearly']);
    final yearly = plans.last;
    expect(yearly.yearlyPriceInr, 999);
    expect(yearly.dailyPriceDisplay, ProPlanConfig.dailyPriceForYearly(999));
    expect(yearly.billingDisclosure, '₹999 billed yearly');
    expect(yearly.isBestValue, isTrue);
    expect(plans.first.isBestValue, isFalse);
    expect(plans.every((p) => !p.purchasable), isTrue, reason: 'no payment backend: nothing may look buyable');
    double perDay(ProPlanConfig p) => double.parse(p.dailyPriceDisplay.substring(1, p.dailyPriceDisplay.indexOf('/')));
    expect(perDay(yearly), lessThan(perDay(plans.first)));
  });

  test('a server yearly plan parses without a monthly number and still discloses yearly billing', () {
    final plan = ProPlanConfig.fromJson({'plan_id': 'flowstate_pro_yearly', 'billing_period': 'yearly', 'yearly_price_inr': 999});
    expect(plan.isYearly, isTrue);
    expect(plan.dailyPriceDisplay, '₹2.74/day');
    expect(plan.billingDisclosure, '₹999 billed yearly');
  });
}
