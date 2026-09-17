import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';

/// Base Rounded Card Container
/// 24px - 28px corner radius with obsidian background and subtle border.
class RoundedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final BorderSide? border;
  final double radius;
  final Gradient? gradient;

  const RoundedCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20.0),
    this.onTap,
    this.backgroundColor,
    this.border,
    this.radius = FlowRadii.card,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (backgroundColor ?? FlowColors.darkCard) : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.fromBorderSide(
          border ?? const BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: onTap != null ? FlowColors.cyan.withOpacity(0.08) : Colors.transparent,
          highlightColor: onTap != null ? FlowColors.cyan.withOpacity(0.04) : Colors.transparent,
          onTap: onTap,
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}
