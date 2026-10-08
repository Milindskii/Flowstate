import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/flow_companion.dart';
import 'package:flowstate/models/flow_overview.dart';

Map<String, dynamic> _quest(String type, int cur, int target, {bool done = false, bool claimed = false}) => {
      'id': 'q-$type',
      'week_identifier': '2026-W41',
      'title': type,
      'target_count': target,
      'current_count': cur,
      'reward_flow': 60,
      'is_completed': done,
      'is_claimed': claimed,
      'challenge_type': type,
    };

void main() {
  test('overview carries all weekly quests and restores them from the cache JSON', () {
    final ov = FlowOverview.fromJson({
      'companion': {'id': 'c', 'species': 'fox', 'name': 'Noya', 'level': 1, 'stage': 'Baby'},
      'profile': {'user_id': 'u'},
      'active_challenge': _quest('priority_tasks', 1, 5),
      'weekly_quests': [
        _quest('priority_tasks', 1, 5),
        _quest('focus_sessions', 4, 4, done: true),
        _quest('focus_minutes', 120, 120, done: true, claimed: true),
      ],
    });
    expect(ov.weeklyQuests.map((q) => q.challengeType), ['priority_tasks', 'focus_sessions', 'focus_minutes']);
    final restored = FlowOverview.fromJson(ov.toJson());
    expect(restored.weeklyQuests, hasLength(3));
    expect(restored.weeklyQuests[1].isCompleted, isTrue);
    expect(restored.weeklyQuests[2].isClaimed, isTrue);
  });

  test('an older server without weekly_quests still shows the single challenge', () {
    final ov = FlowOverview.fromJson({
      'companion': {'id': 'c', 'species': 'fox', 'name': 'Noya', 'level': 1, 'stage': 'Baby'},
      'profile': {'user_id': 'u'},
      'active_challenge': _quest('priority_tasks', 0, 5),
    });
    expect(ov.weeklyQuests, isEmpty);
    expect(ov.activeChallenge, isNotNull);
  });

  test('level 100 is Super Noya with a full bar and no next level', () {
    final c = FlowCompanion.fromJson({
      'id': 'c', 'species': 'fox', 'name': 'Noya', 'level': 100, 'stage': 'Super',
      'companion_xp': 999999, 'xp_to_next_level': 0,
    });
    expect(c.isMaxLevel, isTrue);
    expect(c.progressFraction, 1.0);
    expect(c.stage, 'Super');
    final baby = FlowCompanion.fromJson({'id': 'c', 'species': 'fox', 'name': 'Noya', 'level': 1, 'stage': 'Baby'});
    expect(baby.isMaxLevel, isFalse);
    expect(baby.stage, 'Baby');
  });
}
