import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../models/task_reflection.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'flow_day_path.dart';

/// "Completed today · N": the day's finished tasks, hidden from the active list and folded behind one button.
/// Expanding it shows each finished moment (most recent first) — what was done, when, and how it felt — and tapping a
/// moment opens its history. Renders nothing until something is finished today; a new day starts with nothing here,
/// while History keeps every finished task.
class TodaySoFar extends StatefulWidget {
  /// Start expanded (the default is collapsed: finished work stays out of the way until asked for).
  final bool initiallyExpanded;

  const TodaySoFar({super.key, this.initiallyExpanded = false});

  static ScheduleItem momentItem(TaskItem t) {
    final start = t.scheduledStart;
    return ScheduleItem(
      id: 'comp-${t.id}',
      taskId: t.id,
      time: start == null ? '' : DateFormat('h:mm').format(start),
      period: start == null ? '' : DateFormat('a').format(start),
      title: t.title,
      type: t.type,
      tagText: 'COMPLETED',
      isCompleted: true,
      durationMinutes: t.durationMinutes,
      startTime: start,
    );
  }

  @override
  State<TodaySoFar> createState() => _TodaySoFarState();
}

class _TodaySoFarState extends State<TodaySoFar> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final done = state.todayCompletion.completedToday;
    if (done.isEmpty) return const SizedBox.shrink();
    final muted = FlowColors.textSecondaryOf(context);

    return Column(
      key: const Key('today_so_far'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: 'Completed today, ${done.length}. ${_expanded ? 'Hide' : 'Show'} completed tasks',
          excludeSemantics: true,
          child: InkWell(
            key: const Key('completed_today_toggle'),
            borderRadius: FlowRadii.pillRadius,
            onTap: () {
              FlowHaptics.selection();
              setState(() => _expanded = !_expanded);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 16, color: FlowColors.successOf(context)),
                    const SizedBox(width: 6),
                    Text(
                      'Completed today · ${done.length}',
                      style: FlowTypography.labelMedium(color: muted).copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 2),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more_rounded, size: 18, color: muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_expanded
              ? const SizedBox(width: double.infinity)
              : Padding(
                  key: const Key('completed_today_list'),
                  padding: const EdgeInsets.only(top: 6),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final t in done)
                          _Moment(
                            key: Key('today_moment_${t.id}'),
                            task: t,
                            reflection: state.reflectionFor(t.id),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Moment extends StatelessWidget {
  final TaskItem task;
  final TaskReflection? reflection;

  const _Moment({super.key, required this.task, required this.reflection});

  @override
  Widget build(BuildContext context) {
    final at = reflection?.completedAt ?? task.completedAt;
    final meta = [
      if (at != null) DateFormat('h:mm a').format(at),
      if (reflection != null) TaskReflection.feelingLabel(reflection!.feeling),
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: [task.title, 'completed', if (meta.isNotEmpty) meta].join(', '),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: FlowRadii.chipRadius,
          onTap: () {
            FlowHaptics.selection();
            showHistoryMomentSheet(
              context,
              item: TodaySoFar.momentItem(task),
              reflection: reflection,
              completedAt: task.completedAt,
              category: task.category,
            );
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 56, maxWidth: 220),
            padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
            decoration: BoxDecoration(
              borderRadius: FlowRadii.chipRadius,
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: FlowColors.successOf(context), width: 1.5),
                  ),
                  child: Icon(Icons.check_rounded, size: 16, color: FlowColors.successOf(context)),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: FlowColors.textMutedOf(context),
                        ),
                      ),
                      if (meta.isNotEmpty) Text(meta, style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
