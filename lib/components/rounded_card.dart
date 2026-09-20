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
    final cardBg = backgroundColor ?? FlowColors.surface(context);
    final borderSide = border ?? BorderSide(color: FlowColors.border(context), width: 1.0);

    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? cardBg : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.fromBorderSide(borderSide),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: onTap != null ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          highlightColor: onTap != null ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04) : Colors.transparent,
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
