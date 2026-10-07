import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../components/noya_companion_view.dart';
import '../components/noya_motion_view.dart';
import '../models/history_days.dart';
import '../models/task_reflection.dart';
import '../providers/app_state_provider.dart';
import '../services/flow_clock.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Opens History from Insights: older days, one line each, explorable without crowding Insights.
Future<void> openInsightsHistory(BuildContext context) {
  // The route carries the caller's state along, whichever level of the tree provides it.
  final state = Provider.of<AppStateProvider>(context, listen: false);
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => ChangeNotifierProvider<AppStateProvider>.value(value: state, child: const InsightsHistoryScreen()),
  ));
}

/// Every day the user finished something, newest first. Each day is a strip of its own hours —
/// a dot where each task was finished, shaded by how it felt — and opens into what was done,
/// when, how long it took, and how it compared to the plan.
class InsightsHistoryScreen extends StatefulWidget {
  const InsightsHistoryScreen({super.key});

  @override
  State<InsightsHistoryScreen> createState() => _InsightsHistoryScreenState();
}

enum HistoryFilter { all, week, month }

class _InsightsHistoryScreenState extends State<InsightsHistoryScreen> {
  DateTime? _open;
  HistoryFilter _filter = HistoryFilter.all;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadHistory();
    });
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    final state = Provider.of<AppStateProvider>(context, listen: false);
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        state.reflectionsReady,
        state.loadUserTasks(),
        state.refreshTodayData(),
      ]);
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final accent = Theme.of(context).colorScheme.primary;
    final allDays = HistoryDay.from(tasks: state.tasks, reflections: state.reflections);
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);

    final days = allDays.where((d) {
      if (_filter == HistoryFilter.all) return true;
      final diff = today.difference(d.date).inDays;
      if (_filter == HistoryFilter.week) return diff <= 7;
      if (_filter == HistoryFilter.month) return diff <= 30;
      return true;
    }).toList();

    final totalTasks = allDays.fold<int>(0, (sum, d) => sum + d.entries.length);
    final totalMinutes = allDays.fold<int>(0, (sum, d) => sum + d.totalMinutes);

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: FlowColors.textPrimaryOf(context),
        title: Text(
          'History',
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: accent,
        child: allDays.isEmpty
            ? const SingleChildScrollView(
                physics: AlwaysScrollableScrollPhysics(),
                child: _NoHistory(),
              )
            : ListView.separated(
                key: const Key('insights_history_list'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(FlowSpacing.pageMargin(context), 4, FlowSpacing.pageMargin(context), 48),
                itemCount: days.length + 1,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Overview Stats Card
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: FlowColors.surface(context),
                            borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
                            border: Border.all(color: FlowColors.border(context)),
                            boxShadow: [
                              BoxShadow(
                                color: FlowColors.softShadow(context),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.auto_graph_rounded, size: 16, color: accent),
                                  const SizedBox(width: 6),
                                  Text(
                                    'COMPLETION OVERVIEW',
                                    style: FlowTypography.badgeText(color: accent).copyWith(
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_isLoading)
                                    SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MetricTile(
                                      label: 'Finished',
                                      value: '$totalTasks',
                                      unit: totalTasks == 1 ? 'task' : 'tasks',
                                    ),
                                  ),
                                  Container(width: 1, height: 36, color: FlowColors.border(context)),
                                  Expanded(
                                    child: _MetricTile(
                                      label: 'Focus Time',
                                      value: _minutes(totalMinutes),
                                      unit: 'total',
                                    ),
                                  ),
                                  Container(width: 1, height: 36, color: FlowColors.border(context)),
                                  Expanded(
                                    child: _MetricTile(
                                      label: 'Active Days',
                                      value: '${allDays.length}',
                                      unit: allDays.length == 1 ? 'day' : 'days',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Timeframe Filter Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _FilterChip(
                                label: 'All Time',
                                selected: _filter == HistoryFilter.all,
                                onTap: () => setState(() => _filter = HistoryFilter.all),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Last 7 Days',
                                selected: _filter == HistoryFilter.week,
                                onTap: () => setState(() => _filter = HistoryFilter.week),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: 'Last 30 Days',
                                selected: _filter == HistoryFilter.month,
                                onTap: () => setState(() => _filter = HistoryFilter.month),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        Text(
                          '${days.length} ${days.length == 1 ? 'day' : 'days'} with finished work. Tap a day to open it.',
                          style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }
                  final day = days[i - 1];
                  final open = _open == day.date;
                  return _DayRow(
                    day: day,
                    today: today,
                    open: open,
                    onToggle: () {
                      FlowHaptics.selection();
                      setState(() => _open = open ? null : day.date);
                    },
                    onOpenInCalendar: () {
                      FlowHaptics.lightTap();
                      state.loadCalendarDay(day.date);
                      state.setNavIndex(2);
                      Navigator.of(context).maybePop();
                    },
                  );
                },
              ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _MetricTile({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontSize: 11),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: () {
        FlowHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(FlowRadii.pill),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : FlowColors.surface(context),
          borderRadius: BorderRadius.circular(FlowRadii.pill),
          border: Border.all(
            color: selected ? accent : FlowColors.border(context),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: FlowTypography.labelSmall(
            color: selected ? accent : FlowColors.textSecondaryOf(context),
          ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
      ),
    );
  }
}

String _dayTitle(DateTime date, DateTime today) {
  final diff = today.difference(date).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(date.year == today.year ? 'EEEE, MMM d' : 'EEE, MMM d, yyyy').format(date);
}

String _minutes(int m) {
  final h = m ~/ 60;
  final r = m % 60;
  if (h == 0) return '$r min';
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

class _DayRow extends StatelessWidget {
  final HistoryDay day;
  final DateTime today;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onOpenInCalendar;

  const _DayRow({required this.day, required this.today, required this.open, required this.onToggle, required this.onOpenInCalendar});

  @override
  Widget build(BuildContext context) {
    final count = day.entries.length;
    final feeling = day.averageFeeling;
    final summary = [
      '$count finished',
      _minutes(day.totalMinutes),
      if (feeling != null) 'felt ${TaskReflection.feelingLabel(feeling.round()).toLowerCase()}',
    ].join(' · ');
    final duration = FlowMotion.responsiveDuration(context, FlowMotion.standardDuration);

    final details = open ? _DayDetails(day: day, onOpenInCalendar: onOpenInCalendar) : const SizedBox(width: double.infinity);

    return Container(
      key: Key('history_day_${DateFormat('yyyy-MM-dd').format(day.date)}'),
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: BorderRadius.circular(FlowRadii.card),
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
          Semantics(
            button: true,
            expanded: open,
            label: '${_dayTitle(day.date, today)}, $summary',
            excludeSemantics: true,
            onTap: onToggle,
            child: InkWell(
              borderRadius: BorderRadius.circular(FlowRadii.card),
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _dayTitle(day.date, today),
                            style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        AnimatedRotation(
                          turns: open ? 0.5 : 0,
                          duration: duration,
                          curve: FlowMotion.easeOut,
                          child: Icon(Icons.expand_more_rounded, color: FlowColors.textMutedOf(context)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    const SizedBox(height: 12),
                    _DayStrip(day: day),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(height: 1, color: FlowColors.border(context)),
            ),
          // Zero-duration AnimatedSize throws under disabled animations, so it only wraps real motion.
          if (duration == Duration.zero)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: details)
          else
            AnimatedSize(
              duration: duration,
              curve: FlowMotion.easeOut,
              alignment: Alignment.topCenter,
              child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: details),
            ),
        ],
      ),
    );
  }
}

/// The day's hours, 5 AM to 5 AM, with one dot per finished task at the time it was finished.
/// Reflected tasks are filled, shaded by how they felt; the rest are open rings.
class _DayStrip extends StatelessWidget {
  final HistoryDay day;

  const _DayStrip({required this.day});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        SizedBox(
          height: 18,
          width: double.infinity,
          child: CustomPaint(
            painter: _StripPainter(
              entries: day.entries,
              accent: accent,
              track: FlowColors.border(context),
              ring: FlowColors.textMutedOf(context),
              surface: FlowColors.background(context),
              dark: FlowColors.isDark(context),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final label in const ['5a', '11a', '5p', '11p'])
              Expanded(
                child: Text(label, style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontSize: 10)),
              ),
          ],
        ),
      ],
    );
  }
}

/// Position of a time on a 5 AM → 5 AM day, 0–1.
double dayFraction(DateTime t) => (((t.hour - 5) % 24) * 60 + t.minute) / (24 * 60);

class _StripPainter extends CustomPainter {
  final List<HistoryEntry> entries;
  final Color accent;
  final Color track;
  final Color ring;
  final Color surface;
  final bool dark;

  _StripPainter({
    required this.entries,
    required this.accent,
    required this.track,
    required this.ring,
    required this.surface,
    required this.dark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final cy = size.height / 2;
    final w = size.width - pad * 2;
    final trackPaint = Paint()
      ..color = track
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pad, cy), Offset(size.width - pad, cy), trackPaint);
    for (var q = 1; q < 4; q++) {
      final x = pad + w * q / 4;
      canvas.drawLine(Offset(x, cy - 4), Offset(x, cy + 4), trackPaint..strokeWidth = 1);
    }
    final steps = dark ? const {1: 0.4, 2: 0.58, 3: 0.78, 4: 1.0} : const {1: 0.3, 2: 0.5, 3: 0.72, 4: 1.0};
    for (final e in entries) {
      final c = Offset(pad + w * dayFraction(e.completedAt), cy);
      canvas.drawCircle(c, 7, Paint()..color = surface);
      final r = e.reflection;
      if (r == null) {
        canvas.drawCircle(
          c,
          4.5,
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      } else {
        canvas.drawCircle(c, 5.5, Paint()..color = accent.withValues(alpha: steps[r.feeling.clamp(1, 4)]));
      }
    }
  }

  @override
  bool shouldRepaint(_StripPainter old) =>
      old.entries != entries || old.accent != accent || old.track != track || old.surface != surface || old.dark != dark;
}

class _DayDetails extends StatelessWidget {
  final HistoryDay day;
  final VoidCallback onOpenInCalendar;

  const _DayDetails({required this.day, required this.onOpenInCalendar});

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('h:mm a');
    final versus = day.minutesVersusPlan;
    final muted = FlowColors.textMutedOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in day.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      time.format(e.completedAt),
                      style: FlowTypography.bodySmall(color: muted).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          [
                            '${e.minutes} min',
                            if (e.category != null) e.category!,
                            if (e.reflection != null) 'felt ${TaskReflection.feelingLabel(e.reflection!.feeling).toLowerCase()}',
                          ].join(' · '),
                          style: FlowTypography.bodySmall(color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (versus != null) ...[
            const SizedBox(height: 6),
            Text(
              versus.abs() <= 5
                  ? 'Reflected tasks ran close to plan.'
                  : (versus > 0 ? 'Reflected tasks ran $versus min over plan in total.' : 'Reflected tasks finished ${-versus} min under plan in total.'),
              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
            ),
          ],
          const SizedBox(height: 4),
          TextButton.icon(
            key: Key('history_open_calendar_${DateFormat('yyyy-MM-dd').format(day.date)}'),
            onPressed: onOpenInCalendar,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8)),
            icon: const Icon(Icons.route_rounded, size: 18),
            label: const Text('See this day in Calendar'),
          ),
        ],
      ),
    );
  }
}

class _NoHistory extends StatelessWidget {
  const _NoHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('insights_history_empty'),
      padding: EdgeInsets.symmetric(horizontal: FlowSpacing.pageMargin(context), vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const NoyaMotionView(pose: NoyaState.thinking, mood: NoyaMood.thinking, size: 72, enter: true),
          const SizedBox(height: 12),
          Text(
            'No finished days yet.',
            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'When you finish a task, its day appears here with when you did it and how it felt.',
            style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
          ),
        ],
      ),
    );
  }
}
