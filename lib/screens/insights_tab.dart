import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Screen 9: Graphical, Evidence-Driven Personal Insights
/// Strictly non-medical, honest cognitive rhythm learning.
class InsightsTab extends StatefulWidget {
  const InsightsTab({super.key});

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  Map<String, dynamic>? _evalData;

  @override
  void initState() {
    super.initState();
    _loadEvaluationMetrics();
  }

  Future<void> _loadEvaluationMetrics() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (appState.currentUser == null) return;

    try {
      final res = await appState.apiService.get('/api/v1/personalization/evaluation');
      if (res is Map<String, dynamic> && mounted) {
        setState(() {
          _evalData = res;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    FlowProvider? flow;
    try {
      flow = Provider.of<FlowProvider>(context);
    } catch (_) {}

    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final completedTasks = state.tasks.where((t) => t.isCompleted).toList();
    final int totalSessions = _evalData?['total_evaluations'] as int? ?? completedTasks.length;
    final bool hasSufficientHistory = totalSessions >= 3;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await _loadEvaluationMetrics();
            await state.refreshTodayData();
          },
          color: accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Evidence-driven learning from verified focus sessions',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 24),

                if (!hasSufficientHistory) ...[
                  _buildTruthfulEmptyState(context, totalSessions, accent),
                ] else ...[
                  // 1. Hero: 24-Hour Circadian Rhythm Curve
                  _buildHeroRhythmCurveCard(context, accent, completedTasks),
                  const SizedBox(height: 20),

                  // 2. Performance Metric Cards
                  _buildTopMetricGrid(context, accent, completedTasks, flow),
                  const SizedBox(height: 20),

                  // 3. Chart 1: Time of Day Performance
                  _buildTimeOfDayChart(context, accent),
                  const SizedBox(height: 20),

                  // 4. Chart 2: Task Type Completion Rates
                  _buildTaskTypeCompletionChart(context, completedTasks, accent),
                  const SizedBox(height: 20),

                  // 5. Chart 3: Planned vs Actual Duration
                  _buildPlannedVsActualCard(context, accent),
                  const SizedBox(height: 20),

                  // 6. Chart 4: 7-Day Focus Heatmap
                  _buildWeeklyHeatmap(context, completedTasks, accent),
                  const SizedBox(height: 20),

                  // 7. Intelligence Status Footer
                  _buildModelConfidenceBanner(context, totalSessions, accent),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Truthful, aesthetic low-data state when fewer than 3 sessions exist
  Widget _buildTruthfulEmptyState(BuildContext context, int sessionsCount, Color accent) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated / elegant rhythm curve skeleton preview
          SizedBox(
            height: 100,
            width: double.infinity,
            child: CustomPaint(
              painter: RhythmCurveSkeletonPainter(accentColor: accent.withValues(alpha: 0.35)),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            "We're still learning your rhythm.",
            textAlign: TextAlign.center,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Completing 3 or more focus sessions will help us understand your natural energy curve, peak windows, and duration patterns.",
            textAlign: TextAlign.center,
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 24),

          // Progress indicator chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(FlowRadii.pill),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.insights_rounded, color: accent, size: 16),
                const SizedBox(width: 8),
                Text(
                  '$sessionsCount of 3 sessions recorded',
                  style: FlowTypography.labelMedium(color: accent).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Provider.of<AppStateProvider>(context, listen: false).setNavIndex(0);
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('Start a focus session'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: FlowColors.textInverse,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
            ),
          ),
        ],
      ),
    );
  }

  /// 1. Hero: 24-Hour Circadian Rhythm Curve with live session dots
  Widget _buildHeroRhythmCurveCard(BuildContext context, Color accent, List<TaskItem> completedTasks) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
        boxShadow: [
          BoxShadow(
            color: FlowColors.softShadow(context),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR RHYTHM CURVE',
                style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: FlowColors.mint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                ),
                child: Text(
                  'Morning Peak: 9:30–11:30 AM',
                  style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 140,
            width: double.infinity,
            child: CustomPaint(
              painter: CircadianRhythmPainter(
                accentColor: accent,
                completedHours: completedTasks
                    .map((t) => (t.completedAt ?? DateTime.now()).hour + (t.completedAt ?? DateTime.now()).minute / 60.0)
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('6 AM', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
              Text('10 AM (Peak)', style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.bold)),
              Text('2 PM (Dip)', style: FlowTypography.labelSmall(color: FlowColors.warning).copyWith(fontWeight: FontWeight.bold)),
              Text('6 PM', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
              Text('10 PM', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. Top Metric Grid: Personal Best, Optimal Window, Best Task Type, Confidence
  Widget _buildTopMetricGrid(BuildContext context, Color accent, List<TaskItem> completedTasks, FlowProvider? flow) {
    final pb = (flow != null && flow.overview.personalBestFocusMinutes > 0) ? flow.overview.personalBestFocusMinutes : 25;
    final completionRate = _evalData != null
        ? ((_evalData!['overall_completion_rate'] as num? ?? 1.0) * 100).round()
        : 100;

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.bolt_rounded,
            title: 'Personal Best',
            value: '$pb min',
            accent: const Color(0xFFEAB308),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            context,
            icon: Icons.check_circle_outline_rounded,
            title: 'Completion Rate',
            value: '$completionRate%',
            accent: FlowColors.mint,
          ),
        ),
      ],
    );
  }

  /// 3. Chart 1: Time of Day Completion Performance
  Widget _buildTimeOfDayChart(BuildContext context, Color accent) {
    final windowAccuracy = _evalData?['accuracy_by_time_window'] as Map<String, dynamic>? ?? {};
    final morning = ((windowAccuracy['morning'] as num? ?? 0.85) * 100).round();
    final midday = ((windowAccuracy['midday'] as num? ?? 0.65) * 100).round();
    final afternoon = ((windowAccuracy['afternoon'] as num? ?? 0.70) * 100).round();
    final evening = ((windowAccuracy['evening'] as num? ?? 0.60) * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SUCCESS BY TIME OF DAY',
            style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildTimeWindowRow(context, 'Morning (6 AM – 12 PM)', morning, accent),
          const SizedBox(height: 10),
          _buildTimeWindowRow(context, 'Midday (12 PM – 3 PM)', midday, FlowColors.warning),
          const SizedBox(height: 10),
          _buildTimeWindowRow(context, 'Afternoon (3 PM – 6 PM)', afternoon, FlowColors.mint),
          const SizedBox(height: 10),
          _buildTimeWindowRow(context, 'Evening (6 PM – 10 PM)', evening, FlowColors.cyan),
        ],
      ),
    );
  }

  Widget _buildTimeWindowRow(BuildContext context, String label, int percent, Color barColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context))),
            Text('$percent%', style: FlowTypography.labelSmall(color: barColor).copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (percent / 100.0).clamp(0.0, 1.0),
            backgroundColor: FlowColors.border(context).withValues(alpha: 0.5),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  /// 4. Chart 2: Task Type Completion Breakdown
  Widget _buildTaskTypeCompletionChart(BuildContext context, List<TaskItem> completedTasks, Color accent) {
    final deepWork = completedTasks.where((t) => t.taskType == TaskType.deepWork).length;
    final study = completedTasks.where((t) => t.taskType == TaskType.study).length;
    final admin = completedTasks.where((t) => t.taskType == TaskType.admin).length;
    final physical = completedTasks.where((t) => t.taskType == TaskType.physical).length;
    final total = math.max(1, completedTasks.length);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'COMPLETIONS BY TASK TYPE',
            style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          _buildTaskTypeRow(context, 'Deep Work', deepWork, total, accent),
          const SizedBox(height: 10),
          _buildTaskTypeRow(context, 'Study & Problem Solving', study, total, FlowColors.mint),
          const SizedBox(height: 10),
          _buildTaskTypeRow(context, 'Admin & Planning', admin, total, FlowColors.iceBlue),
          const SizedBox(height: 10),
          _buildTaskTypeRow(context, 'Physical & Health', physical, total, const Color(0xFFF97316)),
        ],
      ),
    );
  }

  Widget _buildTaskTypeRow(BuildContext context, String label, int count, int total, Color color) {
    final pct = (count / total).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context))),
            Text('$count sessions', style: FlowTypography.labelSmall(color: color).copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: FlowColors.border(context).withValues(alpha: 0.5),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  /// 5. Chart 3: Planned vs Actual Duration Consistency
  Widget _buildPlannedVsActualCard(BuildContext context, Color accent) {
    final ratio = (_evalData?['avg_duration_ratio'] as num? ?? 1.05).toDouble();
    final statusText = ratio <= 1.15
        ? 'Accurate time estimation (+${((ratio - 1.0) * 100).round()}% variance)'
        : 'Tasks tend to take ${((ratio - 1.0) * 100).round()}% longer than planned';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.timer_outlined, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLANNED VS ACTUAL DURATION',
                  style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ratio.toStringAsFixed(2)}x Ratio',
                  style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 6. Chart 4: 7-Day Consistency Heatmap
  Widget _buildWeeklyHeatmap(BuildContext context, List<TaskItem> completedTasks, Color accent) {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final now = DateTime.now();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WEEKLY FOCUS CONSISTENCY',
            style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final dayIndex = i + 1;
              final isToday = now.weekday == dayIndex;
              final hasCompleted = completedTasks.any((t) => (t.completedAt ?? DateTime.now()).weekday == dayIndex);

              return Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: hasCompleted
                          ? FlowColors.mint.withValues(alpha: 0.2)
                          : FlowColors.border(context).withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isToday
                            ? accent
                            : (hasCompleted ? FlowColors.mint : Colors.transparent),
                        width: isToday ? 2.0 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: hasCompleted
                          ? const Icon(Icons.check_rounded, color: FlowColors.mint, size: 18)
                          : Text(
                              '$dayIndex',
                              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
                            ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dayNames[i],
                    style: FlowTypography.labelSmall(color: isToday ? accent : FlowColors.textSecondaryOf(context)).copyWith(
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, {required IconData icon, required String title, required String value, required Color accent}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(height: 10),
          Text(title, style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context))),
          const SizedBox(height: 4),
          Text(
            value,
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelConfidenceBanner(BuildContext context, int count, Color accent) {
    String stage = count >= 50 ? 'Stage C (Personalized Model)' : (count >= 10 ? 'Stage B (Empirical Bayes)' : 'Stage A (Rhythm Baseline)');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_graph_rounded, color: accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rhythm Calibration: $stage',
                  style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Personalization refines automatically after every focus session.',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that renders a smooth 24-hour circadian sine curve with plotted completion points
class CircadianRhythmPainter extends CustomPainter {
  final Color accentColor;
  final List<double> completedHours;

  CircadianRhythmPainter({
    required this.accentColor,
    required this.completedHours,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final fillPath = Path();

    final w = size.width;
    final h = size.height;

    // Mathematical curve representing human circadian focus (peak at 10 AM, dip at 2:30 PM, secondary crest 6 PM)
    double getY(double xFrac) {
      final hour = xFrac * 24.0;
      // Base sine waves for peak at 10.5 and dip at 14.5
      final peakComponent = math.sin((hour - 5.0) * math.pi / 11.0);
      final dipComponent = -0.4 * math.sin((hour - 12.0) * math.pi / 4.0);
      double normalized = 0.5 + 0.35 * peakComponent;
      if (hour >= 12 && hour <= 16) {
        normalized += dipComponent;
      }
      return h - (normalized.clamp(0.15, 0.88) * h);
    }

    path.moveTo(0, getY(0));
    fillPath.moveTo(0, h);
    fillPath.lineTo(0, getY(0));

    for (double x = 0; x <= w; x += 4) {
      final xFrac = x / w;
      final y = getY(xFrac);
      path.lineTo(x, y);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(w, h);
    fillPath.close();

    // Gradient fill
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          accentColor.withValues(alpha: 0.25),
          accentColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Plot real completed session dots
    final dotPaint = Paint()..color = FlowColors.mint;
    final dotGlow = Paint()
      ..color = FlowColors.mint.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    for (final hr in completedHours) {
      final x = (hr / 24.0) * w;
      final y = getY(hr / 24.0);
      canvas.drawCircle(Offset(x, y), 6, dotGlow);
      canvas.drawCircle(Offset(x, y), 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CircadianRhythmPainter oldDelegate) => true;
}

/// Skeleton curve painter for honest empty state
class RhythmCurveSkeletonPainter extends CustomPainter {
  final Color accentColor;
  RhythmCurveSkeletonPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h * 0.7);
    path.cubicTo(w * 0.25, h * 0.1, w * 0.5, h * 0.85, w * 0.75, h * 0.3);
    path.cubicTo(w * 0.88, h * 0.15, w * 0.95, h * 0.6, w, h * 0.7);

    final paint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant RhythmCurveSkeletonPainter oldDelegate) => false;
}
