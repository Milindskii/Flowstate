import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Tag / Badge for Task Difficulty and Focus intensity
class TaskDifficultyBadge extends StatelessWidget {
  final TaskDifficulty difficulty;

  const TaskDifficultyBadge({
    super.key,
    required this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color textColor;
    String label;

    switch (difficulty) {
      case TaskDifficulty.high:
        bg = FlowColors.tagDeepWorkBg;
        textColor = FlowColors.tagDeepWorkText;
        label = 'HIGH FOCUS';
        break;
      case TaskDifficulty.medium:
        bg = FlowColors.tagMediumBg;
        textColor = FlowColors.tagMediumText;
        label = 'MEDIUM';
        break;
      case TaskDifficulty.light:
        bg = FlowColors.tagLightBg;
        textColor = FlowColors.tagLightText;
        label = 'LIGHT';
        break;
      case TaskDifficulty.physical:
        bg = FlowColors.tagPhysicalBg;
        textColor = FlowColors.tagPhysicalText;
        label = 'PHYSICAL';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: FlowRadii.pillRadius,
        border: Border.all(color: textColor.withOpacity(0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: FlowTypography.badgeText(color: textColor),
      ),
    );
  }
}
