import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../components/noya_companion_view.dart';
import '../components/noya_motion_view.dart';
import '../models/insights_snapshot.dart';
import '../models/task_reflection.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../services/flow_clock.dart';
import 'insights_history_screen.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Screen 9: Insights — what the user's days are teaching Flowstate.
///
/// Personal, not a dashboard: every chart and statement comes from data the app really has
/// (completions with a recorded time, reflections stored on this device, planned slots,
/// readiness, and — once it has evaluations — the account's personalization metrics). A section
/// only appears when there is enough data behind it; what is still missing is listed once, at
/// the end, under what Flowstate has learned.
class InsightsTab extends StatefulWidget {
  const InsightsTab({super.key});

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends State<InsightsTab> {
  Map<String, dynamic>? _evalData;

  /// `history` from GET /insights/summary: real account-wide patterns (routines, postponement, week trend).
  /// Every section is either "ready" with its sample size or an honest "learning" state.
  Map<String, dynamic>? _history;

  InsightsSnapshot? _snapshot;
  int? _snapshotKey;

  @override
  void initState() {
    super.initState();
    _loadEvaluationMetrics();
  }

  /// Both server reads in parallel (one round trip of latency, not two).
  Future<void> _loadEvaluationMetrics() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (appState.currentUser == null) return;

    Future<void> eval() async {
      try {
        final res = await appState.apiService.get('/api/v1/personalization/evaluation');
        if (res is Map<String, dynamic> && mounted) setState(() => _evalData = res);
      } catch (_) {}
    }

    Future<void> history() async {
      try {
        final res = await appState.apiService.get('/api/v1/insights/summary');
        final h = res is Map<String, dynamic> ? res['history'] : null;
        if (h is Map<String, dynamic> && mounted) setState(() => _history = h);
      } catch (_) {}
    }

    await Future.wait([eval(), history()]);
  }

  /// The snapshot is recomputed only when what it reads changed (not on every provider notify).
  InsightsSnapshot _snapshotFor(AppStateProvider state, DateTime now) {
    final tasks = state.tasks;
    final reflections = state.reflections;
    final key = Object.hash(
      Object.hashAll(tasks.map((t) => Object.hash(t.id, t.isCompleted, t.completedAt, t.scheduledStart, t.durationMinutes))),
      Object.hashAll(reflections.map((r) => Object.hash(r.taskId, r.completedAt))),
      DateTime(now.year, now.month, now.day, now.hour),
    );
    if (_snapshot == null || key != _snapshotKey) {
      _snapshot = InsightsSnapshot.compute(tasks: tasks, reflections: reflections, now: now);
      _snapshotKey = key;
    }
    return _snapshot!;
  }

  Map<String, dynamic>? _ready(String section) {
    final s = _history?[section];
    return s is Map<String, dynamic> && s['status'] == 'ready' ? s : null;
  }

  int get _evaluations => (_evalData?['total_evaluations'] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    Color accent = Theme.of(context).colorScheme.primary;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final now = FlowClock().now;
    final snapshot = _snapshotFor(state, now);
    final routines = _ready('routines');
    final postponement = _ready('postponement');
    final completion = _ready('completion');
    final accountRatio = _evaluations >= 3 ? (_evalData?['avg_duration_ratio'] as num?)?.toDouble() : null;

    final sections = <Widget>[
      if (snapshot.hasAnyHistory) _Consistency(snapshot: snapshot, accent: accent, now: now),
      if (snapshot.timedCompletions >= InsightsSnapshot.minTimedCompletions) _TimeOfDay(snapshot: snapshot, reflections: state.reflections, accent: accent, now: now),
      if (snapshot.plannedVsActual != null || accountRatio != null)
        _PlannedVsActual(snapshot: snapshot, accent: accent, accountRatio: accountRatio),
      if (snapshot.averages != null) _HowItFelt(snapshot: snapshot, accent: accent),
      if (snapshot.hasFollowThrough) _FollowThrough(snapshot: snapshot, accent: accent),
      if (completion != null && completion['last_week'] != null) _WeekTrend(data: completion, accent: accent),
      if (routines != null) _Routines(data: routines, accent: accent),
      if (postponement != null) _Postponement(data: postponement, accent: accent),
    ];

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
            padding: EdgeInsets.symmetric(horizontal: FlowSpacing.pageMargin(context), vertical: 18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your patterns',
                        style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    // Older days live one step away, so this screen stays about meaning.
                    TextButton.icon(
                      key: const Key('insights_history_button'),
                      onPressed: () => openInsightsHistory(context),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        textStyle: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w700),
                      ),
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('History'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'What your days are teaching Flowstate',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 20),
                if (!snapshot.hasAnyHistory && routines == null && postponement == null)
                  _StillLearning(accent: accent)
                else ...[
                  _Headline(snapshot: snapshot),
                  for (final s in sections) ...[const _Rule(), s],
                  const _Rule(),
                  _Learned(
                      state: state,
                      snapshot: snapshot,
                      evaluations: _evaluations,
                      evalData: _evalData,
                      history: _history,
                      accent: accent),
                ],
                const SizedBox(height: 16),
                Text(
                  'Reflections are kept on this device and synced to your account. Patterns only appear once there is enough real history behind them.',
                  key: const Key('insights_data_note'),
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Layout pieces ───────────────────────────────────────────────────────────────────────────

/// Sections are separated by a hairline and air, not boxed in cards.
class _Rule extends StatelessWidget {
  const _Rule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Divider(height: 1, thickness: 1, color: FlowColors.border(context)),
      );
}

class _Section extends StatelessWidget {
  final String title;
  final String? finding;
  final Widget child;

  const _Section({super.key, required this.title, this.finding, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
        ),
        if (finding != null) ...[
          const SizedBox(height: 4),
          Text(finding!, style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(height: 1.4)),
        ],
        const SizedBox(height: 16),
        child,
      ],
    );
  }
}

/// A short muted caption under a chart.
class _Caption extends StatelessWidget {
  final String text;

  const _Caption(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(text, style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
      );
}

/// Muted ink for de-emphasised marks: one step off the surface, readable in both themes.
Color _quiet(BuildContext context) => FlowColors.textMutedOf(context).withValues(alpha: FlowColors.isDark(context) ? 0.45 : 0.35);

class _Headline extends StatelessWidget {
  final InsightsSnapshot snapshot;

  const _Headline({required this.snapshot});

  String get _subline {
    final last = snapshot.completionsLastWeek;
    if (snapshot.completionsThisWeek == 0) return 'Last week you finished $last. A fresh start is one task away.';
    if (last == 0) return 'Nothing was recorded last week, so this is your baseline.';
    final diff = snapshot.completionsThisWeek - last;
    if (diff == 0) return 'Level with last week ($last).';
    return diff > 0 ? '$diff more than last week ($last).' : 'Last week: $last. The week is not over.';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('insights_hero'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          snapshot.headline,
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        Text(_subline, style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
      ],
    );
  }
}

class _StillLearning extends StatelessWidget {
  final Color accent;

  const _StillLearning({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('insights_still_learning'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const NoyaMotionView(key: Key('insights_noya'), pose: NoyaState.thinking, mood: NoyaMood.thinking, size: 72, enter: true),
        const SizedBox(height: 12),
        Text(
          "We're still learning your rhythm.",
          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'Finish and reflect on a few tasks. Flowstate will chart when you get things done, how long tasks really take, and how your sessions feel. Nothing here is estimated.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Provider.of<AppStateProvider>(context, listen: false).setNavIndex(0),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Start a focus session'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: FlowColors.textInverse,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
          ),
        ),
      ],
    );
  }
}

// ── Consistency: last two weeks ──────────────────────────────────────────────────────────────

class _Consistency extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final Color accent;
  final DateTime now;

  const _Consistency({required this.snapshot, required this.accent, required this.now});

  @override
  Widget build(BuildContext context) {
    final today = DateTime(now.year, now.month, now.day);
    final lastMonday = today.subtract(Duration(days: today.weekday - 1 + 7));
    final todayIndex = 7 + today.weekday - 1;
    final counts = snapshot.fortnightCounts;
    final peak = counts.fold<int>(0, math.max);
    final peakIndex = peak == 0 ? -1 : counts.lastIndexOf(peak);
    const initials = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return _Section(
      key: const Key('insights_week'),
      title: 'Consistency',
      finding: snapshot.activeDaysThisWeek == 0
          ? 'No finished tasks yet this week.'
          : 'Active on ${snapshot.activeDaysThisWeek} of ${today.weekday} days this week.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Columns(
            height: 96,
            values: counts,
            colorFor: (i) => i >= 7 ? accent : _quiet(context),
            labelFor: (i) => (i == peakIndex || (i == todayIndex && counts[i] > 0)) ? '${counts[i]}' : null,
            keyFor: (i) => i >= 7 ? Key('insights_day_${i - 7}_${counts[i]}') : null,
            tooltipFor: (i) {
              final day = lastMonday.add(Duration(days: i));
              return '${DateFormat('EEE d MMM').format(day)}: ${counts[i]} finished';
            },
            dimFrom: todayIndex + 1,
            groupGapAfter: 6,
            axis: [for (var i = 0; i < 14; i++) initials[i % 7]],
            emphasisAxis: todayIndex,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _Key(color: _quiet(context), text: 'Last week · ${snapshot.completionsLastWeek}')),
              Expanded(child: _Key(color: accent, text: 'This week · ${snapshot.completionsThisWeek}')),
            ],
          ),
          if (snapshot.completionsWithoutTime > 0)
            _Caption(
              '${snapshot.completionsWithoutTime} finished ${snapshot.completionsWithoutTime == 1 ? 'task has' : 'tasks have'} no recorded time and ${snapshot.completionsWithoutTime == 1 ? "isn't" : "aren't"} charted.',
            ),
        ],
      ),
    );
  }
}

// ── Time of day ─────────────────────────────────────────────────────────────────────────────

class _TimeOfDay extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final List<TaskReflection> reflections;
  final Color accent;
  final DateTime now;

  const _TimeOfDay({required this.snapshot, required this.reflections, required this.accent, required this.now});

  static String _hour(int h) => h == 0 ? '12 AM' : (h < 12 ? '$h AM' : (h == 12 ? '12 PM' : '${h - 12} PM'));

  @override
  Widget build(BuildContext context) {
    final best = snapshot.bestWindow;
    final hours = snapshot.hourCounts;
    final peak = hours.fold<int>(0, math.max);
    final peakHour = hours.indexOf(peak);
    final reflected = reflections.take(40).toList();

    return _Section(
      key: const Key('insights_windows'),
      title: 'Your rhythm',
      finding: best == null
          ? 'No single part of the day stands out yet.'
          : 'You finish the most in the ${best.label.toLowerCase()} (${best.range}).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: [
              'Tasks finished by time of day.',
              for (final w in DayWindow.values) '${w.label}: ${snapshot.windowCounts[w]}.',
              if (peak > 0) 'Busiest hour ${_hour(peakHour)}.',
            ].join(' '),
            excludeSemantics: true,
            child: _DrawIn(
              child: SizedBox(
                key: const Key('insights_rhythm_curve'),
                height: 168,
                width: double.infinity,
                child: CustomPaint(
                  painter: _RhythmPainter(
                    hours: hours,
                    energies: [for (final r in reflected) (r.completedAt, r.energy)],
                    best: best,
                    now: now,
                    accent: accent,
                    ink: FlowColors.textMutedOf(context),
                    grid: FlowColors.border(context),
                    surface: FlowColors.background(context),
                    labelStyle: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontSize: 10),
                    peakStyle: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Key(color: accent, text: 'Tasks finished'),
              if (reflected.isNotEmpty) _Key(color: accent.withValues(alpha: 0.55), text: 'Energy you reported (larger = more)', round: true),
            ],
          ),
          _Caption([
            for (final w in DayWindow.values) '${w.label} ${snapshot.windowCounts[w]}',
          ].join('  ·  ')),
        ],
      ),
    );
  }
}

/// The day as one curve, 5 AM → 5 AM: finished tasks per hour, smoothed so the shape of the day
/// reads at a glance, over the raw hourly counts as faint ticks (the evidence under the curve).
/// The strongest window is shaded; energy reports sit on a lane below on the same clock.
class _RhythmPainter extends CustomPainter {
  final List<int> hours;
  final List<(DateTime, int)> energies;
  final DayWindow? best;
  final DateTime now;
  final Color accent;
  final Color ink;
  final Color grid;
  final Color surface;
  final TextStyle labelStyle;
  final TextStyle peakStyle;

  _RhythmPainter({
    required this.hours,
    required this.energies,
    required this.best,
    required this.now,
    required this.accent,
    required this.ink,
    required this.grid,
    required this.surface,
    required this.labelStyle,
    required this.peakStyle,
  });

  static const double _laneHeight = 26;
  static const double _axisHeight = 16;
  static const double _top = 20;

  /// x position for an hour of the day (fractional), on a 5 AM → 5 AM axis.
  static double _f(double hour) => ((hour - 5) % 24) / 24;

  void _text(Canvas canvas, String s, TextStyle style, Offset at, {bool center = true}) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: ui.TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(center ? at.dx - tp.width / 2 : at.dx, at.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final w = size.width - pad * 2;
    final baseline = size.height - _axisHeight - _laneHeight;
    final chartH = baseline - _top;
    double x(double hour) => pad + w * _f(hour);

    // Best window band.
    if (best != null) {
      final (from, to) = switch (best!) {
        DayWindow.morning => (5.0, 12.0),
        DayWindow.afternoon => (12.0, 17.0),
        DayWindow.evening => (17.0, 22.0),
        DayWindow.night => (22.0, 29.0),
      };
      canvas.drawRRect(
        RRect.fromLTRBR(x(from), _top - 6, from == 22 ? pad + w : x(to), baseline, const Radius.circular(8)),
        Paint()..color = accent.withValues(alpha: 0.07),
      );
    }

    // Baseline and quarter gridlines.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(pad, baseline), Offset(size.width - pad, baseline), gridPaint);

    // Smoothed curve: circular Gaussian kernel (σ ≈ 1.2 h) over the hourly counts.
    const samples = 96;
    final ys = List<double>.filled(samples + 1, 0);
    for (var i = 0; i <= samples; i++) {
      final hour = 5 + 24 * i / samples;
      var v = 0.0;
      for (var h = 0; h < 24; h++) {
        if (hours[h] == 0) continue;
        var d = ((hour - (h + 0.5)) % 24).abs();
        if (d > 12) d = 24 - d;
        v += hours[h] * math.exp(-(d * d) / (2 * 1.2 * 1.2));
      }
      ys[i] = v;
    }
    final maxY = ys.fold<double>(0, math.max);
    if (maxY > 0) {
      Offset pt(int i) => Offset(pad + w * i / samples, baseline - chartH * ys[i] / maxY);
      final line = Path()..moveTo(pt(0).dx, pt(0).dy);
      for (var i = 1; i <= samples; i++) {
        line.lineTo(pt(i).dx, pt(i).dy);
      }
      final area = Path.from(line)
        ..lineTo(pad + w, baseline)
        ..lineTo(pad, baseline)
        ..close();
      canvas.drawPath(area, Paint()..color = accent.withValues(alpha: 0.12));
      canvas.drawPath(
        line,
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      // Raw hourly evidence as short ticks on the baseline.
      final peakCount = hours.fold<int>(0, math.max);
      for (var h = 0; h < 24; h++) {
        if (hours[h] == 0) continue;
        final cx = x(h + 0.5);
        canvas.drawLine(
          Offset(cx, baseline),
          Offset(cx, baseline - 3 - 7 * hours[h] / peakCount),
          Paint()
            ..color = accent.withValues(alpha: 0.6)
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round,
        );
      }

      // Peak marker with a direct label.
      var peakI = 0;
      for (var i = 1; i <= samples; i++) {
        if (ys[i] > ys[peakI]) peakI = i;
      }
      final p = pt(peakI);
      canvas.drawCircle(p, 6.5, Paint()..color = surface);
      canvas.drawCircle(p, 4.5, Paint()..color = accent);
      final peakHour = (5 + 24 * peakI / samples).floor() % 24;
      final label = peakHour == 0 ? '12 AM' : (peakHour < 12 ? '$peakHour AM' : (peakHour == 12 ? '12 PM' : '${peakHour - 12} PM'));
      final tp = TextPainter(text: TextSpan(text: 'Peak ~$label', style: peakStyle), textDirection: ui.TextDirection.ltr)..layout();
      final lx = (p.dx - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(lx, math.max(0, p.dy - tp.height - 8)));
    }

    // Now: a quiet vertical tick to orient the curve against the current time.
    final nx = x(now.hour + now.minute / 60);
    final dash = Paint()
      ..color = ink.withValues(alpha: 0.6)
      ..strokeWidth = 1;
    for (var y = _top; y < baseline; y += 6) {
      canvas.drawLine(Offset(nx, y), Offset(nx, math.min(y + 3, baseline)), dash);
    }

    // Energy lane: each reflection at the time it was finished, bigger and darker = more energy.
    final laneY = baseline + _laneHeight / 2 + 2;
    canvas.drawLine(Offset(pad, laneY), Offset(size.width - pad, laneY), gridPaint..color = grid.withValues(alpha: 0.6));
    for (final (at, energy) in energies) {
      final c = Offset(x(at.hour + at.minute / 60), laneY);
      final e = energy.clamp(1, 5);
      canvas.drawCircle(c, 2.5 + e * 0.9, Paint()..color = accent.withValues(alpha: 0.2 + 0.15 * e));
    }

    // Axis.
    final axisY = size.height - _axisHeight + 3;
    for (final (h, s) in const [(5, '5a'), (9, '9a'), (13, '1p'), (17, '5p'), (21, '9p'), (1, '1a')]) {
      _text(canvas, s, labelStyle, Offset(x(h.toDouble()), axisY));
    }
  }

  @override
  bool shouldRepaint(_RhythmPainter old) =>
      old.hours != hours || old.energies != energies || old.best != best || old.now != now || old.accent != accent || old.grid != grid;
}

/// One shared entrance for every chart: drawn in from the left, once, when the section mounts.
/// Data never moves after that. Under reduced motion it is simply there.
class _DrawIn extends StatelessWidget {
  final Widget child;

  const _DrawIn({required this.child});

  @override
  Widget build(BuildContext context) {
    if (FlowMotion.isReducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: FlowMotion.emphasized,
      builder: (context, t, child) => ClipRect(clipper: _RevealClipper(t), child: child),
      child: child,
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  final double t;

  _RevealClipper(this.t);

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, -40, size.width * t, size.height + 80);

  @override
  bool shouldReclip(_RevealClipper old) => old.t != t;
}

// ── Planned vs actual ───────────────────────────────────────────────────────────────────────

class _PlannedVsActual extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final Color accent;
  final double? accountRatio;

  const _PlannedVsActual({required this.snapshot, required this.accent, required this.accountRatio});

  @override
  Widget build(BuildContext context) {
    String label;
    String source;
    if (snapshot.plannedVsActualLabel != null) {
      label = snapshot.plannedVsActualLabel!;
      source = 'From ${snapshot.reflectionCount} reflections on this device';
    } else {
      final r = accountRatio!;
      final pct = ((r - 1).abs() * 100).round();
      label = (r >= 0.9 && r <= 1.1)
          ? 'Tasks usually take about as long as planned'
          : (r > 1 ? 'Tasks usually take about $pct% longer than planned' : 'Tasks usually take about $pct% less time than planned');
      source = 'From your account history';
    }

    final pairs = snapshot.durationPairs;
    final maxMinutes = pairs.fold<int>(0, (m, p) => math.max(m, math.max(p.planned, p.actual)));
    final fb = snapshot.durationFeedbackCounts;
    final said = [
      if ((fb['shorter'] ?? 0) > 0) '${fb['shorter']} faster',
      if ((fb['about_right'] ?? 0) > 0) '${fb['about_right']} about right',
      if ((fb['longer'] ?? 0) > 0) '${fb['longer']} longer',
    ];

    return _Section(
      key: const Key('insights_planned'),
      title: 'Planned vs actual',
      finding: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (pairs.isNotEmpty) ...[
            for (final p in pairs) _DurationRow(pair: p, maxMinutes: maxMinutes, accent: accent),
            const SizedBox(height: 6),
            Row(
              children: [
                _Key(color: FlowColors.textMutedOf(context), text: 'Planned', hollow: true),
                const SizedBox(width: 16),
                _Key(color: accent, text: 'Actual'),
              ],
            ),
          ],
          _Caption(source),
          if (said.isNotEmpty) _Caption('You said: ${said.join(' · ')}'),
        ],
      ),
    );
  }
}

/// One task as a dumbbell on a shared minutes scale: planned (ring) → actual (dot).
class _DurationRow extends StatelessWidget {
  final DurationPair pair;
  final int maxMinutes;
  final Color accent;

  const _DurationRow({required this.pair, required this.maxMinutes, required this.accent});

  @override
  Widget build(BuildContext context) {
    final muted = FlowColors.textMutedOf(context);
    return Semantics(
      label: '${pair.title}: planned ${pair.planned} minutes, took ${pair.actual}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 88,
              child: Text(
                pair.title.isEmpty ? 'Task' : pair.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
              ),
            ),
            Expanded(
              child: SizedBox(
                height: 16,
                child: CustomPaint(
                  painter: _DumbbellPainter(
                    planned: pair.planned / maxMinutes,
                    actual: pair.actual / maxMinutes,
                    accent: accent,
                    track: FlowColors.border(context),
                    ring: muted,
                    surface: FlowColors.background(context),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                '${pair.actual} / ${pair.planned}m',
                textAlign: TextAlign.right,
                style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context))
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DumbbellPainter extends CustomPainter {
  final double planned;
  final double actual;
  final Color accent;
  final Color track;
  final Color ring;
  final Color surface;

  _DumbbellPainter({
    required this.planned,
    required this.actual,
    required this.accent,
    required this.track,
    required this.ring,
    required this.surface,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final w = size.width - pad * 2;
    final cy = size.height / 2;
    final px = pad + w * planned;
    final ax = pad + w * actual;
    canvas.drawLine(
        Offset(pad, cy),
        Offset(size.width - pad, cy),
        Paint()
          ..color = track
          ..strokeWidth = 1);
    canvas.drawLine(
      Offset(px, cy),
      Offset(ax, cy),
      Paint()
        ..color = accent.withValues(alpha: 0.5)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(px, cy), 5, Paint()..color = surface);
    canvas.drawCircle(
        Offset(px, cy),
        4,
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(Offset(ax, cy), 6, Paint()..color = surface);
    canvas.drawCircle(Offset(ax, cy), 4.5, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(_DumbbellPainter old) =>
      old.planned != planned || old.actual != actual || old.accent != accent || old.track != track || old.surface != surface;
}

// ── How sessions felt ───────────────────────────────────────────────────────────────────────

class _HowItFelt extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final Color accent;

  const _HowItFelt({required this.snapshot, required this.accent});

  @override
  Widget build(BuildContext context) {
    final a = snapshot.averages!;
    final series = snapshot.series;
    final total = snapshot.feelingCounts.values.fold<int>(0, (x, y) => x + y);
    // Ordinal: one hue, light (drained) → full (on fire).
    final steps = FlowColors.isDark(context) ? const {1: 0.4, 2: 0.58, 3: 0.78, 4: 1.0} : const {1: 0.25, 2: 0.45, 3: 0.7, 4: 1.0};

    return _Section(
      key: const Key('insights_feelings'),
      title: 'How your sessions felt',
      finding: 'Focus ${a.focus.toStringAsFixed(1)} · Energy ${a.energy.toStringAsFixed(1)} on average (of 5)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Feeling mix as one proportional bar.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (final f in const [1, 2, 3, 4])
                    if ((snapshot.feelingCounts[f] ?? 0) > 0)
                      Expanded(
                        flex: snapshot.feelingCounts[f]!,
                        child: Container(
                          margin: EdgeInsets.only(right: f == 4 ? 0 : 2),
                          color: accent.withValues(alpha: steps[f]),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final f in const [1, 2, 3, 4])
                Semantics(
                  label: '${TaskReflection.feelingLabel(f)}: ${snapshot.feelingCounts[f] ?? 0} of $total',
                  excludeSemantics: true,
                  child: _Key(
                    key: Key('insights_feeling_${f}_${snapshot.feelingCounts[f] ?? 0}'),
                    color: accent.withValues(alpha: steps[f]),
                    text: '${TaskReflection.feelingLabel(f)} ${snapshot.feelingCounts[f] ?? 0}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          // Small multiples: one signal per row, same 1–5 scale, oldest → newest.
          _SignalTrend(name: 'Focus', values: [for (final r in series) r.focus], average: a.focus, accent: accent),
          _SignalTrend(name: 'Energy', values: [for (final r in series) r.energy], average: a.energy, accent: accent),
          _SignalTrend(name: 'Difficulty', values: [for (final r in series) r.difficulty], average: a.difficulty, accent: accent),
          _SignalTrend(name: 'Distraction', values: [for (final r in series) r.distraction], average: a.distraction, accent: accent),
          _Caption('Last ${series.length} reflections, oldest to newest.'),
        ],
      ),
    );
  }
}

class _SignalTrend extends StatelessWidget {
  final String name;
  final List<int> values;
  final double average;
  final Color accent;

  const _SignalTrend({required this.name, required this.values, required this.average, required this.accent});

  @override
  Widget build(BuildContext context) {
    final shown = average.toStringAsFixed(1);
    return Semantics(
      label: '$name average $shown of 5, latest ${values.isEmpty ? 'none' : values.last}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 88, child: Text(name, style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)))),
            Expanded(
              child: SizedBox(
                height: 28,
                child: _DrawIn(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _SparkPainter(
                      values: values,
                      color: accent,
                      grid: FlowColors.border(context),
                      surface: FlowColors.background(context),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(
                'avg $shown',
                textAlign: TextAlign.right,
                style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context))
                    .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<int> values;
  final Color color;
  final Color grid;
  final Color surface;

  _SparkPainter({required this.values, required this.color, required this.grid, required this.surface});

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 6.0;
    final h = size.height - pad * 2;
    double y(int v) => pad + h * (1 - (v - 1) / 4);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y(1)), Offset(size.width, y(1)), gridPaint);
    canvas.drawLine(Offset(0, y(5)), Offset(size.width, y(5)), gridPaint..color = grid.withValues(alpha: 0.5));
    if (values.isEmpty) return;
    final step = values.length == 1 ? 0.0 : (size.width - pad * 2) / (values.length - 1);
    final points = [for (var i = 0; i < values.length; i++) Offset(pad + step * i, y(values[i]))];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 6, Paint()..color = surface);
    canvas.drawCircle(points.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.color != color || old.grid != grid || old.surface != surface;
}

// ── Follow-through ──────────────────────────────────────────────────────────────────────────

class _FollowThrough extends StatelessWidget {
  final InsightsSnapshot snapshot;
  final Color accent;

  const _FollowThrough({required this.snapshot, required this.accent});

  @override
  Widget build(BuildContext context) {
    final done = snapshot.plannedRecentlyDone;
    final planned = snapshot.plannedRecently;
    return _Section(
      key: const Key('insights_follow'),
      title: 'Follow-through',
      finding: '$done of $planned planned tasks finished',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label: '$done of $planned planned tasks finished in the last 14 days',
            excludeSemantics: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: done / planned,
                minHeight: 10,
                backgroundColor: accent.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const _Caption('Tasks whose planned time ended in the last 14 days.'),
        ],
      ),
    );
  }
}

// ── From your account history (GET /insights/summary) ───────────────────────────────────────

class _WeekTrend extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _WeekTrend({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final now = ((data['this_week'] as num).toDouble() * 100).round();
    final last = ((data['last_week'] as num).toDouble() * 100).round();
    final change = (data['change_pts'] as num?)?.toInt() ?? (now - last);
    final word = change > 0 ? 'up' : 'down';
    return _Section(
      key: const Key('insights_week_trend'),
      title: 'This week vs last',
      finding: change == 0
          ? 'You finished $now% of planned work, the same as last week.'
          : 'You finished $now% of planned work, $word ${change.abs()} points from last week.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in [('This week', now), ('Last week', last)]) ...[
            Row(children: [
              SizedBox(
                width: 84,
                child: Text(label, style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context))),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: value / 100,
                    minHeight: 8,
                    backgroundColor: accent.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation(label == 'This week' ? accent : _quiet(context)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('$value%', style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context))),
            ]),
            const SizedBox(height: 8),
          ],
          _Caption('${data['completed']} of ${data['planned']} planned tasks so far this week.'),
        ],
      ),
    );
  }
}

class _Routines extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _Routines({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final items = ((data['items'] as List?) ?? const []).cast<Map>().take(4).toList();
    return _Section(
      key: const Key('insights_routines'),
      title: 'Your routines',
      finding: items.length == 1
          ? 'One habit keeps showing up in your weeks.'
          : '${items.length} habits keep showing up in your weeks.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in items)
            _Fact(
              icon: Icons.event_repeat_rounded,
              text: '${r['title']} · ${r['weekday']}s around ${r['start_label']} '
                  '(${r['weeks_seen']} of the last ${r['weeks_span']} weeks)',
              accent: accent,
            ),
          const _Caption('Build My Day suggests these times when you add the task without one. '
              'A time you give always wins.'),
        ],
      ),
    );
  }
}

class _Postponement extends StatelessWidget {
  final Map<String, dynamic> data;
  final Color accent;

  const _Postponement({required this.data, required this.accent});

  @override
  Widget build(BuildContext context) {
    final rows = ((data['categories'] as List?) ?? const [])
        .cast<Map>()
        .where((r) => ((r['rate'] as num?) ?? 0) > 0)
        .take(3)
        .toList();
    if (rows.isEmpty) {
      return _Section(
        key: const Key('insights_postponement'),
        title: 'Postponing',
        finding: 'Across ${data['sample_size']} planned tasks, nothing has been pushed back.',
        child: const SizedBox.shrink(),
      );
    }
    final top = rows.first;
    return _Section(
      key: const Key('insights_postponement'),
      title: 'Postponing',
      finding: '${top['category']} gets pushed back most: '
          '${(((top['rate'] as num).toDouble()) * 100).round()}% of the time.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            _Fact(
              icon: Icons.schedule_rounded,
              text: '${r['category']}: ${r['skipped']} skipped, ${r['deferred']} deferred, ${r['missed']} missed '
                  'of ${r['sample_size']}',
              accent: accent,
            ),
          const _Caption('Skips, deferrals and missed slots from the last 8 weeks.'),
        ],
      ),
    );
  }
}

// ── What Flowstate learned ──────────────────────────────────────────────────────────────────

class _Learned extends StatelessWidget {
  final AppStateProvider state;
  final InsightsSnapshot snapshot;
  final int evaluations;
  final Map<String, dynamic>? evalData;
  final Map<String, dynamic>? history;
  final Color accent;

  const _Learned(
      {required this.state,
      required this.snapshot,
      required this.evaluations,
      required this.evalData,
      this.history,
      required this.accent});

  @override
  Widget build(BuildContext context) {
    final readiness = state.readiness;
    final completionRate = (evalData?['overall_completion_rate'] as num?)?.toDouble();
    final learnings = snapshot.learnings;
    final timedNeeded = InsightsSnapshot.minTimedCompletions - snapshot.timedCompletions;

    // What is still missing, said once instead of an empty chart per section.
    final waiting = <String>[
      if (timedNeeded > 0) 'Finish $timedNeeded more ${timedNeeded == 1 ? 'task' : 'tasks'} to see when you tend to get things done.',
      if (snapshot.averages == null)
        'Reflect on ${snapshot.reflectionsNeeded} more ${snapshot.reflectionsNeeded == 1 ? 'task' : 'tasks'} (the "How did that feel?" step) to see your energy and focus patterns.',
      if (snapshot.plannedVsActual == null) 'Reflect on a few finished tasks to compare planned and actual time.',
      if ((history?['routines'] as Map?)?['status'] == 'learning')
        'Do something on the same weekday at a similar time for 3 weeks and Flowstate will spot the routine.',
    ];

    return Column(
      key: const Key('insights_learning'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NoyaMotionView(
              key: const Key('insights_noya'),
              pose: learnings.isEmpty ? NoyaState.thinking : NoyaState.idea,
              mood: NoyaMood.rest,
              size: 56,
              enter: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What Flowstate learned',
                    style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    learnings.isEmpty ? 'Nothing stands out yet.' : 'Patterns from your own days',
                    style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < learnings.length; i++) _LearningRow(index: i + 1, learning: learnings[i], accent: accent),
        if (readiness.isCalibrated)
          _Fact(icon: Icons.bolt_rounded, text: 'Your focus window: ${readiness.focusWindowRange}', accent: accent),
        if (evaluations >= 3 && completionRate != null)
          _Fact(
            icon: Icons.check_circle_outline_rounded,
            text: 'Across $evaluations readiness checks, you finish about ${(completionRate * 100).round()}% of what you plan.',
            accent: accent,
          ),
        _Fact(
          icon: Icons.edit_note_rounded,
          text: snapshot.reflectionCount == 0
              ? 'No reflections yet. Each "How did that feel?" answer teaches Flowstate.'
              : '${snapshot.reflectionCount} ${snapshot.reflectionCount == 1 ? 'reflection' : 'reflections'} recorded on this device.',
          accent: accent,
        ),
        if (waiting.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final w in waiting)
            _Fact(icon: Icons.hourglass_empty_rounded, text: w, accent: FlowColors.textMutedOf(context), muted: true),
        ],
      ],
    );
  }
}

class _LearningRow extends StatelessWidget {
  final int index;
  final Learning learning;
  final Color accent;

  const _LearningRow({required this.index, required this.learning, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('insights_learned_${learning.id}'),
      padding: const EdgeInsets.only(bottom: 14),
      // The claim, then the evidence behind it — weight and ink carry the hierarchy.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            learning.text,
            style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(learning.evidence, style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color accent;
  final bool muted;

  const _Fact({required this.icon, required this.text, required this.accent, this.muted = false});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: muted
                    ? FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
                    : FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
              ),
            ),
          ],
        ),
      );
}

// ── Chart primitives ────────────────────────────────────────────────────────────────────────

/// A legend key: a small swatch (or ring) beside text in text ink.
class _Key extends StatelessWidget {
  final Color color;
  final String text;
  final bool hollow;

  /// A filled dot, for marks drawn as dots.
  final bool round;

  const _Key({super.key, required this.color, required this.text, this.hollow = false, this.round = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: hollow || round ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: hollow || round ? null : BorderRadius.circular(2),
              color: hollow ? null : color,
              border: hollow ? Border.all(color: color, width: 2) : null,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)))),
        ],
      );
}

/// Columns on one baseline: thin bars (≤ 24 px) with 4 px rounded tops, sparse direct labels, and
/// a tap tooltip per column so every value is reachable without labelling all of them.
class _Columns extends StatelessWidget {
  final double height;
  final List<int> values;
  final Color Function(int i) colorFor;
  final String? Function(int i) labelFor;
  final Key? Function(int i)? keyFor;
  final String Function(int i) tooltipFor;
  final List<String> axis;

  /// Columns from this index on are in the future (drawn as an empty slot).
  final int? dimFrom;

  /// Extra space after this index (separates two groups, e.g. weeks).
  final int? groupGapAfter;
  final int? emphasisAxis;

  const _Columns({
    required this.height,
    required this.values,
    required this.colorFor,
    required this.labelFor,
    this.keyFor,
    required this.tooltipFor,
    required this.axis,
    this.dimFrom,
    this.groupGapAfter,
    this.emphasisAxis,
  });

  @override
  Widget build(BuildContext context) {
    final peak = math.max(1, values.fold<int>(0, math.max));
    final labelStyle = FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(fontWeight: FontWeight.w700);
    final axisStyle = FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(fontSize: 10);

    Widget column(int i) {
      final future = dimFrom != null && i >= dimFrom!;
      final label = future ? null : labelFor(i);
      final barHeight = values[i] == 0 ? 0.0 : math.max(3.0, (height - 26) * values[i] / peak);
      final bar = LayoutBuilder(
        builder: (context, c) {
          final width = math.min(24.0, math.max(4.0, c.maxWidth * 0.6));
          return SizedBox(
            key: keyFor?.call(i),
            height: height,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (label != null) FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: labelStyle)),
                const SizedBox(height: 2),
                Container(
                  width: width,
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: colorFor(i),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ],
            ),
          );
        },
      );
      return Expanded(
        child: future
            ? bar
            : Tooltip(
                message: tooltipFor(i),
                triggerMode: TooltipTriggerMode.tap,
                child: Semantics(label: tooltipFor(i), excludeSemantics: true, child: bar),
              ),
      );
    }

    final children = <Widget>[];
    final labels = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      children.add(column(i));
      labels.add(Expanded(
        child: Text(
          axis[i],
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.visible,
          softWrap: false,
          style: i == emphasisAxis ? axisStyle.copyWith(color: FlowColors.textPrimaryOf(context), fontWeight: FontWeight.w700) : axisStyle,
        ),
      ));
      if (groupGapAfter == i) {
        children.add(const SizedBox(width: 12));
        labels.add(const SizedBox(width: 12));
      }
    }

    return Column(
      children: [
        _DrawIn(child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: children)),
        Divider(height: 1, thickness: 1, color: FlowColors.border(context)),
        const SizedBox(height: 4),
        Row(children: labels),
      ],
    );
  }
}
