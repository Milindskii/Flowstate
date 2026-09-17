import 'package:flutter/material.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';

/// Sticky Bottom Navigation Bar for Flowstate
/// 5 destinations with thumb-friendly tap targets (> 48px).
class FlowBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const FlowBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: FlowColors.darkSurface,
        border: Border(
          top: BorderSide(color: FlowColors.darkBorder, width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.today_rounded,
                label: 'Today',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.assignment_rounded,
                label: 'Tasks',
              ),
              _buildNavItem(
                index: 2,
                icon: Icons.calendar_month_rounded,
                label: 'Calendar',
              ),
              _buildNavItem(
                index: 3,
                icon: Icons.insights_rounded,
                label: 'Insights',
              ),
              _buildNavItem(
                index: 4,
                icon: Icons.person_outline_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = currentIndex == index;
    final color = isSelected ? FlowColors.cyanLight : FlowColors.textSecondary;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => onTap(index),
          splashColor: FlowColors.cyan.withOpacity(0.12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: color,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: FlowTypography.labelSmall(color: color).copyWith(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
