import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 5 Task Card matching mobile layout
class TaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onToggleComplete;
  final VoidCallback? onTap;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggleComplete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: task.isCompleted ? FlowColors.mint.withOpacity(0.3) : FlowColors.darkBorder,
          width: 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top: Title and Menu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: FlowTypography.titleMedium().copyWith(
                          fontWeight: FontWeight.w700,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? FlowColors.textMuted : FlowColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.more_horiz_rounded,
                      color: FlowColors.textMuted,
                      size: 22,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Middle: Attribute pills
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    // Difficulty tag
                    _buildMetaChip(
                      icon: Icons.bolt_rounded,
                      label: task.difficulty.label,
                      iconColor: FlowColors.cyanLight,
                      bgColor: FlowColors.tagDeepWorkBg,
                      textColor: FlowColors.cyanLight,
                    ),
                    // Duration
                    _buildMetaChip(
                      icon: Icons.access_time_rounded,
                      label: '${task.durationMinutes} min',
                      iconColor: FlowColors.textSecondary,
                      bgColor: FlowColors.darkSurface,
                      textColor: FlowColors.textSecondary,
                    ),
                    // Deadline
                    _buildMetaChip(
                      icon: Icons.calendar_today_rounded,
                      label: task.deadline,
                      iconColor: FlowColors.textSecondary,
                      bgColor: FlowColors.darkSurface,
                      textColor: FlowColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Bottom: Category & Action icons (reschedule, complete)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      task.category,
                      style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                    ),
                    Row(
                      children: [
                        // Reschedule / repeat button
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          color: FlowColors.textMuted,
                          splashRadius: 22,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Rescheduling "${task.title}" to next focus window...'),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                        // Complete Checkbox Button (48px tap target)
                        InkWell(
                          onTap: onToggleComplete,
                          borderRadius: BorderRadius.circular(24),
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
                            child: Icon(
                              task.isCompleted
                                  ? Icons.check_circle_rounded
                                  : Icons.check_circle_outline_rounded,
                              color: task.isCompleted ? FlowColors.mint : FlowColors.mintLight,
                              size: 26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip({
    required IconData icon,
    required String label,
    required Color iconColor,
    required Color bgColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: FlowRadii.pillRadius,
        border: Border.all(color: FlowColors.darkBorder.withOpacity(0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: FlowTypography.labelSmall(color: textColor).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
