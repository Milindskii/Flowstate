import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 3: Multi-step Progress Header
class ProgressHeader extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final VoidCallback? onBack;

  const ProgressHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = (currentStep / totalSteps).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (onBack != null && currentStep > 1)
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: FlowColors.textPrimary),
                onPressed: onBack,
                splashRadius: 24,
              )
            else
              const SizedBox(width: 48),
            Text(
              'Step $currentStep of $totalSteps',
              style: FlowTypography.labelMedium(color: FlowColors.textMuted).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 48), // Balancing spacer
          ],
        ),
        const SizedBox(height: 12),
        // Progress Bar
        ClipRRect(
          borderRadius: FlowRadii.pillRadius,
          child: Container(
            height: 6,
            width: double.infinity,
            color: FlowColors.darkCard,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: FlowColors.primaryGradient,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
