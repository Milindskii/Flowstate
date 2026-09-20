import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Flat Primary Button using user-customized accent color (Min height 52px, 18px radius)
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool fullWidth;
  final Color? customColor;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.customColor,
  });

  @override
  Widget build(BuildContext context) {
    Color accent = customColor ?? FlowColors.accentCyan;
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      accent = customColor ?? themeProvider.resolveAccent(context);
    } catch (_) {}

    return Container(
      width: fullWidth ? double.infinity : null,
      height: 52.0, // Mobile thumb-friendly target (> 48px)
      decoration: BoxDecoration(
        color: accent,
        borderRadius: FlowRadii.buttonRadius,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: FlowRadii.buttonRadius,
          splashColor: Colors.black.withValues(alpha: 0.15),
          highlightColor: Colors.black.withValues(alpha: 0.08),
          onTap: isLoading || onPressed == null
              ? null
              : () {
                  FlowHaptics.lightTap();
                  onPressed!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isLoading) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(FlowColors.textInverse),
                    ),
                  ),
                  const SizedBox(width: 12),
                ] else if (icon != null) ...[
                  icon!,
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                    fontWeight: FontWeight.w700,
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
