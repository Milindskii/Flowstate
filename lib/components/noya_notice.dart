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

  /// A meaningful action just worked (routine saved, plan confirmed, task completed).
  success,

  /// Something the user asked for did not happen ("Couldn't complete that action. Try again.").
  failure,

  /// The user received something: XP, Flow, a Shield ("Shield claimed! +1 🛡️").
  reward,

  /// Plain information about a change the app made ("Your day was replanned.").
  info,
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
      case NoticeKind.failure:
        return NoyaState.encouraging;
      case NoticeKind.reward:
        return NoyaState.cheering;
      case NoticeKind.info:
        return NoyaState.idle;
    }
  }

  /// Important events get the larger Noya card; trivial ones a small toast.
  bool get isImportant => kind == NoticeKind.milestone || kind == NoticeKind.reward || kind == NoticeKind.questComplete;

  /// Identical notices collapse: same kind, same words.
  String get dedupeKey => '${kind.name}|${title ?? ''}|$message';
}

/// Decides whether a notice gets Noya's picture. Milestones always do (they are rare and are the point of her);
/// everything else shares a cooldown, so a burst of small successes shows ONE Noya and then plain text.
class NoyaNoticePolicy {
  final Duration cooldown;
  DateTime? _lastNoya;
  NoyaNoticePolicy({this.cooldown = const Duration(seconds: 45)});

  bool useNoya(NoticeKind kind, DateTime now) {
    if (kind == NoticeKind.info || kind == NoticeKind.failure) return false; // plain words: Noya keeps her weight
    final bypass = kind == NoticeKind.milestone || kind == NoticeKind.reward;
    final last = _lastNoya;
    if (!bypass && last != null && now.difference(last) < cooldown) return false;
    _lastNoya = now;
    return true;
  }

  void reset() => _lastNoya = null;
}

/// THE app-wide feedback channel: every screen and provider reports an event here instead of building its own popup.
///
/// * success / failure / reward / milestone / info (see [NoticeKind]);
/// * important events (reward, milestone, quest) are a larger card with Noya; trivial ones a small toast;
/// * never blocks: a floating snack bar that leaves on its own;
/// * no spam: an identical notice inside [dedupeWindow] is dropped, and within [coalesceWindow] a new notice replaces the
///   one on screen instead of stacking; a milestone always shows (it overrides the suppression).
///
/// The key is handed to MaterialApp so providers can notify without a BuildContext.
class NoyaNoticeCenter {
  NoyaNoticeCenter({NoyaNoticePolicy? policy, DateTime Function()? clock})
      : policy = policy ?? NoyaNoticePolicy(),
        _clock = clock ?? DateTime.now;

  static final NoyaNoticeCenter instance = NoyaNoticeCenter();

  static const Duration dedupeWindow = Duration(seconds: 4);
  static const Duration coalesceWindow = Duration(milliseconds: 1500);

  final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey<ScaffoldMessengerState>();
  final NoyaNoticePolicy policy;
  final DateTime Function() _clock;

  String? _lastKey;
  DateTime? _lastAt;
  NoticeKind? _lastKind;

  /// Every notice actually shown, oldest first (tests and diagnostics read it; capped).
  final List<NoyaNotice> shown = [];

  /// Whether [notice] should be shown now (and, if so, records it). Pure decision + bookkeeping, no UI.
  bool admit(NoyaNotice notice) {
    final now = _clock();
    final last = _lastAt;
    if (last != null && notice.kind != NoticeKind.milestone) {
      final since = now.difference(last);
      if (notice.dedupeKey == _lastKey && since < dedupeWindow) return false; // the same thing twice: once
      // a trivial notice never pushes an important one off the screen right after it appeared
      final onScreenImportant = _lastKind == NoticeKind.milestone || _lastKind == NoticeKind.reward;
      if (onScreenImportant && !notice.isImportant && since < coalesceWindow) return false;
    }
    _lastKey = notice.dedupeKey;
    _lastAt = now;
    _lastKind = notice.kind;
    shown.add(notice);
    if (shown.length > 50) shown.removeAt(0);
    return true;
  }

  void success(String message, {String? title}) => show(NoyaNotice(NoticeKind.success, message, title: title));
  void failure(String message, {String? title}) => show(NoyaNotice(NoticeKind.failure, message, title: title));
  void reward(String message, {String? title}) => show(NoyaNotice(NoticeKind.reward, message, title: title));
  void milestone(String message, {String? title}) => show(NoyaNotice(NoticeKind.milestone, message, title: title));
  void info(String message, {String? title}) => show(NoyaNotice(NoticeKind.info, message, title: title));

  void show(NoyaNotice notice) {
    if (!admit(notice)) return;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;
    final withNoya = policy.useNoya(notice.kind, _clock());
    final ctx = messenger.context;
    final important = notice.isImportant;
    final failure = notice.kind == NoticeKind.failure;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        key: Key(important ? 'noya_notice_card' : 'noya_notice'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: important ? 4 : 3),
        backgroundColor: FlowColors.surfaceElevated(ctx),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: important ? 14 : 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(important ? 20 : 14),
          side: failure ? BorderSide(color: FlowColors.errorOf(ctx).withValues(alpha: 0.5)) : BorderSide.none,
        ),
        content: Row(
          children: [
            if (withNoya) ...[
              NoyaCompanionView(state: notice.noya, size: important ? 52 : 36),
              const SizedBox(width: 12),
            ] else if (failure) ...[
              Icon(Icons.error_outline_rounded, size: 20, color: FlowColors.errorOf(ctx)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notice.title != null)
                    Text(notice.title!,
                        style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(ctx))
                            .copyWith(fontWeight: FontWeight.w700)),
                  Text(notice.message,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(ctx))),
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
