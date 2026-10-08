import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';
import 'noya_companion_view.dart';

/// What a notice is about. Noya's picture is used only where it carries meaning; everything else stays a plain
/// message so she keeps her weight.
enum NoticeKind {
  /// A nudge about something coming up. (In-app only for now: there is no OS push scheduling yet.)
  reminder,

  /// A daily or weekly quest just became claimable.
  questComplete,

  /// Level up, evolution, a new streak record, a Shield earned. Rare by construction.
  milestone,

  /// A meaningful action just worked (routine saved, plan confirmed, reward claimed).
  success,
}

class NoyaNotice {
  final NoticeKind kind;
  final String message;
  final String? title;
  const NoyaNotice(this.kind, this.message, {this.title});

  NoyaState get noya {
    switch (kind) {
      case NoticeKind.reminder:
        return NoyaState.encouraging;
      case NoticeKind.questComplete:
        return NoyaState.goodJob;
      case NoticeKind.milestone:
        return NoyaState.cheering;
      case NoticeKind.success:
        return NoyaState.proud;
    }
  }
}

/// Decides whether a notice gets Noya's picture. Milestones always do (they are rare and are the point of her);
/// everything else shares a cooldown, so a burst of small successes shows ONE Noya and then plain text.
class NoyaNoticePolicy {
  final Duration cooldown;
  DateTime? _lastNoya;
  NoyaNoticePolicy({this.cooldown = const Duration(seconds: 45)});

  bool useNoya(NoticeKind kind, DateTime now) {
    final bypass = kind == NoticeKind.milestone;
    final last = _lastNoya;
    if (!bypass && last != null && now.difference(last) < cooldown) return false;
    _lastNoya = now;
    return true;
  }

  void reset() => _lastNoya = null;
}

/// App-wide place to show a notice. The key is handed to MaterialApp so providers can notify without a BuildContext.
class NoyaNoticeCenter {
  NoyaNoticeCenter({NoyaNoticePolicy? policy, DateTime Function()? clock})
      : policy = policy ?? NoyaNoticePolicy(),
        _clock = clock ?? DateTime.now;

  static final NoyaNoticeCenter instance = NoyaNoticeCenter();

  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  final NoyaNoticePolicy policy;
  final DateTime Function() _clock;

  void show(NoyaNotice notice) {
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final withNoya = policy.useNoya(notice.kind, _clock());
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: const Key('noya_notice'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: notice.kind == NoticeKind.milestone ? 4 : 3),
        backgroundColor: FlowColors.surfaceElevated(messenger.context),
        content: Row(
          children: [
            if (withNoya) ...[
              NoyaCompanionView(state: notice.noya, size: 40),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice.title != null)
                    Text(notice.title!,
                        style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(messenger.context))
                            .copyWith(fontWeight: FontWeight.w700)),
                  Text(notice.message,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(messenger.context))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The one milestone worth announcing from a finished focus session (server response), or null. Priority:
/// evolution, level up, Shield earned, streak landmark. One notice, never a pile.
NoyaNotice? milestoneFromSession(Map<String, dynamic> res) {
  if (res['evolution_ready'] == true && res['leveled_up'] == true) {
    return NoyaNotice(NoticeKind.milestone, 'Noya is ready to evolve. Open the Flow Hub.',
        title: 'Level ${res['new_level']}!');
  }
  if (res['leveled_up'] == true) {
    return NoyaNotice(NoticeKind.milestone, 'Noya reached level ${res['new_level']}.', title: 'Level up');
  }
  if (res['shield_awarded'] == true) {
    return const NoyaNotice(NoticeKind.milestone, 'Seven days in a row earned you a Flow Shield.', title: 'Shield earned');
  }
  final streak = res['current_streak'];
  if (res['streak_incremented'] == true && streak is int && const {3, 7, 14, 30, 60, 100}.contains(streak)) {
    return NoyaNotice(NoticeKind.milestone, '$streak days in a row.', title: 'Streak');
  }
  return null;
}
