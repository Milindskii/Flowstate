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
    );
  }

  factory FlowProfile.fromJson(Map<String, dynamic> json) {
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
    };
  }
}
