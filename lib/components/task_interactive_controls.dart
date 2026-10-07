import 'package:flutter/material.dart';
import '../models/task_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Interactive stepped selector for Task Focus Requirement / Difficulty.
/// Features a smooth horizontal track, animated sliding indicator,
/// haptic feedback, and a small contextual label.
class FocusRequirementSelector extends StatelessWidget {
  final TaskDifficulty selectedDifficulty;
  final ValueChanged<TaskDifficulty> onChanged;
  final Color? accentColor;

  const FocusRequirementSelector({
    super.key,
    required this.selectedDifficulty,
    required this.onChanged,
    this.accentColor,
  });

  static const List<TaskDifficulty> _levels = [
    TaskDifficulty.light,
    TaskDifficulty.medium,
    TaskDifficulty.high,
    TaskDifficulty.physical,
  ];

  String _getContextualLabel(TaskDifficulty diff) {
    switch (diff) {
      case TaskDifficulty.light:
        return 'Light • Quick & shallow tasks';
      case TaskDifficulty.medium:
        return 'Medium • Steady focus & study';
      case TaskDifficulty.high:
        return 'Deep • High focus required';
      case TaskDifficulty.physical:
        return 'Active • Physical & movement';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeAccent = accentColor ?? FlowColors.mint;
    final currentIndex = _levels.indexOf(selectedDifficulty).clamp(0, 3);
    final isDark = FlowColors.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'FOCUS REQUIREMENT',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  _getContextualLabel(selectedDifficulty),
                  key: ValueKey(selectedDifficulty),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FlowTypography.bodySmall(color: activeAccent).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Horizontal Stepped Selector Track
        Container(
          height: 48,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: BorderRadius.circular(FlowRadii.chip),
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              // constraints are already the inner (padded) box: one cell is exactly a quarter of it
              final stepWidth = constraints.maxWidth / 4;
              final targetX = currentIndex * stepWidth;

              return Stack(
                children: [
                  // Animated Sliding Active Indicator Pill
                  AnimatedPositioned(
                    duration: FlowMotion.responsiveDuration(
                      context,
                      const Duration(milliseconds: 200),
                    ),
                    curve: Curves.easeOutCubic,
                    left: targetX,
                    top: 0,
                    width: stepWidth,
                    height: constraints.maxHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: activeAccent.withValues(alpha: isDark ? 0.25 : 0.16),
                        borderRadius: BorderRadius.circular(FlowRadii.chip - 3),
                        border: Border.all(color: activeAccent, width: 1.5),
                      ),
                    ),
                  ),

                  // Interactive Step Buttons (4 steps)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _levels.map((level) {
                      final isSelected = selectedDifficulty == level;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (!isSelected) {
                              FlowHaptics.selection();
                              onChanged(level);
                            }
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 150),
                              style: FlowTypography.labelSmall(
                                color: isSelected
                                    ? activeAccent
                                    : FlowColors.textSecondaryOf(context),
                              ).copyWith(
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                fontSize: 12,
                              ),
                              child: Text(level.tagText),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Interactive Duration Selector supporting both horizontal drag slider with snapping
/// and quick preset chips.
class DurationSliderSelector extends StatelessWidget {
  final int durationMinutes;
  final ValueChanged<int> onChanged;
  final Color? accentColor;

  const DurationSliderSelector({
    super.key,
    required this.durationMinutes,
    required this.onChanged,
    this.accentColor,
  });

  static const List<int> _snappingSteps = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 150, 180];
  static const List<int> _presetChips = [15, 25, 30, 45, 60, 90, 120];

  int _snapToNearest(int value) {
    int closest = _snappingSteps.first;
    int minDiff = (value - closest).abs();
    for (final step in _snappingSteps) {
      final diff = (value - step).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = step;
      }
    }
    return closest;
  }

  @override
  Widget build(BuildContext context) {
    final activeAccent = accentColor ?? FlowColors.mint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ESTIMATED DURATION',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: activeAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(FlowRadii.pill),
              ),
              child: Text(
                '$durationMinutes min',
                style: FlowTypography.labelMedium(color: activeAccent).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Horizontal Interactive Slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            activeTrackColor: activeAccent,
            inactiveTrackColor: FlowColors.surfaceElevated(context),
            thumbColor: activeAccent,
            overlayColor: activeAccent.withValues(alpha: 0.2),
            valueIndicatorColor: activeAccent,
            valueIndicatorTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          child: Slider(
            value: durationMinutes.toDouble().clamp(5.0, 180.0),
            min: 5.0,
            max: 180.0,
            divisions: 35, // 5 min increments up to 180 min
            onChanged: (val) {
              final snapped = _snapToNearest(val.round());
              if (snapped != durationMinutes) {
                FlowHaptics.selection();
                onChanged(snapped);
              }
            },
          ),
        ),

        // Quick Preset Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _presetChips.map((mins) {
              final isSelected = durationMinutes == mins;
              return Container(
                margin: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('${mins}m'),
                  selected: isSelected,
                  selectedColor: activeAccent.withValues(alpha: 0.18),
                  backgroundColor: FlowColors.surfaceElevated(context),
                  labelStyle: FlowTypography.labelSmall(
                    color: isSelected ? activeAccent : FlowColors.textSecondaryOf(context),
                  ).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
                  side: BorderSide(
                    color: isSelected ? activeAccent : FlowColors.border(context),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FlowRadii.chip),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      FlowHaptics.selection();
                      onChanged(mins);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// Restrained, semantic Priority Selector:
/// LOW: muted neutral
/// MEDIUM: blue
/// HIGH: amber
/// URGENT: red/rose
/// Uses small colored dots, clean scannable indicators, and subtle borders.
class PrioritySelector extends StatelessWidget {
  final TaskPriority priority;
  final ValueChanged<TaskPriority> onChanged;

  const PrioritySelector({
    super.key,
    required this.priority,
    required this.onChanged,
  });

  /// The status line always derives from the selected level, so it can never contradict the control.
  static String statusLabel(TaskPriority p) {
    switch (p) {
      case TaskPriority.low:
        return 'Low priority';
      case TaskPriority.medium:
        return 'Medium priority';
      case TaskPriority.high:
        return 'High priority';
      case TaskPriority.urgent:
        return 'Urgent priority';
    }
  }

  static const List<(TaskPriority, String, Color)> _levels = [
    (TaskPriority.low, 'Low', Color(0xFF94A3B8)),
    (TaskPriority.medium, 'Medium', Color(0xFF38BDF8)),
    (TaskPriority.high, 'High', Color(0xFFF59E0B)),
    (TaskPriority.urgent, 'Urgent', Color(0xFFF43F5E)),
  ];

  @override
  Widget build(BuildContext context) {
    final isHighOrUrgent = priority == TaskPriority.high || priority == TaskPriority.urgent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'PRIORITY',
              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                letterSpacing: 0.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              statusLabel(priority),
              key: const Key('priority_status_label'),
              style: FlowTypography.bodySmall(
                color: isHighOrUrgent ? FlowColors.priorityColorOf(context, priority) : FlowColors.textMutedOf(context),
              ).copyWith(
                fontWeight: isHighOrUrgent ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: FlowColors.surfaceElevated(context),
            borderRadius: BorderRadius.circular(FlowRadii.chip),
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _levels.map((lvl) {
              final isSelected = priority == lvl.$1;
              final color = lvl.$3;
              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!isSelected) {
                      FlowHaptics.selection();
                      onChanged(lvl.$1);
                    }
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? color.withValues(alpha: FlowColors.isDark(context) ? 0.22 : 0.14)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(FlowRadii.chip - 3),
                      border: Border.all(color: isSelected ? color : Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isSelected ? color : color.withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          lvl.$2,
                          style: FlowTypography.labelSmall(
                            color: isSelected
                                ? FlowColors.textPrimaryOf(context)
                                : FlowColors.textSecondaryOf(context),
                          ).copyWith(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

