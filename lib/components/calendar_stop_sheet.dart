import 'package:flutter/material.dart';

import '../models/schedule_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'day_path/stop_emoji.dart';
import 'noya_notice.dart';

/// One action in the stop sheet. [run] returns the message to report (null: nothing to say), or throws.
class StopAction {
  final Key key;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Long-running actions (a server move) keep the sheet open with a spinner on the tile until they finish.
  final Future<void> Function() run;

  const StopAction({
    required this.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.run,
  });
}

/// The sheet a Calendar stop opens: what the stop is and what can be done with it.
///
/// Dismissible the usual ways: swipe down (anywhere on the sheet), the close button, the system back gesture, or a tap
/// outside. Its height follows its content (never a fixed height), scrolling only when a small screen needs it.
Future<void> showCalendarStopSheet(
  BuildContext context, {
  required ScheduleItem item,
  required String? category,
  required String? badge,
  required Color? badgeColor,
  required List<StopAction> actions,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    showDragHandle: false,
    useSafeArea: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge))),
    builder: (_) => _CalendarStopSheet(item: item, category: category, badge: badge, badgeColor: badgeColor, actions: actions),
  );
}

class _CalendarStopSheet extends StatefulWidget {
  final ScheduleItem item;
  final String? category;
  final String? badge;
  final Color? badgeColor;
  final List<StopAction> actions;

  const _CalendarStopSheet({
    required this.item,
    required this.category,
    required this.badge,
    required this.badgeColor,
    required this.actions,
  });

  @override
  State<_CalendarStopSheet> createState() => _CalendarStopSheetState();
}

class _CalendarStopSheetState extends State<_CalendarStopSheet> {
  Key? _running;

  Future<void> _run(StopAction a) async {
    if (_running != null) return; // one action at a time: a double tap never runs two
    setState(() => _running = a.key);
    try {
      await a.run();
      if (mounted) Navigator.of(context).maybePop();
    } catch (_) {
      NoyaNoticeCenter.instance.failure("Couldn't complete that action. Try again.");
      if (mounted) setState(() => _running = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final muted = FlowColors.textMutedOf(context);
    final time = '${item.time} ${item.period}'.trim();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    final accent = Theme.of(context).colorScheme.primary;
    return ConstrainedBox(
      key: const Key('calendar_stop_sheet'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // drag handle: the whole header is a grab area too
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Center(
              child: Container(
                key: const Key('calendar_stop_sheet_handle'),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: muted.withValues(alpha: 0.35), borderRadius: FlowRadii.pillRadius),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                  ),
                  child: Icon(stopIconFor(title: item.title, category: widget.category, type: item.type),
                      size: 22, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: [if (time.isNotEmpty) time, '${item.durationMinutes} min'].join(' · ')),
                          if (widget.badge != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: widget.badge,
                              style: TextStyle(color: widget.badgeColor, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ]),
                        style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('calendar_stop_sheet_close'),
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  color: muted,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in widget.actions)
                    ListTile(
                      key: a.key,
                      enabled: _running == null || _running == a.key,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: a.color.withValues(alpha: FlowColors.isDark(context) ? 0.15 : 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: _running == a.key
                            ? Padding(
                                padding: const EdgeInsets.all(11),
                                child: CircularProgressIndicator(strokeWidth: 2, color: a.color),
                              )
                            : Icon(a.icon, color: a.color, size: 20),
                      ),
                      title: Text(a.title,
                          style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context))
                              .copyWith(fontWeight: FontWeight.w600)),
                      subtitle: Text(a.subtitle, style: FlowTypography.bodySmall(color: muted)),
                      onTap: () {
                        FlowHaptics.selection();
                        _run(a);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Your day is a journey": the short explanation behind the Calendar title. Plain words, no tutorial.
Future<void> showCalendarLegendSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge))),
    builder: (context) {
      final primary = FlowColors.textPrimaryOf(context);
      final muted = FlowColors.textSecondaryOf(context);
      Widget row(Color color, String name, String text, {bool dot = false}) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: dot ? 14 : 28,
                  height: dot ? 14 : 6,
                  decoration: BoxDecoration(
                    color: dot ? null : color,
                    shape: dot ? BoxShape.circle : BoxShape.rectangle,
                    border: dot ? Border.all(color: color, width: 2.5) : null,
                    borderRadius: dot ? null : FlowRadii.pillRadius,
                  ),
                ),
                SizedBox(width: dot ? 26 : 12),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '$name  ', style: TextStyle(color: primary, fontWeight: FontWeight.w700)),
                      TextSpan(text: text),
                    ]),
                    style: FlowTypography.bodyMedium(color: muted),
                  ),
                ),
              ],
            ),
          );
      return SingleChildScrollView(
        key: const Key('calendar_legend_sheet'),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: FlowColors.textMutedOf(context).withValues(alpha: 0.35), borderRadius: FlowRadii.pillRadius),
              ),
            ),
            const SizedBox(height: 16),
            Text('Your day is a journey',
                style: FlowTypography.headlineMedium(color: primary).copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Each stop is a task, in the order of your day. The road shows how you actually travelled.',
                style: FlowTypography.bodyMedium(color: muted)),
            const SizedBox(height: 12),
            row(FlowColors.successOf(context), 'Green', 'the road you have completed'),
            row(Theme.of(context).colorScheme.primary, 'Blue', 'the road still ahead'),
            row(FlowColors.routeRecoveryOf(context), 'Orange', 'recovery: you changed course to go back to a stop'),
            row(FlowColors.routeSkippedOf(context), 'Skipped', 'you chose to bypass it', dot: true),
            row(FlowColors.routeSkippedOf(context), 'Auto-skipped', 'you finished the stops on both sides of it',
                dot: true),
            row(FlowColors.warningOf(context), 'Missed', 'its time passed without completion', dot: true),
            const SizedBox(height: 12),
            Text('Flowstate updates the road as your real day changes. You never have to mark anything just to move on.',
                style: FlowTypography.bodyMedium(color: primary)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const Key('calendar_legend_close'),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      );
    },
  );
}
