import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'task_difficulty_badge.dart';

/// Screen 4: Recommended Next Hero Task Card
class RecommendedTaskCard extends StatelessWidget {
  final TaskItem task;
  final VoidCallback onStart;

  const RecommendedTaskCard({
    super.key,
    required this.task,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recommended Next',
          style: FlowTypography.titleMedium().copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: FlowColors.darkCard,
            borderRadius: FlowRadii.cardLargeRadius,
            border: Border.all(color: FlowColors.darkBorder, width: 1.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title and Play Action
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: FlowTypography.headlineMedium().copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Circular play button
                    GestureDetector(
                      onTap: onStart,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: FlowColors.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: FlowColors.cyan.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: FlowColors.textInverse,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Meta row: Difficulty badge + Duration & Deadline
                Row(
                  children: [
                    TaskDifficultyBadge(difficulty: task.difficulty),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${task.durationMinutes} min • ${task.deadline}',
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Primary Start Button
                Container(
                  width: double.infinity,
                  height: 48, // Touch target
                  decoration: BoxDecoration(
                    borderRadius: FlowRadii.buttonRadius,
                    gradient: FlowColors.primaryGradient,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: FlowRadii.buttonRadius,
                      splashColor: Colors.white.withOpacity(0.2),
                      onTap: onStart,
                      child: Center(
                        child: Text(
                          'Start Task',
                          style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
