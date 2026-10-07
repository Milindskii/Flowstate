import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import 'flow_completion_check.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'edit_task_sheet.dart';
import 'noya_companion_view.dart';
import 'reschedule_task_sheet.dart';
import '../core/focus_navigation.dart';

/// Screen 5 Task Card matching mobile layout
class TaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onToggleComplete;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggleComplete,
    this.onTap,
    this.onMoreTap,
  });

  /// One quiet line of metadata; "Priority not specified" is noise, so only real priorities show.
  /// Duration is not here: it sits on the right as the row's one number.
  List<String> get _metaParts {
    return <String>[
      task.difficulty.label,
      if (task.isPriorityExplicit && task.priority != null)
        '${task.priority!.value[0].toUpperCase()}${task.priority!.value.substring(1)} priority'
      else if (task.isPriorityInferred && task.priority != null)
        'Suggested ${task.priority!.value}',
      if (task.category.isNotEmpty) task.category,
    ];
  }

  /// Deadlines that need attention today read in the warning colour; the rest stay quiet.
  bool get _deadlineIsUrgent {
    final d = task.deadline.toLowerCase();
    return d.contains('overdue') || d == 'due today' || d == 'tonight';
  }

  String? get _deadlineText => task.deadline.isNotEmpty && task.deadline != 'Today' ? task.deadline : null;

  /// Focus demand as 1–3 short bars (light → high). Physical work has its own kind of effort and
  /// gets none.
  int get _focusLevel {
    switch (task.difficulty) {
      case TaskDifficulty.high:
        return 3;
      case TaskDifficulty.medium:
        return 2;
      case TaskDifficulty.light:
        return 1;
      case TaskDifficulty.physical:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final done = task.isCompleted;
    final active = !done && task.status == TaskStatus.inProgress;

    // Upcoming: a light outline. In progress: accent tint. Completed: unboxed history.
    final BoxDecoration decoration;
    if (done) {
      decoration = const BoxDecoration(borderRadius: FlowRadii.cardRadius);
    } else if (active) {
      decoration = BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.2),
      );
    } else {
      // Opaque surface: a translucent fill over the ambient wash read as muddy grey.
      decoration = BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      );
    }

    return Container(
      key: Key('task_card_${task.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Animated check (§8.2); plays success / light haptics itself.
                FlowCompletionCheck(
                  completed: done,
                  size: 24,
                  onToggle: onToggleComplete,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (active)
                          Text(
                            'In progress',
                            style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w800),
                          ),
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FlowTypography.bodyLarge(
                            color: done ? FlowColors.textMutedOf(context) : FlowColors.textPrimaryOf(context),
                          ).copyWith(
                            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                            height: 1.3,
                            decoration: done ? TextDecoration.lineThrough : null,
                            decorationColor: FlowColors.textMutedOf(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Builder(
                          builder: (context) {
                            final showPriorityDot = (task.priority != null && task.priority != TaskPriority.medium) || task.isPriority;
                            final hasUrgentDeadline = !done && _deadlineIsUrgent;
                            if (!showPriorityDot && !hasUrgentDeadline) {
                              final fullMeta = [
                                ..._metaParts,
                                if (_deadlineText != null) _deadlineText!,
                              ].join(' · ');
                              return Text(
                                fullMeta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                              );
                            }
                            return Text.rich(
                              TextSpan(children: [
                                if (showPriorityDot)
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: FlowColors.priorityColorOf(context, task.priority, isPriority: task.isPriority),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                TextSpan(text: _metaParts.join(' · ')),
                                if (_deadlineText != null) ...[
                                  const TextSpan(text: ' · '),
                                  TextSpan(
                                    text: _deadlineText,
                                    style: hasUrgentDeadline
                                        ? TextStyle(color: FlowColors.warningOf(context), fontWeight: FontWeight.w700)
                                        : null,
                                  ),
                                ],
                              ]),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // The row's one number: how long it takes, with its focus demand underneath.
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.isDurationExplicit ? '${task.durationMinutes} min' : '~${task.durationMinutes} min',
                        key: Key('task_card_duration_${task.id}'),
                        style: FlowTypography.labelLarge(
                          color: done ? FlowColors.textMutedOf(context) : FlowColors.textPrimaryOf(context),
                        ).copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      if (_focusLevel > 0 && !done) ...[
                        const SizedBox(height: 5),
                        Semantics(
                          label: task.difficulty.label,
                          excludeSemantics: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var i = 1; i <= 3; i++)
                                Container(
                                  width: 8,
                                  height: 3,
                                  margin: EdgeInsets.only(left: i == 1 ? 0 : 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    color: i <= _focusLevel ? accent : FlowColors.border(context),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Noya only where her pose says something: the one task in focus right now. Finished
                // tasks are calm history — repeating her on every one would be decoration.
                if (active)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: NoyaCompanionView(state: NoyaState.focusing, size: NoyaSize.small),
                  ),
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded, size: 22),
                  color: FlowColors.textMutedOf(context),
                  tooltip: 'Task options',
                  onPressed: () {
                    if (onMoreTap != null) {
                      onMoreTap!();
                    } else {
                      _showTaskOptionsMenu(context);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTaskOptionsMenu(BuildContext context) {
    FlowHaptics.lightTap();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FlowColors.border(sheetContext),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Task Context Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.title,
                            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(sheetContext)).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                task.category,
                                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(sheetContext)),
                              ),
                              if (task.durationMinutes > 0) ...[
                                Text(
                                  ' · ${task.durationMinutes} min',
                                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(sheetContext)),
                                ),
                              ],
                              if (task.isCompleted) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: FlowColors.successOf(sheetContext).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(FlowRadii.pill),
                                  ),
                                  child: Text(
                                    'COMPLETED',
                                    style: FlowTypography.badgeText(color: FlowColors.successOf(sheetContext)).copyWith(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: FlowColors.textMutedOf(sheetContext),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: FlowColors.border(sheetContext), height: 1),
                const SizedBox(height: 8),

                // Action 1: Start Focus Session
                if (!task.isCompleted)
                  _buildOptionTile(
                    sheetContext,
                    icon: Icons.play_arrow_rounded,
                    iconColor: FlowColors.accentCyan,
                    title: 'Start Focus Session',
                    subtitle: 'Enter deep work mode with this task',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      openFocusRitual(context, task: task);
                    },
                  ),

                // Action 2: Toggle Complete
                _buildOptionTile(
                  sheetContext,
                  icon: task.isCompleted ? Icons.undo_rounded : Icons.check_circle_rounded,
                  iconColor: task.isCompleted ? FlowColors.textSecondaryOf(sheetContext) : FlowColors.mint,
                  title: task.isCompleted ? 'Mark as Incomplete' : 'Mark as Done',
                  subtitle: task.isCompleted ? 'Move back to active tasks' : 'Complete and record focus stats',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onToggleComplete();
                  },
                ),

                // Action 3: Edit Task
                _buildOptionTile(
                  sheetContext,
                  icon: Icons.edit_outlined,
                  iconColor: FlowColors.textPrimaryOf(sheetContext),
                  title: 'Edit Task',
                  subtitle: 'Change title, date, time, duration, or priority',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    EditTaskSheet.show(context, task);
                  },
                ),

                // Action 4: Reschedule / Move to Later
                _buildOptionTile(
                  sheetContext,
                  icon: Icons.schedule_rounded,
                  iconColor: FlowColors.warning,
                  title: 'Reschedule / Later',
                  subtitle: 'Move to tomorrow, tonight, or custom date',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    RescheduleTaskSheet.show(context, task);
                  },
                ),

                const SizedBox(height: 6),
                Divider(color: FlowColors.border(sheetContext), height: 1),
                const SizedBox(height: 8),

                // Destructive Section: Delete Task (Clearly distinguishable with danger styling & confirmation)
                Container(
                  decoration: BoxDecoration(
                    color: FlowColors.error.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(FlowRadii.card),
                    border: Border.all(color: FlowColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                      leading: const Icon(Icons.delete_outline_rounded, color: FlowColors.error, size: 22),
                      title: Text(
                        'Delete Task',
                        style: FlowTypography.bodyLarge(color: FlowColors.error).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Permanently remove this task',
                        style: FlowTypography.bodySmall(color: FlowColors.error.withValues(alpha: 0.8)),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.card)),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _confirmAndDeleteTask(context);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(FlowRadii.button),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.card)),
      onTap: () {
        FlowHaptics.lightTap();
        onTap();
      },
    );
  }

  void _confirmAndDeleteTask(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: FlowColors.surfaceElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: FlowColors.error, size: 24),
            const SizedBox(width: 8),
            Text(
              'Delete Task?',
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${task.title}"? This action cannot be undone.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: FlowTypography.labelLarge(color: FlowColors.textSecondaryOf(context)),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              FlowHaptics.selection();
              final appState = Provider.of<AppStateProvider>(context, listen: false);
              appState.removeTask(task.id);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Task "${task.title}" deleted.'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: FlowColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
