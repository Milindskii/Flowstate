import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_typography.dart';

/// Sticky Bottom Navigation Bar for Flowstate
/// 5 destinations with thumb-friendly tap targets (> 48px).
/// Features cohesive active (filled) vs inactive (outlined) icon states and subtle selection haptics.
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
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        border: Border(
          top: BorderSide(color: FlowColors.border(context), width: 1.0),
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
                context: context,
                index: 0,
                activeIcon: Icons.today_rounded,
                inactiveIcon: Icons.today_outlined,
                label: 'Today',
              ),
              _buildNavItem(
                context: context,
                index: 1,
                activeIcon: Icons.assignment_rounded,
                inactiveIcon: Icons.assignment_outlined,
                label: 'Tasks',
              ),
              _buildNavItem(
                context: context,
                index: 2,
                activeIcon: Icons.calendar_month_rounded,
                inactiveIcon: Icons.calendar_month_outlined,
                label: 'Calendar',
              ),
              _buildNavItem(
                context: context,
                index: 3,
                activeIcon: Icons.insights_rounded,
                inactiveIcon: Icons.insights_outlined,
                label: 'Insights',
              ),
              _buildNavItem(
                context: context,
                index: 4,
                activeIcon: Icons.person_rounded,
                inactiveIcon: Icons.person_outline_rounded,
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required String label,
  }) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final isSelected = currentIndex == index;
    final color = isSelected ? accent : FlowColors.textMutedOf(context);
    final iconData = isSelected ? activeIcon : inactiveIcon;

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$label tab',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              if (currentIndex != index) {
                FlowHaptics.selection();
              }
              onTap(index);
            },
            splashColor: accent.withValues(alpha: 0.12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconData,
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
      ),
    );
  }
}
