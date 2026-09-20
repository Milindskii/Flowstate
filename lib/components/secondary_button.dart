import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Thumb-friendly Secondary Button (Min height 52px, 18px radius, touch feedback)
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool fullWidth;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      height: 52.0, // Mobile thumb target (> 44px)
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.buttonRadius,
        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.buttonRadius,
          splashColor: FlowColors.accentCyan.withValues(alpha: 0.12),
          highlightColor: FlowColors.accentCyan.withValues(alpha: 0.06),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: FlowTypography.labelLarge(color: FlowColors.textPrimary).copyWith(
                    fontWeight: FontWeight.w600,
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
