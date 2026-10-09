/// The server's Shield wallet (GET /api/v1/shields): balance, every price, and the ways to earn more.
///
/// Everything here is read from the server; the app never computes a balance, a price or a reward itself.
class ShieldWallet {
  final int balance;
  final int maximum;
  final DateTime? nextRefillAt;
  final DateTime? serverNow;
  final int costBuildMyDay;
  final int costReplan;
  final int costStreakRestore;
  final AdOffer ads;
  final PackOffer pack;

  const ShieldWallet({
    required this.balance,
    this.maximum = 3,
    this.nextRefillAt,
    this.serverNow,
    this.costBuildMyDay = 1,
    this.costReplan = 1,
    this.costStreakRestore = 1,
    this.ads = const AdOffer(),
    this.pack = const PackOffer(),
  });

  /// Time until the next free Shield measured on the SERVER's clock (difference of two server instants), so a
  /// device clock change cannot move it. Null when no refill is running.
  Duration? get untilNextRefill {
    final next = nextRefillAt;
    final now = serverNow;
    if (next == null || now == null) return null;
    final d = next.difference(now);
    return d.isNegative ? Duration.zero : d;
  }

  factory ShieldWallet.fromJson(Map<String, dynamic> json) {
    final costs = json['costs'] as Map<String, dynamic>? ?? const {};
    return ShieldWallet(
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      maximum: (json['maximum'] as num?)?.toInt() ?? 3,
      nextRefillAt: DateTime.tryParse(json['next_refill_at'] as String? ?? ''),
      serverNow: DateTime.tryParse(json['server_now'] as String? ?? ''),
      costBuildMyDay: (costs['build_my_day'] as num?)?.toInt() ?? 1,
      costReplan: (costs['replan'] as num?)?.toInt() ?? 1,
      costStreakRestore: (costs['streak_restore'] as num?)?.toInt() ?? 1,
      ads: AdOffer.fromJson(json['ads'] as Map<String, dynamic>? ?? const {}),
      pack: PackOffer.fromJson(json['pack'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

/// "Watch N ads, get a Shield". Progress and limits are the server's (verified ads only).
class AdOffer {
  final bool enabled;
  final String? adUnitId;
  final int adsPerReward;
  final int shieldsPerReward;
  final int progress;
  final int dailyRemaining;

  const AdOffer({
    this.enabled = false,
    this.adUnitId,
    this.adsPerReward = 5,
    this.shieldsPerReward = 1,
    this.progress = 0,
    this.dailyRemaining = 0,
  });

  factory AdOffer.fromJson(Map<String, dynamic> json) => AdOffer(
        enabled: json['enabled'] as bool? ?? false,
        adUnitId: json['ad_unit_id'] as String?,
        adsPerReward: (json['ads_per_reward'] as num?)?.toInt() ?? 5,
        shieldsPerReward: (json['shields_per_reward'] as num?)?.toInt() ?? 1,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        dailyRemaining: (json['daily_remaining'] as num?)?.toInt() ?? 0,
      );
}

/// The paid Shield pack. `enabled` is false until store billing is verified server-side.
class PackOffer {
  final bool enabled;
  final String productId;
  final String priceDisplay;
  final int units;
  final String? accountRef;

  const PackOffer({
    this.enabled = false,
    this.productId = 'flowstate_shield_pack_20',
    this.priceDisplay = '₹20',
    this.units = 5,
    this.accountRef,
  });

  factory PackOffer.fromJson(Map<String, dynamic> json) => PackOffer(
        enabled: json['enabled'] as bool? ?? false,
        productId: json['product_id'] as String? ?? 'flowstate_shield_pack_20',
        priceDisplay: json['price_display'] as String? ?? '₹20',
        units: (json['units'] as num?)?.toInt() ?? 5,
        accountRef: json['account_ref'] as String?,
      );
}

/// Whether the streak can be restored now (server-decided), and what it costs.
class StreakRecovery {
  final bool eligible;
  final bool expired;
  final int streak;
  final int missedDays;
  final int cost;
  final int shieldsAvailable;
  final bool canAfford;
  final String? reason;
  final DateTime? deadlineAt;
  final int secondsRemaining;
  final int adsRequired;
  final int adsProgress;
  final bool canRestoreWithAds;

  const StreakRecovery({
    this.eligible = false,
    this.expired = false,
    this.streak = 0,
    this.missedDays = 0,
    this.cost = 1,
    this.shieldsAvailable = 0,
    this.canAfford = false,
    this.reason,
    this.deadlineAt,
    this.secondsRemaining = 0,
    this.adsRequired = 5,
    this.adsProgress = 0,
    this.canRestoreWithAds = false,
  });

  static const none = StreakRecovery();

  factory StreakRecovery.fromJson(Map<String, dynamic> json) => StreakRecovery(
        eligible: json['eligible'] as bool? ?? false,
        expired: json['expired'] as bool? ?? false,
        streak: (json['streak'] as num?)?.toInt() ?? 0,
        missedDays: (json['missed_days'] as num?)?.toInt() ?? 0,
        cost: (json['cost'] as num?)?.toInt() ?? 1,
        shieldsAvailable: (json['shields_available'] as num?)?.toInt() ?? 0,
        canAfford: json['can_afford'] as bool? ?? false,
        reason: json['reason'] as String?,
        deadlineAt: json['deadline_at'] != null ? DateTime.tryParse(json['deadline_at'].toString()) : null,
        secondsRemaining: (json['seconds_remaining'] as num?)?.toInt() ?? 0,
        adsRequired: (json['ads_required'] as num?)?.toInt() ?? 5,
        adsProgress: (json['ads_progress'] as num?)?.toInt() ?? 0,
        canRestoreWithAds: json['can_restore_with_ads'] as bool? ?? false,
      );

  String formatRemainingTime() {
    if (secondsRemaining <= 0) return '0m left';
    final hours = secondsRemaining ~/ 3600;
    final minutes = (secondsRemaining % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m left';
    }
    return '${minutes}m left';
  }

  Map<String, dynamic> toJson() => {
        'eligible': eligible,
        'expired': expired,
        'streak': streak,
        'missed_days': missedDays,
        'cost': cost,
        'shields_available': shieldsAvailable,
        'can_afford': canAfford,
        'reason': reason,
        'deadline_at': deadlineAt?.toIso8601String(),
        'seconds_remaining': secondsRemaining,
        'ads_required': adsRequired,
        'ads_progress': adsProgress,
        'can_restore_with_ads': canRestoreWithAds,
      };
}

