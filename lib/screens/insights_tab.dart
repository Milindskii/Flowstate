import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Screen 9: Personal Analytics & Patterns
/// Strictly non-medical cognitive performance insights.
class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final learning = state.learningEngine;

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
                'Your Patterns',
                style: FlowTypography.headlineMedium().copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Continuous rhythm learning from your completions',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
              ),
              const SizedBox(height: 24),

              // 2x2 Metric Grid
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      icon: Icons.access_time_rounded,
                      title: 'Best Focus Window',
                      value: learning.bestFocusWindow,
                      accentColor: FlowColors.cyanLight,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      icon: Icons.code_rounded,
                      title: 'Best Task Type',
                      value: learning.bestTaskType,
                      accentColor: FlowColors.mintLight,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      icon: Icons.hourglass_top_rounded,
                      title: 'Avg Deep Work',
                      value: learning.averageDeepWork,
                      accentColor: FlowColors.iceBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildMetricCard(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Completion Rate',
                      value: '${learning.completionRatePercentage}%',
                      accentColor: FlowColors.mint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Weekly Rhythm & Deep Work Graph
              Text(
                'Weekly Focus & Readiness',
                style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: FlowColors.darkCard,
                  borderRadius: FlowRadii.cardLargeRadius,
                  border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                ),
                child: Column(
                  children: [
                    // Legend
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildLegend(FlowColors.cyan, 'Readiness'),
                        const SizedBox(width: 20),
                        _buildLegend(FlowColors.mint, 'Completed Deep Work'),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Weekly Bars (Mon - Sun)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildDayBar('Mon', 0.82, 0.70),
                        _buildDayBar('Tue', 0.76, 0.65),
                        _buildDayBar('Wed', 0.88, 0.85),
                        _buildDayBar('Thu', 0.72, 0.60),
                        _buildDayBar('Fri', 0.90, 0.88),
                        _buildDayBar('Sat', 0.65, 0.50),
                        _buildDayBar('Sun', 0.78, 0.65),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Learning Loop Status Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FlowColors.darkSurface,
                  borderRadius: FlowRadii.cardRadius,
                  border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.sync_rounded, color: FlowColors.cyanLight, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personal Learning Engine Active',
                            style: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Flowstate adapts to your completed focus sessions to predict tomorrow\'s optimal peak.',
                            style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.darkBorder, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accentColor, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            style: FlowTypography.labelSmall(color: FlowColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: FlowTypography.labelSmall(color: FlowColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildDayBar(String day, double readinessRatio, double deepWorkRatio) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Readiness Bar
            Container(
              width: 14,
              height: 110 * readinessRatio,
              decoration: BoxDecoration(
                color: FlowColors.cyan,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 4),
            // Deep Work Bar
            Container(
              width: 14,
              height: 110 * deepWorkRatio,
              decoration: BoxDecoration(
                color: FlowColors.mint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          day,
          style: FlowTypography.labelSmall(color: FlowColors.textSecondary),
        ),
      ],
    );
  }
}
