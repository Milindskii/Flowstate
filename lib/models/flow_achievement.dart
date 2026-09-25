/// Meaningful milestone achievement model.
class FlowAchievement {
  final String id;
  final String achievementKey;
  final String title;
  final String description;
  final String icon;
  final int rewardFlow;
  final bool isUnlocked;
  final DateTime? unlockedAt;

  const FlowAchievement({
    required this.id,
    required this.achievementKey,
    required this.title,
    required this.description,
    required this.icon,
    required this.rewardFlow,
    required this.isUnlocked,
    this.unlockedAt,
  });

  factory FlowAchievement.fromJson(Map<String, dynamic> json) {
    return FlowAchievement(
      id: json['id'] as String? ?? '',
      achievementKey: json['achievement_key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      icon: json['icon'] as String? ?? 'star',
      rewardFlow: json['reward_flow'] as int? ?? 25,
      isUnlocked: json['is_unlocked'] as bool? ?? false,
      unlockedAt: json['unlocked_at'] != null
          ? DateTime.tryParse(json['unlocked_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'achievement_key': achievementKey,
        'title': title,
        'description': description,
        'icon': icon,
        'reward_flow': rewardFlow,
        'is_unlocked': isUnlocked,
        'unlocked_at': unlockedAt?.toIso8601String(),
      };
}
