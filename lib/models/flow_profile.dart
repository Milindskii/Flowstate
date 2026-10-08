/// Flow Profile Model
/// Authoritative user progression state including Flow balance,
/// streak metrics, shields, and league status.
class FlowProfile {
  final String userId;
  final int flowBalance;
  final int lifetimeFlow;
  final int currentStreak;
  final int longestStreak;
  final String? streakStartDate;
  final String? lastQualifyingDate;
  final int shieldProgressDays; // 0 to 6
  final int shieldsAvailable; // 0 to 3
  final int shieldsUsedCount;
  final String? lastShieldUsedDate;
  final int weeklyFlowPoints;
  final String? currentWeekIdentifier;
  final String leagueTier;
  final bool isPro;

  /// The most Shields an account holds, and the SERVER instant its next free one lands (null at the maximum).
  final int shieldMax;
  final DateTime? shieldRefillAt;

  /// The server's wait for that Shield when this was read, and the device time it was read at: the countdown is the
  /// server-measured wait minus the time elapsed here, so a wrong device clock cannot change it.
  final Duration? untilNextShield;
  final DateTime? readAt;

  /// Time left until the next free Shield at [now]; null when none is counting down.
  Duration? untilNextShieldAt(DateTime now) {
    final base = untilNextShield;
    final at = readAt;
    if (base == null) return null;
    if (at == null) return base;
    final elapsed = now.difference(at);
    final left = base - (elapsed.isNegative ? Duration.zero : elapsed);
    return left.isNegative ? Duration.zero : left;
  }

  const FlowProfile({
    required this.userId,
    this.flowBalance = 0,
    this.lifetimeFlow = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.streakStartDate,
    this.lastQualifyingDate,
    this.shieldProgressDays = 0,
    this.shieldsAvailable = 0,
    this.shieldsUsedCount = 0,
    this.lastShieldUsedDate,
    this.weeklyFlowPoints = 0,
    this.currentWeekIdentifier,
    this.leagueTier = 'Bronze',
    this.isPro = false,
    this.shieldMax = 3,
    this.shieldRefillAt,
    this.untilNextShield,
    this.readAt,
  });

  double get shieldProgressFraction => (shieldProgressDays / 7.0).clamp(0.0, 1.0);

  bool get hasShields => shieldsAvailable > 0;

  FlowProfile copyWith({
    String? userId,
    int? flowBalance,
    int? lifetimeFlow,
    int? currentStreak,
    int? longestStreak,
    String? streakStartDate,
    String? lastQualifyingDate,
    int? shieldProgressDays,
    int? shieldsAvailable,
    int? shieldsUsedCount,
    String? lastShieldUsedDate,
    int? weeklyFlowPoints,
    String? currentWeekIdentifier,
    String? leagueTier,
    bool? isPro,
  }) {
    return FlowProfile(
      userId: userId ?? this.userId,
      flowBalance: flowBalance ?? this.flowBalance,
      lifetimeFlow: lifetimeFlow ?? this.lifetimeFlow,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      streakStartDate: streakStartDate ?? this.streakStartDate,
      lastQualifyingDate: lastQualifyingDate ?? this.lastQualifyingDate,
      shieldProgressDays: shieldProgressDays ?? this.shieldProgressDays,
      shieldsAvailable: shieldsAvailable ?? this.shieldsAvailable,
      shieldsUsedCount: shieldsUsedCount ?? this.shieldsUsedCount,
      lastShieldUsedDate: lastShieldUsedDate ?? this.lastShieldUsedDate,
      weeklyFlowPoints: weeklyFlowPoints ?? this.weeklyFlowPoints,
      currentWeekIdentifier: currentWeekIdentifier ?? this.currentWeekIdentifier,
      leagueTier: leagueTier ?? this.leagueTier,
      isPro: isPro ?? this.isPro,
      shieldMax: shieldMax,
      shieldRefillAt: shieldRefillAt,
      untilNextShield: untilNextShield,
      readAt: readAt,
    );
  }

  factory FlowProfile.fromJson(Map<String, dynamic> json) {
    final refill = DateTime.tryParse(json['shield_refill_at'] as String? ?? '');
    final serverNow = DateTime.tryParse(json['server_now'] as String? ?? '');
    return FlowProfile(
      userId: json['user_id'] as String? ?? 'user-default',
      flowBalance: json['flow_balance'] as int? ?? 0,
      lifetimeFlow: json['lifetime_flow'] as int? ?? 0,
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      streakStartDate: json['streak_start_date'] as String?,
      lastQualifyingDate: json['last_qualifying_date'] as String?,
      shieldProgressDays: json['shield_progress_days'] as int? ?? 0,
      shieldsAvailable: json['shields_available'] as int? ?? 0,
      shieldsUsedCount: json['shields_used_count'] as int? ?? 0,
      lastShieldUsedDate: json['last_shield_used_date'] as String?,
      weeklyFlowPoints: json['weekly_flow_points'] as int? ?? 0,
      currentWeekIdentifier: json['current_week_identifier'] as String?,
      leagueTier: json['league_tier'] as String? ?? 'Bronze',
      isPro: json['is_pro'] as bool? ?? false,
      shieldMax: json['shield_max'] as int? ?? 3,
      shieldRefillAt: refill,
      untilNextShield: (refill != null && serverNow != null) ? refill.difference(serverNow) : null,
      readAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'flow_balance': flowBalance,
      'lifetime_flow': lifetimeFlow,
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'streak_start_date': streakStartDate,
      'last_qualifying_date': lastQualifyingDate,
      'shield_progress_days': shieldProgressDays,
      'shields_available': shieldsAvailable,
      'shields_used_count': shieldsUsedCount,
      'last_shield_used_date': lastShieldUsedDate,
      'weekly_flow_points': weeklyFlowPoints,
      'current_week_identifier': currentWeekIdentifier,
      'league_tier': leagueTier,
      'is_pro': isPro,
      'shield_max': shieldMax,
      'shield_refill_at': shieldRefillAt?.toUtc().toIso8601String(),
      // the cached copy counts down from the moment it was read, not from a stale server instant
      if (shieldRefillAt != null && untilNextShield != null)
        'server_now': shieldRefillAt!.subtract(untilNextShieldAt(DateTime.now()) ?? untilNextShield!).toUtc().toIso8601String(),
    };
  }
}
