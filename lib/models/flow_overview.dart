import 'flow_companion.dart';
import 'flow_profile.dart';
import 'flow_challenge.dart';
import 'flow_daily_quest.dart';
import 'flow_achievement.dart';

/// Weekly grind progress snapshot returned in the overview payload.
class FlowWeeklyProgress {
  final String weekIdentifier;
  final int sessionsCompleted;
  final int focusMinutesLogged;
  final int priorityTasksCompleted;
  final int feedbackGiven;
  final int flowPointsEarned;
  final int adaptiveSessionTarget;
  final int adaptiveMinutesTarget;
  final bool weeklyGoalHit;

  const FlowWeeklyProgress({
    required this.weekIdentifier,
    this.sessionsCompleted = 0,
    this.focusMinutesLogged = 0,
    this.priorityTasksCompleted = 0,
    this.feedbackGiven = 0,
    this.flowPointsEarned = 0,
    this.adaptiveSessionTarget = 3,
    this.adaptiveMinutesTarget = 60,
    this.weeklyGoalHit = false,
  });

  factory FlowWeeklyProgress.fromJson(Map<String, dynamic> json) {
    return FlowWeeklyProgress(
      weekIdentifier: json['week_identifier'] as String? ?? '',
      sessionsCompleted: json['sessions_completed'] as int? ?? 0,
      focusMinutesLogged: json['focus_minutes_logged'] as int? ?? 0,
      priorityTasksCompleted: json['priority_tasks_completed'] as int? ?? 0,
      feedbackGiven: json['feedback_given'] as int? ?? 0,
      flowPointsEarned: json['flow_points_earned'] as int? ?? 0,
      adaptiveSessionTarget: json['adaptive_session_target'] as int? ?? 3,
      adaptiveMinutesTarget: json['adaptive_minutes_target'] as int? ?? 60,
      weeklyGoalHit: json['weekly_goal_hit'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'week_identifier': weekIdentifier,
    'sessions_completed': sessionsCompleted,
    'focus_minutes_logged': focusMinutesLogged,
    'priority_tasks_completed': priorityTasksCompleted,
    'feedback_given': feedbackGiven,
    'flow_points_earned': flowPointsEarned,
    'adaptive_session_target': adaptiveSessionTarget,
    'adaptive_minutes_target': adaptiveMinutesTarget,
    'weekly_goal_hit': weeklyGoalHit,
  };

  /// Progress fraction [0.0 – 1.0] toward the adaptive session target.
  double get sessionProgressFraction =>
      adaptiveSessionTarget > 0
          ? (sessionsCompleted / adaptiveSessionTarget).clamp(0.0, 1.0)
          : 0.0;
}

/// Aggregated Flow Overview Model combining Companion, Profile,
/// Challenges, Daily Quests, Achievements, League Cohort, and Personal Progress.
class FlowOverview {
  final FlowCompanion companion;
  final FlowProfile profile;
  final FlowChallenge? activeChallenge;
  final List<FlowDailyQuest> dailyQuests;
  final List<FlowAchievement> achievements;
  final FlowWeeklyProgress? weeklyProgress;
  final String leagueTier;
  final int weeklyFlowPoints;
  final String leagueStatusMessage;
  final int personalBestFocusMinutes;
  final int weeklyFocusSessions;
  final int weeklyFocusMinutes;
  final int totalFocusMinutes;
  final int totalSessionsCompleted;
  final int bestFocusDayMinutes;
  final String consistencyScore;
  final String rhythmAcknowledgement;
  final String? activeSessionId;
  final String? notification;

  const FlowOverview({
    required this.companion,
    required this.profile,
    this.activeChallenge,
    this.dailyQuests = const [],
    this.achievements = const [],
    this.weeklyProgress,
    this.leagueTier = 'Bronze',
    this.weeklyFlowPoints = 0,
    this.leagueStatusMessage = 'Focus on your rhythm. Cohort leagues open when participant quorum is reached.',
    this.personalBestFocusMinutes = 0,
    this.weeklyFocusSessions = 0,
    this.weeklyFocusMinutes = 0,
    this.totalFocusMinutes = 0,
    this.totalSessionsCompleted = 0,
    this.bestFocusDayMinutes = 0,
    this.consistencyScore = 'Building',
    this.rhythmAcknowledgement = 'Start your first flow to build your rhythm with Noya. 🦊',
    this.activeSessionId,
    this.notification,
  });

  static FlowOverview defaultInitial({String userId = 'user-default'}) {
    return FlowOverview(
      companion: const FlowCompanion(
        id: 'companion-initial',
        species: 'fox',
        name: 'Noya',
        level: 1,
        stage: 'Baby',
        companionXp: 0,
        xpToNextLevel: 60,
      ),
      profile: FlowProfile(
        userId: userId,
        flowBalance: 0,
        currentStreak: 0,
        longestStreak: 0,
        shieldsAvailable: 0,
      ),
      activeChallenge: const FlowChallenge(
        id: 'challenge-initial',
        weekIdentifier: 'current',
        title: 'Complete 5 priority tasks',
        targetCount: 5,
        currentCount: 0,
      ),
      dailyQuests: const [
        FlowDailyQuest(
          id: 'quest-1',
          questDate: 'today',
          questKey: 'complete_1_session',
          title: 'Deep Focus',
          description: 'Complete 1 focus session today',
          targetCount: 1,
          currentCount: 0,
          rewardFlow: 15,
          isCompleted: false,
          isClaimed: false,
        ),
        FlowDailyQuest(
          id: 'quest-2',
          questDate: 'today',
          questKey: 'finish_2_tasks',
          title: 'Planned Execution',
          description: 'Finish 2 planned tasks',
          targetCount: 2,
          currentCount: 0,
          rewardFlow: 20,
          isCompleted: false,
          isClaimed: false,
        ),
        FlowDailyQuest(
          id: 'quest-3',
          questDate: 'today',
          questKey: 'give_feedback',
          title: 'Rhythm Calibration',
          description: 'Record session feeling feedback',
          targetCount: 1,
          currentCount: 0,
          rewardFlow: 10,
          isCompleted: false,
          isClaimed: false,
        ),
      ],
      achievements: const [
        FlowAchievement(
          id: 'ach-1',
          achievementKey: 'first_spark',
          title: 'First Spark',
          description: 'Complete your very first focus session with Noya.',
          icon: 'bolt',
          rewardFlow: 25,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-2',
          achievementKey: 'in_the_groove',
          title: 'In the Groove',
          description: 'Maintain a 3-day focus streak.',
          icon: 'local_fire_department',
          rewardFlow: 30,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-3',
          achievementKey: 'weekly_anchor',
          title: 'Weekly Anchor',
          description: 'Reach a 7-day focus streak without breaking rhythm.',
          icon: 'shield',
          rewardFlow: 50,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-4',
          achievementKey: 'habit_master',
          title: 'Habit Master',
          description: 'Achieve an unshakeable 30-day focus streak.',
          icon: 'military_tech',
          rewardFlow: 150,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-5',
          achievementKey: 'decathlon',
          title: 'Decathlon',
          description: 'Complete 10 focused work sessions.',
          icon: 'timer',
          rewardFlow: 40,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-6',
          achievementKey: 'quarter_century',
          title: 'Quarter Century',
          description: 'Complete 25 focused work sessions.',
          icon: 'stars',
          rewardFlow: 75,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-7',
          achievementKey: 'centurion',
          title: 'Centurion',
          description: 'Complete 100 focused work sessions.',
          icon: 'workspace_premium',
          rewardFlow: 200,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-8',
          achievementKey: 'ten_hour_club',
          title: 'Ten Hour Club',
          description: 'Log 10 hours (600 minutes) of deep focused work.',
          icon: 'hourglass_bottom',
          rewardFlow: 60,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-9',
          achievementKey: 'deep_diver',
          title: 'Deep Diver',
          description: 'Complete a single marathon focus session of 60+ minutes.',
          icon: 'scuba_diving',
          rewardFlow: 50,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-10',
          achievementKey: 'rhythm_sync',
          title: 'Rhythm Sync',
          description: 'Complete a focus session during your peak focus window.',
          icon: 'light_mode',
          rewardFlow: 30,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-11',
          achievementKey: 'night_scholar',
          title: 'Night Scholar',
          description: 'Complete a focus session in an evening or quiet window.',
          icon: 'nights_stay',
          rewardFlow: 30,
          isUnlocked: false,
        ),
        FlowAchievement(
          id: 'ach-12',
          achievementKey: 'personal_best',
          title: 'Personal Best',
          description: 'Surpass your previous record for longest focus session.',
          icon: 'emoji_events',
          rewardFlow: 50,
          isUnlocked: false,
        ),
      ],
    );
  }

  factory FlowOverview.fromJson(Map<String, dynamic> json) {
    final compJson = json['companion'] as Map<String, dynamic>? ?? {};
    final profJson = json['profile'] as Map<String, dynamic>? ?? {};
    final chalJson = json['active_challenge'] as Map<String, dynamic>?;
    final leagueJson = json['league'] as Map<String, dynamic>? ?? {};
    final personalJson = json['personal_progress'] as Map<String, dynamic>? ?? {};
    final questsJson = json['daily_quests'] as List<dynamic>? ?? [];
    final achsJson = json['achievements'] as List<dynamic>? ?? [];
    final wpJson = json['weekly_progress'] as Map<String, dynamic>?;

    return FlowOverview(
      companion: FlowCompanion.fromJson(compJson),
      profile: FlowProfile.fromJson(profJson),
      activeChallenge: chalJson != null ? FlowChallenge.fromJson(chalJson) : null,
      dailyQuests: questsJson
          .map((q) => FlowDailyQuest.fromJson(q as Map<String, dynamic>))
          .toList(),
      achievements: achsJson
          .map((a) => FlowAchievement.fromJson(a as Map<String, dynamic>))
          .toList(),
      weeklyProgress: wpJson != null ? FlowWeeklyProgress.fromJson(wpJson) : null,
      leagueTier: leagueJson['tier'] as String? ?? 'Bronze',
      weeklyFlowPoints: leagueJson['weekly_flow_points'] as int? ?? 0,
      leagueStatusMessage: leagueJson['status_message'] as String? ??
          'Focus on your rhythm. Cohort leagues open when participant quorum is reached.',
      personalBestFocusMinutes: personalJson['personal_best_focus_minutes'] as int? ?? 0,
      weeklyFocusSessions: personalJson['weekly_focus_sessions'] as int? ?? 0,
      weeklyFocusMinutes: personalJson['weekly_focus_minutes'] as int? ?? 0,
      totalFocusMinutes: personalJson['total_focus_minutes'] as int? ?? 0,
      totalSessionsCompleted: personalJson['total_sessions_completed'] as int? ?? 0,
      bestFocusDayMinutes: personalJson['best_focus_day_minutes'] as int? ?? 0,
      consistencyScore: personalJson['consistency_score'] as String? ?? 'Building',
      rhythmAcknowledgement: personalJson['rhythm_acknowledgement'] as String? ??
          'Start your first flow to build your rhythm with Noya. 🦊',
      activeSessionId: json['active_session_id'] as String?,
      notification: json['notification'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'companion': companion.toJson(),
      'profile': profile.toJson(),
      if (activeChallenge != null) 'active_challenge': activeChallenge!.toJson(),
      'daily_quests': dailyQuests.map((q) => q.toJson()).toList(),
      'achievements': achievements.map((a) => a.toJson()).toList(),
      if (weeklyProgress != null) 'weekly_progress': weeklyProgress!.toJson(),
      'league': {
        'tier': leagueTier,
        'weekly_flow_points': weeklyFlowPoints,
        'status_message': leagueStatusMessage,
      },
      'personal_progress': {
        'personal_best_focus_minutes': personalBestFocusMinutes,
        'weekly_focus_sessions': weeklyFocusSessions,
        'weekly_focus_minutes': weeklyFocusMinutes,
        'total_focus_minutes': totalFocusMinutes,
        'total_sessions_completed': totalSessionsCompleted,
        'best_focus_day_minutes': bestFocusDayMinutes,
        'consistency_score': consistencyScore,
        'rhythm_acknowledgement': rhythmAcknowledgement,
      },
      if (activeSessionId != null) 'active_session_id': activeSessionId,
      if (notification != null) 'notification': notification,
    };
  }
}
