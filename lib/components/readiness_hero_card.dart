import 'package:flutter/material.dart';
import '../models/readiness_model.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'energy_curve_painter.dart';

/// Screen 4 Hero Card: Today's Readiness
/// Prominent, calming cognitive focus evaluation with circadian rhythm curve.
class ReadinessHeroCard extends StatelessWidget {
  final ReadinessModel readiness;
  final VoidCallback? onTap;

  const ReadinessHeroCard({
    super.key,
    required this.readiness,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardLargeRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header: Title + Score Badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Today's Readiness",
                          style: FlowTypography.titleMedium().copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Based on your recent rhythm',
                          style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                        ),
                      ],
                    ),
                    // Score pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: FlowColors.tagDeepWorkBg,
                        borderRadius: FlowRadii.pillRadius,
                        border: Border.all(color: FlowColors.cyan.withOpacity(0.4), width: 1.0),
                      ),
                      child: Text(
                        '${readiness.score}/${readiness.maxScore}',
                        style: FlowTypography.titleMedium(color: FlowColors.cyanLight).copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Smooth circadian curve chart
                SizedBox(
                  height: 90,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: EnergyCurvePainter(points: readiness.hourlyRhythm),
                  ),
                ),
                const SizedBox(height: 20),

                // Status message with sparkle icon
                Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: FlowColors.mintLight,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        readiness.statusMessage,
                        style: FlowTypography.labelMedium(color: FlowColors.textPrimary).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Focus Window Chip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: FlowColors.darkSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        color: FlowColors.cyanLight,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Focus Window: ${readiness.focusWindowRange}',
                        style: FlowTypography.labelMedium(color: FlowColors.textPrimary).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
