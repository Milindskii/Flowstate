import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';

/// Reusable pulsating shimmer box for skeleton states
class FlowShimmerBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? margin;

  const FlowShimmerBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
    this.margin,
  });

  @override
  State<FlowShimmerBox> createState() => _FlowShimmerBoxState();
}

class _FlowShimmerBoxState extends State<FlowShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.35, end: 0.75).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark
        ? FlowColors.darkCard
        : FlowColors.lightCardElevated;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: baseColor.withValues(alpha: _animation.value),
            borderRadius: widget.borderRadius ?? FlowRadii.cardRadius,
            border: Border.all(
              color: (isDark ? FlowColors.darkBorder : FlowColors.lightBorder)
                  .withValues(alpha: _animation.value * 0.5),
              width: 1.0,
            ),
          ),
        );
      },
    );
  }
}

/// Loading skeleton for Today Dashboard screen
class TodayDashboardSkeleton extends StatelessWidget {
  const TodayDashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = FlowSpacing.pageMargin(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Date skeleton + Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowShimmerBox(
                        width: 100,
                        height: 14,
                        borderRadius: BorderRadius.circular(FlowRadii.badge),
                      ),
                      const SizedBox(height: 8),
                      FlowShimmerBox(
                        width: 180,
                        height: 28,
                        borderRadius: BorderRadius.circular(FlowRadii.badge),
                      ),
                    ],
                  ),
                  const FlowShimmerBox(
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.all(Radius.circular(22)),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Hero Readiness / Noya Card
              const FlowShimmerBox(
                width: double.infinity,
                height: 160,
                borderRadius: FlowRadii.cardLargeRadius,
              ),
              const SizedBox(height: 24),

              // Section Title: "Today's Schedule"
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  FlowShimmerBox(
                    width: 140,
                    height: 20,
                    borderRadius: BorderRadius.circular(FlowRadii.badge),
                  ),
                  FlowShimmerBox(
                    width: 60,
                    height: 16,
                    borderRadius: BorderRadius.circular(FlowRadii.badge),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3 Task Cards
              ...List.generate(3, (index) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: FlowShimmerBox(
                  width: double.infinity,
                  height: 90,
                  borderRadius: FlowRadii.cardRadius,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading skeleton for Task Inbox tab
class TaskInboxSkeleton extends StatelessWidget {
  const TaskInboxSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = FlowSpacing.pageMargin(context);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowShimmerBox(
                        width: 90,
                        height: 26,
                        borderRadius: BorderRadius.circular(FlowRadii.badge),
                      ),
                      const SizedBox(height: 6),
                      FlowShimmerBox(
                        width: 160,
                        height: 14,
                        borderRadius: BorderRadius.circular(FlowRadii.badge),
                      ),
                    ],
                  ),
                  const FlowShimmerBox(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.all(Radius.circular(16)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Quick Input Bar
              const FlowShimmerBox(
                width: double.infinity,
                height: 52,
                borderRadius: FlowRadii.cardRadius,
              ),
              const SizedBox(height: 16),

              // Filter Chips
              Row(
                children: List.generate(4, (index) => const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: FlowShimmerBox(
                    width: 64,
                    height: 32,
                    borderRadius: FlowRadii.chipRadius,
                  ),
                )),
              ),
              const SizedBox(height: 24),

              // Priority Section Header
              FlowShimmerBox(
                width: 110,
                height: 16,
                borderRadius: BorderRadius.circular(FlowRadii.badge),
              ),
              const SizedBox(height: 12),

              // 3 Task Cards
              ...List.generate(3, (index) => const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: FlowShimmerBox(
                  width: double.infinity,
                  height: 80,
                  borderRadius: FlowRadii.cardRadius,
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}
