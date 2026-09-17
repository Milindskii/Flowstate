import 'package:flutter/material.dart';
import '../models/readiness_model.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'energy_curve_painter.dart';

/// Compact Readiness Card
/// Replaces the oversized hero card with a clean, contextual summary.
/// Non-medical, strictly focused on cognitive focus windows.
class CompactReadinessCard extends StatelessWidget {
  final ReadinessModel readiness;
  final VoidCallback? onTap;

  const CompactReadinessCard({
    super.key,
    required this.readiness,
    this.onTap,
  });

  void _showWhySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FlowColors.darkBorder,
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: FlowColors.cyan, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Why this readiness score?',
                      style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  readiness.explanation,
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ...readiness.factors.map(
                  (factor) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded, color: FlowColors.mint, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            factor,
                            style: FlowTypography.bodyMedium(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: FlowColors.darkSurface,
                    borderRadius: FlowRadii.inputRadius,
                    border: Border.all(color: FlowColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: FlowColors.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Confidence: ${(readiness.confidence * 100).toInt()}% • Model: ${readiness.modelVersion}',
                          style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!readiness.isCalibrated) {
      // "Learning your rhythm" state for new users
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: FlowColors.darkCard,
          borderRadius: FlowRadii.cardRadius,
          border: Border.all(color: FlowColors.darkBorder, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: FlowColors.cyan.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: FlowColors.cyan, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Learning your rhythm...',
                    style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'We’ll personalize your recommendations as you use Flowstate.',
                    style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Score + Strong Window + "Why?" button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Score & Status
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded, color: FlowColors.cyan, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          'Readiness ${readiness.score}',
                          style: FlowTypography.titleMedium().copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),

                    // "Why?" trigger
                    InkWell(
                      onTap: () => _showWhySheet(context),
                      borderRadius: FlowRadii.pillRadius,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Text(
                              'Why?',
                              style: FlowTypography.labelMedium(color: FlowColors.cyan).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 2),
                            const Icon(Icons.chevron_right_rounded, color: FlowColors.cyan, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Middle Row: Focus Window Chip + Mini Curve
                Row(
                  children: [
                    Expanded(
                      flex: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: FlowColors.darkSurface,
                          borderRadius: FlowRadii.inputRadius,
                          border: Border.all(color: FlowColors.darkBorder),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded, color: FlowColors.mint, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Strong window: ${readiness.focusWindowRange}',
                                style: FlowTypography.labelMedium(color: FlowColors.textPrimary).copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Mini preview of energy rhythm
                    if (readiness.hourlyRhythm.isNotEmpty)
                      Expanded(
                        flex: 4,
                        child: SizedBox(
                          height: 38,
                          child: CustomPaint(
                            painter: EnergyCurvePainter(
                              points: readiness.hourlyRhythm,
                              animatePeak: false,
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
      ),
    );
  }
}
