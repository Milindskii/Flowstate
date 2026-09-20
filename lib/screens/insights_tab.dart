import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Screen 9: Personal Analytics & Patterns
/// Strictly non-medical cognitive performance insights.
class InsightsTab extends StatelessWidget {
  const InsightsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final learning = state.learningEngine;

    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: FlowSpacing.pageMargin(context),
            vertical: 18.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text(
                'Your Patterns',
                style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Continuous rhythm learning from your completions',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 24),

              if (!learning.hasSufficientHistory) ...[
                _buildLearningEmptyState(context, state, accent),
              ] else ...[
                // 2x2 Metric Grid
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        context: context,
                        icon: Icons.access_time_rounded,
                        title: 'Best Focus Window',
                        value: learning.bestFocusWindow,
                        accentColor: accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        context: context,
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
                        context: context,
                        icon: Icons.hourglass_top_rounded,
                        title: 'Avg Deep Work',
                        value: learning.averageDeepWork,
                        accentColor: FlowColors.iceBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        context: context,
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
                  style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: FlowColors.surface(context),
                    borderRadius: FlowRadii.cardLargeRadius,
                    border: Border.all(color: FlowColors.border(context), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: FlowColors.softShadow(context),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Legend
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 20,
                        runSpacing: 8,
                        children: [
                          _buildLegend(context, accent, 'Readiness'),
                          _buildLegend(context, FlowColors.mint, 'Completed Deep Work'),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Weekly Bars (Mon - Sun)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildDayBar(context, 'Mon', 0.82, 0.70, accent),
                          _buildDayBar(context, 'Tue', 0.76, 0.65, accent),
                          _buildDayBar(context, 'Wed', 0.88, 0.85, accent),
                          _buildDayBar(context, 'Thu', 0.72, 0.60, accent),
                          _buildDayBar(context, 'Fri', 0.90, 0.88, accent),
                          _buildDayBar(context, 'Sat', 0.65, 0.50, accent),
                          _buildDayBar(context, 'Sun', 0.78, 0.65, accent),
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
                    color: FlowColors.surface(context),
                    borderRadius: FlowRadii.cardRadius,
                    border: Border.all(color: FlowColors.border(context), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: FlowColors.softShadow(context),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.sync_rounded, color: accent, size: 24),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Personal Learning Engine Active',
                              style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Flowstate adapts to your completed focus sessions to predict tomorrow\'s optimal peak.',
                              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLearningEmptyState(BuildContext context, AppStateProvider state, Color accent) {
    final historyCount = state.learningEngine.history.length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'LEARNING YOUR RHYTHM',
                style: FlowTypography.badgeText(color: accent).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Gathering your pattern data',
            style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Flowstate never fabricates metrics. Complete 2–3 focus sessions from Today to calibrate your optimal focus window, actual deep work velocity, and circadian energy peaks.',
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildRequirementItem(
            context: context,
            icon: Icons.check_circle_outline_rounded,
            title: 'Logged focus sessions',
            status: '$historyCount / 2 completed',
            isDone: historyCount >= 2,
            accent: accent,
          ),
          const SizedBox(height: 10),
          _buildRequirementItem(
            context: context,
            icon: Icons.access_time_rounded,
            title: 'Circadian wake baseline',
            status: '${state.personalData.wakeTime} recorded',
            isDone: true,
            accent: accent,
          ),
          const SizedBox(height: 10),
          _buildRequirementItem(
            context: context,
            icon: Icons.timeline_rounded,
            title: 'Focus curve calibration',
            status: historyCount > 0 ? 'Calibrating...' : 'Awaiting first session',
            isDone: false,
            accent: accent,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                FlowHaptics.lightTap();
                state.setNavIndex(0);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FlowColors.textInverse,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                  borderRadius: FlowRadii.buttonRadius,
                ),
              ),
              child: Text(
                'Go to Today plan',
                style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String status,
    required bool isDone,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.inputRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDone ? FlowColors.successOf(context) : FlowColors.textMutedOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            status,
            style: FlowTypography.labelSmall(
              color: isDone ? FlowColors.successOf(context) : FlowColors.textMutedOf(context),
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accentColor, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
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
          style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
        ),
      ],
    );
  }

  Widget _buildDayBar(BuildContext context, String day, double readinessRatio, double deepWorkRatio, Color accent) {
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
                color: accent,
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
          style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)),
        ),
      ],
    );
  }
}
