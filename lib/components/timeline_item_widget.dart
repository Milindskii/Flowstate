import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_item.dart';
import '../providers/theme_provider.dart';
import 'flow_completion_check.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Display state of one timeline row. At most one indicator is shown per row.
enum TimelineRowState { normal, now, fixed, conflict, missed, suggested, completed, unscheduled }

/// Precedence: completed > unscheduled > conflict > fixed > missed > suggested > now > normal.
TimelineRowState timelineRowStateOf(ScheduleItem item, {required bool isNow, bool isUnscheduled = false}) {
  if (item.isCompleted || item.tagText == 'COMPLETED') return TimelineRowState.completed;
  if (isUnscheduled) return TimelineRowState.unscheduled;
  if (item.isConflict || item.tagText == 'CONFLICT') return TimelineRowState.conflict;
  if (item.isFixed || item.tagText == 'FIXED') return TimelineRowState.fixed;
  if (item.isMissed) return TimelineRowState.missed;
  if (item.isSuggested) return TimelineRowState.suggested;
  if (isNow) return TimelineRowState.now;
  return TimelineRowState.normal;
}

/// Shared timeline row for Calendar and Today (spec B2.4).
///
/// Anatomy: a time gutter on one vertical axis, a 2 px rail with a state node, then the title,
/// one muted meta line, at most one state indicator (icon + sentence-case label) and a reason
/// line only for actionable states. Default rows carry no badge and no container; the NOW row
/// alone gets a 6% accent fill.
class FlowTimelineRow extends StatelessWidget {
  final ScheduleItem item;
  final bool isNow;
  final bool isLast;
  final bool showTimeGutter;

  /// Row belongs to the "Couldn't fit" section rather than the timeline.
  final bool isUnscheduled;

  /// Row starts inside the day's focus window: the rail segment is accent-tinted (B2.3).
  final bool inFocusWindow;

  /// Vertical space after the row; the rail continues through it.
  final double spacing;

  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onStart;
  final VoidCallback? onDoThisNow;

  const FlowTimelineRow({
    super.key,
    required this.item,
    this.isNow = false,
    this.isLast = false,
    this.showTimeGutter = true,
    this.isUnscheduled = false,
    this.inFocusWindow = false,
    this.spacing = 10,
    this.onTap,
    this.onComplete,
    this.onStart,
    this.onDoThisNow,
  });

  static const double _minGutter = 64;
  static const double _gutterGap = 10;
  static const double _railColumn = 18;
  static const double _node = 10;
  static const double _nodeTop = 8;

  static String labelOf(TimelineRowState state) {
    switch (state) {
      case TimelineRowState.normal:
        return 'Scheduled';
      case TimelineRowState.now:
        return 'Now';
      case TimelineRowState.fixed:
        return 'Fixed';
      case TimelineRowState.conflict:
        return 'Conflict';
      case TimelineRowState.missed:
        return 'Missed';
      case TimelineRowState.suggested:
        return 'Suggested';
      case TimelineRowState.completed:
        return 'Completed';
      case TimelineRowState.unscheduled:
        return 'Unscheduled';
    }
  }

  static IconData? _iconOf(TimelineRowState state) {
    switch (state) {
      case TimelineRowState.now:
        return Icons.adjust_rounded;
      case TimelineRowState.fixed:
        return Icons.lock_rounded;
      case TimelineRowState.conflict:
        return Icons.error_outline_rounded;
      case TimelineRowState.missed:
        return Icons.history_rounded;
      case TimelineRowState.suggested:
        return Icons.lightbulb_outline_rounded;
      case TimelineRowState.unscheduled:
        return Icons.event_busy_rounded;
      case TimelineRowState.normal:
      case TimelineRowState.completed:
        return null;
    }
  }

  static TextStyle _timeStyle(BuildContext context) => FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context))
      .copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]);

  static TextStyle _periodStyle(BuildContext context) =>
      FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontWeight: FontWeight.w600);

  /// Gutter width from text metrics (B2.7): wide enough for "12:00 PM" at the current text
  /// scale, never below 64 dp, and identical on every row so titles share one axis.
  static double gutterWidthOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final period = math.max(measure('AM', _periodStyle(context)), measure('PM', _periodStyle(context)));
    return math.max(_minGutter, measure('12:00', _timeStyle(context)) + 3 + period).ceilToDouble();
  }

  static String _typeLabel(String raw) {
    final text = raw.replaceAll('_', ' ').trim();
    if (text.isEmpty) return '';
    return text[0].toUpperCase() + text.substring(1);
  }

  Color _accent(BuildContext context) {
    try {
      return Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {
      return Theme.of(context).colorScheme.primary;
    }
  }

  Color _stateColor(BuildContext context, TimelineRowState state, Color accent) {
    switch (state) {
      case TimelineRowState.conflict:
        return FlowColors.errorOf(context);
      case TimelineRowState.missed:
      case TimelineRowState.unscheduled:
        return FlowColors.warningOf(context);
      case TimelineRowState.fixed:
      case TimelineRowState.completed:
        return FlowColors.textSecondaryOf(context);
      case TimelineRowState.now:
      case TimelineRowState.suggested:
      case TimelineRowState.normal:
        return accent;
    }
  }

  String? _reasonOf(TimelineRowState state) {
    switch (state) {
      case TimelineRowState.now:
        return item.explanation ?? 'Peak energy focus window';
      case TimelineRowState.conflict:
        return item.explanation ?? 'Conflict with scheduled commitment';
      case TimelineRowState.missed:
        return 'This time has passed. Replan my day to move it.';
      case TimelineRowState.suggested:
        return 'Suggested time — not saved. Edit or replan to confirm.';
      case TimelineRowState.unscheduled:
        return item.explanation ?? 'Could not be fitted into schedule';
      case TimelineRowState.normal:
      case TimelineRowState.fixed:
      case TimelineRowState.completed:
        return isNow ? (item.explanation ?? 'Peak energy focus window') : null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context);
    final state = timelineRowStateOf(item, isNow: isNow, isUnscheduled: isUnscheduled);
    final isDone = state == TimelineRowState.completed;
    final stateColor = _stateColor(context, state, accent);
    final gutterWidth = showTimeGutter ? gutterWidthOf(context) : 0.0;
    final railColor = inFocusWindow ? accent.withValues(alpha: 0.45) : FlowColors.divider(context);
    final showRail = showTimeGutter;
    final reason = _reasonOf(state);
    final typeLabel = _typeLabel(item.type);
    final meta = showTimeGutter
        ? typeLabel
        : [('${item.durationMinutes} min'), if (typeLabel.isNotEmpty) typeLabel].join(' · ');

    final semanticsLabel = [
      item.title,
      if (showTimeGutter) '${item.time} ${item.period}'.trim(),
      '${item.durationMinutes} minutes',
      labelOf(state),
    ].join(', ');

    // Node on the rail: a check for completed, a ring for NOW, a dot otherwise.
    final Widget node = isDone
        ? SizedBox(
            key: Key('timeline_state_completed_${item.id}'),
            child: Icon(Icons.check_circle_rounded, size: 16, color: FlowColors.textMutedOf(context)),
          )
        : Container(
            width: _node,
            height: _node,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNow ? FlowColors.surface(context) : stateColor,
              border: isNow ? Border.all(color: accent, width: 2.5) : null,
            ),
          );

    final rail = SizedBox(
      width: _railColumn,
      child: Column(
        children: [
          Container(width: 2, height: _nodeTop + (isDone ? -3 : 0), color: showRail ? railColor : Colors.transparent),
          SizedBox(height: isDone ? 16 : _node, child: Center(child: node)),
          Expanded(
            child: Container(width: 2, color: showRail && !isLast ? railColor : Colors.transparent),
          ),
        ],
      ),
    );

    final indicatorIcon = _iconOf(state);
    final indicatorText = state == TimelineRowState.now ? 'NOW' : labelOf(state);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Completion settles over 220 ms (§8.2): the strike-through fades in and the title
        // color eases to muted.
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isDone ? 1.0 : 0.0),
          duration: FlowMotion.responsiveDuration(context, FlowMotion.standardDuration),
          curve: FlowMotion.easeOut,
          builder: (context, t, _) {
            final muted = FlowColors.textMutedOf(context);
            return Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FlowTypography.bodyLarge(
                color: Color.lerp(FlowColors.textPrimaryOf(context), muted, t),
              ).copyWith(
                fontWeight: FontWeight.w600,
                height: 1.35,
                decoration: t > 0 ? TextDecoration.lineThrough : null,
                decorationColor: t > 0 ? muted.withValues(alpha: muted.a * t) : null,
              ),
            );
          },
        ),
        if (meta.isNotEmpty)
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
          ),
        if (indicatorIcon != null) ...[
          const SizedBox(height: 4),
          Row(
            key: Key('timeline_state_${state.name}_${item.id}'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(indicatorIcon, size: 16, color: stateColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  indicatorText,
                  style: FlowTypography.labelSmall(color: stateColor).copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: state == TimelineRowState.now ? 1.2 : null,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (reason != null) ...[
          const SizedBox(height: 2),
          Text(
            reason,
            key: Key('timeline_reason_${item.id}'),
            style: FlowTypography.bodySmall(
              color: state == TimelineRowState.conflict ? FlowColors.errorOf(context) : FlowColors.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );

    // Height eases to the completed height (§8.2). Under reduced motion the change is instant;
    // a zero-duration AnimatedSize would re-dirty itself during layout.
    final body = _rowBody(context, accent, isDone, content, rail, gutterWidth);
    final row = FlowMotion.isReducedMotion(context)
        ? body
        : AnimatedSize(
            duration: FlowMotion.standardDuration,
            curve: FlowMotion.easeInOut,
            alignment: Alignment.topCenter,
            child: body,
          );

    return Semantics(
      container: true,
      label: semanticsLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          SizedBox(
            height: spacing,
            child: showRail && !isLast
                ? Padding(
                    padding: EdgeInsets.only(left: gutterWidth + _gutterGap - 6 + (_railColumn - 2) / 2),
                    child: Align(alignment: Alignment.centerLeft, child: Container(width: 2, color: railColor)),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _rowBody(BuildContext context, Color accent, bool isDone, Widget content, Widget rail, double gutterWidth) {
    return Container(
      key: Key('timeline_row_${item.id}'),
      decoration: isNow
          ? BoxDecoration(color: accent.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(FlowRadii.chip))
          : null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlowRadii.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Actions get whatever width is left once the gutter, rail and a readable
                // title column are reserved; lower-priority actions drop first.
                final reserved = (showTimeGutter ? gutterWidth + _gutterGap - 6 : 0) + _railColumn + 8 + 96;
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ExcludeSemantics(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (showTimeGutter)
                                SizedBox(
                                  width: gutterWidth,
                                  child: _Gutter(item: item, timeStyle: _timeStyle(context), periodStyle: _periodStyle(context)),
                                ),
                              if (showTimeGutter) const SizedBox(width: _gutterGap - 6),
                              rail,
                              const SizedBox(width: 8),
                              Expanded(child: content),
                            ],
                          ),
                        ),
                      ),
                      if (!isDone)
                        _Actions(
                          item: item,
                          accent: accent,
                          budget: constraints.maxWidth - reserved,
                          onComplete: onComplete,
                          onStart: onStart,
                          onDoThisNow: onDoThisNow,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  final ScheduleItem item;
  final TextStyle timeStyle;
  final TextStyle periodStyle;

  const _Gutter({required this.item, required this.timeStyle, required this.periodStyle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(item.time, style: timeStyle),
            if (item.period.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(item.period, style: periodStyle),
            ],
          ],
        ),
        Text(
          '${item.durationMinutes} min',
          style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
        ),
      ],
    );
  }
}

/// Today's row actions. Calendar passes no callbacks, so its rows stay action-free.
///
/// Each action is a 40 dp target. Completion has priority, then Start, then the "⋯" menu
/// holding "Do this now"; an action is dropped when [budget] cannot fit it.
class _Actions extends StatelessWidget {
  final ScheduleItem item;
  final Color accent;
  final double budget;
  final VoidCallback? onComplete;
  final VoidCallback? onStart;
  final VoidCallback? onDoThisNow;

  const _Actions({
    required this.item,
    required this.accent,
    required this.budget,
    this.onComplete,
    this.onStart,
    this.onDoThisNow,
  });

  static const double _target = 40;
  static const double _checkTarget = 48;

  @override
  Widget build(BuildContext context) {
    var room = budget;
    bool fits(double width) {
      if (room < width) return false;
      room -= width;
      return true;
    }

    final showComplete = onComplete != null && fits(_checkTarget);
    final showStart = onStart != null && fits(_target);
    final showMore = onDoThisNow != null && fits(_target);
    if (!showComplete && !showStart && !showMore) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showMore)
          SizedBox(
            width: _target,
            height: _target,
            child: PopupMenuButton<String>(
              tooltip: 'More actions for ${item.title}',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz_rounded, size: 20, color: FlowColors.textMutedOf(context)),
              onSelected: (_) {
                FlowHaptics.selection();
                onDoThisNow?.call();
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'do_now',
                  child: Semantics(
                    label: 'Make ${item.title} current task',
                    excludeSemantics: true,
                    child: const Text('Do this now'),
                  ),
                ),
              ],
            ),
          ),
        if (showStart)
          _target40(
            label: 'Start focus on ${item.title}',
            onTap: () {
              FlowHaptics.lightTap();
              onStart?.call();
            },
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(Icons.play_arrow_rounded, size: 16, color: accent),
            ),
          ),
        if (showComplete)
          // FlowCompletionCheck plays the success haptic itself.
          FlowCompletionCheck(
            completed: false,
            size: 22,
            label: 'Mark ${item.title} as done',
            onToggle: onComplete,
          ),
      ],
    );
  }

  Widget _target40({required String label, required VoidCallback onTap, required Widget child}) {
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(width: _target, height: _target, child: Center(child: child)),
      ),
    );
  }
}
