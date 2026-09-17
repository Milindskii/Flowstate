import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'task_difficulty_badge.dart';

/// Screen 4: Single Prominent "RIGHT NOW" Primary Task Card
/// Focuses the user immediately on execution without visual noise.
class RightNowTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onStart;
  final VoidCallback onReschedule;

  const RightNowTaskCard({
    super.key,
    required this.task,
    required this.onStart,
    required this.onReschedule,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: RIGHT NOW Badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: FlowColors.tagDeepWorkBg,
                borderRadius: FlowRadii.pillRadius,
                border: Border.all(color: FlowColors.cyan.withOpacity(0.35), width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: FlowColors.cyan,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'RIGHT NOW',
                    style: FlowTypography.badgeText(color: FlowColors.cyan).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Main Card
        Container(
          decoration: BoxDecoration(
            color: FlowColors.darkCard,
            borderRadius: FlowRadii.cardRadius,
            border: Border.all(color: FlowColors.cyan.withOpacity(0.3), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: FlowColors.cyan.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task Title
                Text(
                  task.title,
                  style: FlowTypography.headlineMedium().copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),

                // Metadata row (Duration • Difficulty • Deadline)
                Row(
                  children: [
                    TaskDifficultyBadge(difficulty: task.difficulty),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${task.durationMinutes} min',
                      style: FlowTypography.bodyMedium(color: FlowColors.textSecondary).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '•',
                      style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.deadline,
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Action Buttons: Primary "Start" + Secondary "Reschedule"
                Row(
                  children: [
                    // Strongest Primary Action: Start
                    Expanded(
                      flex: 6,
                      child: Container(
                        height: 48, // Ergonomic minimum touch target
                        decoration: BoxDecoration(
                          borderRadius: FlowRadii.buttonRadius,
                          gradient: FlowColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: FlowColors.cyan.withOpacity(0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: FlowRadii.buttonRadius,
                            splashColor: Colors.white.withOpacity(0.2),
                            onTap: onStart,
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.play_arrow_rounded,
                                    color: FlowColors.textInverse,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Start',
                                    style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Secondary Action: Reschedule
                    Expanded(
                      flex: 4,
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: onReschedule,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FlowColors.textSecondary,
                            side: const BorderSide(color: FlowColors.darkBorder, width: 1.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: FlowRadii.buttonRadius,
                            ),
                          ),
                          child: Text(
                            'Reschedule',
                            style: FlowTypography.labelMedium(color: FlowColors.textSecondary).copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
