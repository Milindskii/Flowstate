import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_item.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';

/// Ultralight timeline item: TIME  •  TITLE (Duration)
/// No heavy boxed cards. Subtle vertical line and quiet typography.
class TimelineItemWidget extends StatelessWidget {
  final ScheduleItem item;
  final bool isLast;
  final bool isPast;

  const TimelineItemWidget({
    super.key,
    required this.item,
    this.isLast = false,
    this.isPast = false,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    final active = item.isActive;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Time Column (e.g. 11:30 AM)
          SizedBox(
            width: 58,
            child: Text(
              '${item.time} ${item.period}',
              style: FlowTypography.labelSmall(
                color: isPast ? FlowColors.textMuted : FlowColors.textSecondary,
              ).copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 12),

          // 2. Subtle Vertical Line + Dot
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? accent
                      : (isPast ? FlowColors.textMuted : FlowColors.darkBorder),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),

          // 3. Title and Duration (Clean, minimal, no boxed card)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: FlowTypography.bodyMedium(
                        color: isPast ? FlowColors.textMuted : FlowColors.textPrimary,
                      ).copyWith(
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${item.durationMinutes} min',
                    style: FlowTypography.labelSmall(
                      color: isPast ? FlowColors.textMuted : FlowColors.textSecondary,
                    ),
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
