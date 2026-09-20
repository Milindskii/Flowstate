import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/readiness_model.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Tiny Contextual Readiness Element
/// Clean, non-dominant line with "Why?" bottom sheet for details.
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
      isScrollControlled: true,
      backgroundColor: FlowColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: FlowColors.darkBorder,
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: FlowColors.accentCyan, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Why this readiness estimate?',
                      style: FlowTypography.titleMedium().copyWith(
                        fontWeight: FontWeight.w700,
                        color: FlowColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  readiness.explanation.isNotEmpty
                      ? readiness.explanation
                      : 'Your readiness is based on recent sleep, previous cognitive performance, and historical circadian focus rhythm.',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                ),
                const SizedBox(height: 16),
                ...readiness.factors.map(
                  (factor) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_outline_rounded, color: FlowColors.accentMint, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            factor,
                            style: FlowTypography.bodyMedium(color: FlowColors.textPrimary),
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
                    color: FlowColors.darkCardElevated,
                    borderRadius: FlowRadii.inputRadius,
                    border: Border.all(color: FlowColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: FlowColors.textMuted, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          readiness.isCalibrated
                              ? 'Confidence: ${(readiness.confidence * 100).toInt()}% · Model: ${readiness.modelVersion}'
                              : 'Model: ${readiness.modelVersion} · Gathering initial sessions',
                          style: FlowTypography.labelSmall(color: FlowColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    // 1. Uncalibrated / Learning State
    if (!readiness.isCalibrated || readiness.score == null) {
      return InkWell(
        onTap: () => _showWhySheet(context),
        borderRadius: FlowRadii.inputRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('✦', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Learning your rhythm',
                      style: FlowTypography.titleSmall().copyWith(
                        fontWeight: FontWeight.w700,
                        color: FlowColors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const SizedBox(width: 17),
                  Expanded(
                    child: Text(
                      "We're learning when you work best.",
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Why?',
                    style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(
                      decoration: TextDecoration.underline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 2. Calibrated State
    final score = readiness.score ?? 78;
    final isLowEnergy = score < 50;
    final headline = isLowEnergy ? 'Low-energy window' : 'Ready for a good session';
    final subtitle = isLowEnergy
        ? 'Best to handle lighter work'
        : readiness.focusWindowRange;

    return InkWell(
      onTap: () => _showWhySheet(context),
      borderRadius: FlowRadii.inputRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('✦', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    headline,
                    style: FlowTypography.titleSmall().copyWith(
                      fontWeight: FontWeight.w700,
                      color: FlowColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                const SizedBox(width: 17),
                Expanded(
                  child: Text(
                    subtitle,
                    style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Why?',
                  style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
