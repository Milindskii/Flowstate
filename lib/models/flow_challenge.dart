/// Flow Weekly Challenge Model
class FlowChallenge {
  final String id;
  final String weekIdentifier;
  final String title;
  final int targetCount;
  final int currentCount;
  final int rewardFlow;

  /// Shields the quest pays on claim (server-owned; 0 for most quests).
  final int rewardShields;
  final bool isCompleted;
  final bool isClaimed;
  final String challengeType;

  const FlowChallenge({
    required this.id,
    required this.weekIdentifier,
    this.title = 'Complete 5 priority tasks',
    this.targetCount = 5,
    this.currentCount = 0,
    this.rewardFlow = 100,
    this.rewardShields = 0,
    this.isCompleted = false,
    this.isClaimed = false,
    this.challengeType = 'priority_tasks',
  });

  double get progressFraction {
    if (targetCount <= 0) return 1.0;
    return (currentCount / targetCount).clamp(0.0, 1.0);
  }

  String get progressLabel => '$currentCount / $targetCount';

  FlowChallenge copyWith({
    String? id,
    String? weekIdentifier,
    String? title,
    int? targetCount,
    int? currentCount,
    int? rewardFlow,
    int? rewardShields,
    bool? isCompleted,
    bool? isClaimed,
    String? challengeType,
  }) {
    return FlowChallenge(
      id: id ?? this.id,
      weekIdentifier: weekIdentifier ?? this.weekIdentifier,
      title: title ?? this.title,
      targetCount: targetCount ?? this.targetCount,
      currentCount: currentCount ?? this.currentCount,
      rewardFlow: rewardFlow ?? this.rewardFlow,
      rewardShields: rewardShields ?? this.rewardShields,
      isCompleted: isCompleted ?? this.isCompleted,
      isClaimed: isClaimed ?? this.isClaimed,
      challengeType: challengeType ?? this.challengeType,
    );
  }

  factory FlowChallenge.fromJson(Map<String, dynamic> json) {
    return FlowChallenge(
      id: json['id'] as String? ?? 'challenge-default',
      weekIdentifier: json['week_identifier'] as String? ?? '',
      title: json['title'] as String? ?? 'Complete 5 priority tasks',
      targetCount: json['target_count'] as int? ?? 5,
      currentCount: json['current_count'] as int? ?? 0,
      rewardFlow: json['reward_flow'] as int? ?? 100,
      rewardShields: json['reward_shields'] as int? ?? 0,
      isCompleted: json['is_completed'] as bool? ?? false,
      isClaimed: json['is_claimed'] as bool? ?? false,
      challengeType: json['challenge_type'] as String? ?? 'priority_tasks',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'week_identifier': weekIdentifier,
      'title': title,
      'target_count': targetCount,
      'current_count': currentCount,
      'reward_flow': rewardFlow,
      'reward_shields': rewardShields,
      'is_completed': isCompleted,
      'is_claimed': isClaimed,
      'challenge_type': challengeType,
    };
  }
}
