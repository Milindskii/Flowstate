import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/primary_button.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 8: Calendar Tab with Focus Windows & "Optimize My Day" Engine Action
class CalendarTab extends StatefulWidget {
  const CalendarTab({super.key});

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  int _selectedDayIndex = 2; // Wednesday / Oct 24

  final List<String> _days = ['Mon\n22', 'Tue\n23', 'Wed\n24', 'Thu\n25', 'Fri\n26', 'Sat\n27', 'Sun\n28'];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Calendar',
                style: FlowTypography.headlineMedium().copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Energy-aligned schedule & focus blocks',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
              ),
              const SizedBox(height: 20),

              // Horizontal Date Strip
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(_days.length, (index) {
                    final isSelected = _selectedDayIndex == index;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDayIndex = index),
                      child: Container(
                        width: 54,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? FlowColors.cyan : FlowColors.darkCard,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? FlowColors.cyan : FlowColors.darkBorder,
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _days[index],
                          textAlign: TextAlign.center,
                          style: FlowTypography.labelMedium(
                            color: isSelected ? FlowColors.textInverse : FlowColors.textPrimary,
                          ).copyWith(
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 24),

              // Prominent "Optimize My Day" Action Button
              PrimaryButton(
                label: state.isOptimizing ? 'Optimizing with Rhythm Engine...' : 'Optimize My Day',
                icon: const Icon(Icons.auto_awesome_rounded, color: FlowColors.textInverse, size: 20),
                isLoading: state.isOptimizing,
                onPressed: () async {
                  await state.optimizeSchedule();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Schedule recalibrated to align with your peak readiness window!'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 24),

              // Highlighted Focus Window Block
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: FlowColors.cyanLight.withOpacity(0.5), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: FlowColors.cyan.withOpacity(0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: FlowColors.tagDeepWorkBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.bolt_rounded, color: FlowColors.cyanLight, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Optimal Focus Window',
                            style: FlowTypography.titleMedium(color: FlowColors.cyanLight).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.readiness.focusWindowRange,
                            style: FlowTypography.bodyMedium(color: FlowColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Calendar Scheduled Blocks
              Text(
                'Scheduled Timeline',
                style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),

              ...state.schedule.map((item) {
                final isDeepWork = item.tagText == 'DEEP WORK';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlowColors.darkCard,
                    borderRadius: FlowRadii.cardRadius,
                    border: Border.all(
                      color: isDeepWork ? FlowColors.cyan.withOpacity(0.4) : FlowColors.darkBorder,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Time badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: FlowColors.darkSurface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${item.time} ${item.period}',
                          style: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Event details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: FlowTypography.bodyLarge().copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.type} • ${item.durationMinutes} min',
                              style: FlowTypography.bodyMedium(color: FlowColors.textMuted),
                            ),
                          ],
                        ),
                      ),

                      // Tag
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: item.tagBg,
                          borderRadius: FlowRadii.pillRadius,
                        ),
                        child: Text(
                          item.tagText,
                          style: FlowTypography.badgeText(color: item.tagColor),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }
}
