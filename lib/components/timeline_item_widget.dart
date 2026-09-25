import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_item.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Modern Card-based Timeline Task Tile:
/// - Clean elevated container with soft shadow and crisp border
/// - Scheduled time badge
/// - One-tap circular checkbox to mark complete with haptics
/// - Task title, duration badge, and category tag
/// - Direct "Done" action button
class TimelineItemWidget extends StatelessWidget {
  final ScheduleItem item;
  final bool isLast;
  final bool isPast;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onStart;

  const TimelineItemWidget({
    super.key,
    required this.item,
    this.isLast = false,
    this.isPast = false,
    this.onTap,
    this.onComplete,
    this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final active = item.isActive;
    final isDone = item.isCompleted || isPast;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: BorderRadius.circular(FlowRadii.card),
        border: Border.all(
          color: active
              ? accent.withValues(alpha: 0.5)
              : FlowColors.border(context),
          width: active ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FlowRadii.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Circular checkmark button for Done option (touch target ≥ 44px)
                Semantics(
                  button: true,
                  label: 'Mark ${item.title} as done',
                  child: InkWell(
                    onTap: () {
                      FlowHaptics.success();
                      onComplete?.call();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(6.0),
                      child: Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: isDone ? FlowColors.mint : FlowColors.textMutedOf(context),
                        size: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Scheduled Time Pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: active
                        ? accent.withValues(alpha: 0.14)
                        : FlowColors.surfaceElevated(context),
                    borderRadius: BorderRadius.circular(FlowRadii.pill),
                    border: Border.all(
                      color: active
                          ? accent.withValues(alpha: 0.35)
                          : FlowColors.border(context),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '${item.time} ${item.period}',
                    style: FlowTypography.labelSmall(
                      color: active ? accent : FlowColors.textSecondaryOf(context),
                    ).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // 3. Task Title + Duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.title,
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 14.5,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 11,
                            color: FlowColors.textMutedOf(context),
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              '${item.durationMinutes} min${item.type.isNotEmpty ? ' · ${item.type}' : ''}',
                              style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
