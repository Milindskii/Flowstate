/// Lightweight, progress-driven daily quest model.
/// Progress accumulates automatically on real productivity events.
/// User explicitly claims the reward once completed.
class FlowDailyQuest {
  final String id;
  final String questDate;
  final String questKey;
  final String title;
  final String description;
  final int targetCount;
  final int currentCount;
  final int rewardFlow;
  final bool isCompleted;
  final bool isClaimed;

  const FlowDailyQuest({
    required this.id,
    required this.questDate,
    required this.questKey,
    required this.title,
    required this.description,
    required this.targetCount,
    required this.currentCount,
    required this.rewardFlow,
    required this.isCompleted,
    required this.isClaimed,
  });

  double get progressFraction =>
      targetCount > 0 ? (currentCount / targetCount).clamp(0.0, 1.0) : 0.0;

  String get progressLabel => '$currentCount / $targetCount';

  factory FlowDailyQuest.fromJson(Map<String, dynamic> json) {
    return FlowDailyQuest(
      id: json['id'] as String? ?? '',
      questDate: json['quest_date'] as String? ?? '',
      questKey: json['quest_key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      targetCount: json['target_count'] as int? ?? 1,
      currentCount: json['current_count'] as int? ?? 0,
      rewardFlow: json['reward_flow'] as int? ?? 15,
      isCompleted: json['is_completed'] as bool? ?? false,
      isClaimed: json['is_claimed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'quest_date': questDate,
        'quest_key': questKey,
        'title': title,
        'description': description,
        'target_count': targetCount,
        'current_count': currentCount,
        'reward_flow': rewardFlow,
        'is_completed': isCompleted,
        'is_claimed': isClaimed,
      };
}
