import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../models/task_reflection.dart';
import '../providers/app_state_provider.dart';
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'flow_day_path.dart';

/// "Today so far": the day's finished moments as calm history (most recent first) — what was
/// done, when, and how it felt, each marked with a quiet check. Tapping a moment
/// opens its history. Renders nothing until something is finished today.
class TodaySoFar extends StatelessWidget {
  const TodaySoFar({super.key});

  static bool _isToday(DateTime d, DateTime now) => d.year == now.year && d.month == now.month && d.day == now.day;

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
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final now = FlowClock().now;

    final done = state.tasks.where((t) {
      if (!t.isCompleted) return false;
      final when = state.reflectionFor(t.id)?.completedAt ?? t.completedAt ?? t.scheduledStart;
      return when != null && _isToday(when, now);
    }).toList()
      ..sort((a, b) {
        DateTime at(TaskItem t) => state.reflectionFor(t.id)?.completedAt ?? t.completedAt ?? t.scheduledStart!;
        return at(b).compareTo(at(a));
      });
    if (done.isEmpty) return const SizedBox.shrink();

    return Column(
      key: const Key('today_so_far'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Today so far',
          style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
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
