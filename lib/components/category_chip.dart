import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Horizontal Category Filter Pill (44px touch height)
class CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      height: 44.0, // Mobile tap target
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        color: isSelected ? accent : FlowColors.surface(context),
        borderRadius: FlowRadii.pillRadius,
        border: Border.all(
          color: isSelected ? accent : FlowColors.border(context),
          width: 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.pillRadius,
          onTap: () {
            FlowHaptics.selection();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Center(
              child: Text(
                label,
                style: FlowTypography.labelMedium(
                  color: isSelected ? FlowColors.textInverse : FlowColors.textSecondaryOf(context),
                ).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
