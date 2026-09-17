import 'package:flutter/material.dart';
import '../models/schedule_item.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 4: Timeline Item Card for Today's Schedule
class TimelineItemWidget extends StatelessWidget {
  final ScheduleItem item;
  final bool isLast;

  const TimelineItemWidget({
    super.key,
    required this.item,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time Column (e.g. 9:30 AM)
          SizedBox(
            width: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.time,
                  style: FlowTypography.titleMedium().copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  item.period,
                  style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                ),
                const SizedBox(height: 8),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.only(right: 6),
                      color: FlowColors.darkBorder,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),

          // Schedule Card
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: FlowColors.darkCard,
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(
                  color: item.isActive
                      ? FlowColors.cyan.withOpacity(0.5)
                      : FlowColors.darkBorder,
                  width: item.isActive ? 1.5 : 1.0,
                ),
                boxShadow: item.isActive
                    ? [
                        BoxShadow(
                          color: FlowColors.cyan.withOpacity(0.15),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: FlowTypography.titleMedium().copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.more_horiz_rounded,
                        color: FlowColors.textMuted,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      // Tag Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.tagBg,
                          borderRadius: FlowRadii.pillRadius,
                        ),
                        child: Text(
                          item.tagText,
                          style: FlowTypography.badgeText(color: item.tagColor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        item.type,
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
