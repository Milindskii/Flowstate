import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/calendar_models.dart';
import '../models/schedule_item.dart';
import '../models/task_reflection.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'day_path/day_route_geometry.dart';
import 'day_path/day_route_painter.dart';
import 'companion/noya_moments.dart';
import 'companion/noya_reaction_controller.dart';
import 'noya_companion_view.dart';
import 'noya_motion_view.dart';

/// The day as a journey path, seen from a slight tilt: the road runs from the foreground (bottom, the earliest
/// stop) up into the distance (top, the latest), bending gently, centred in the viewport. Stops grow larger near
/// the viewer and shrink with distance; labels sit beside the road on the side opposite its bend and stay
/// secondary.
///
/// The route is not a decoration: [DayRouteGeometry] derives it from the items' real state, and the painter draws
/// exactly that. The stretch already travelled is green, the road ahead blue; a skipped or deferred stop (yellow)
/// makes the route physically bend around it, a recovered one keeps that history and gets an orange detour, and
/// red is only for a true failure.
class FlowDayPath extends StatefulWidget {
  final List<ScheduleItem> items;
  final String? nowItemId;
  final TaskReflection? Function(ScheduleItem item) reflectionFor;
  final DateTime? Function(ScheduleItem item) completedAtFor;

  /// The task's category ("Fitness", "Study"…), when the caller knows it. Falls back to the
  /// schedule item's own type.
  final String? Function(ScheduleItem item)? categoryFor;
  final ValueChanged<ScheduleItem> onTap;

  /// The server's verdict on the day (every task done?) and whether its trophy XP was collected.
  final DayCompleteStatus? dayComplete;

  /// Collects the day's trophy XP for Noya. Null hides the button (e.g. signed out).
  final Future<void> Function()? onClaimTrophy;

  const FlowDayPath({
    super.key,
    required this.items,
    required this.nowItemId,
    required this.reflectionFor,
    required this.completedAtFor,
    this.categoryFor,
    required this.onTap,
    this.dayComplete,
    this.onClaimTrophy,
  });

  /// Visible node diameters at the foreground (the tap target is always at least 48 dp).
  static const double upcomingNodeSize = 36;
  static const double doneNodeSize = 34;
  static const double nowNodeSize = 40;

  /// Height of one stop's row (tap target + label), centred on the stop.
  static const double rowHeight = 92;

  /// Words for the item's category; generic values carry no information and are dropped.
  static String? categoryLabel(ScheduleItem item, String? category) {
    final raw = (category ?? '').trim();
    if (raw.isNotEmpty && raw.toLowerCase() != 'general') return raw[0].toUpperCase() + raw.substring(1);
    switch (item.type.trim().toLowerCase()) {
      case 'high focus':
      case 'deep_work':
        return 'Deep work';
      case '':
      case 'task':
      case 'focus':
        return null;
      default:
        final t = item.type.replaceAll('_', ' ').trim();
        return t[0].toUpperCase() + t.substring(1).toLowerCase();
    }
  }

  @override
  State<FlowDayPath> createState() => _FlowDayPathState();
}

class _FlowDayPathState extends State<FlowDayPath> {
  final GlobalKey _targetKey = GlobalKey();
  String? _revealedFor;

  /// Where the traveller is: NOW, else the next unfinished stop, else the start of the road.
  String? get _targetId {
    final items = widget.items;
    if (items.isEmpty) return null;
    if (widget.nowItemId != null && items.any((i) => i.id == widget.nowItemId)) return widget.nowItemId;
    for (final i in items) {
      if (!i.isCompleted && !i.isSkipped && !i.isFailed && !i.isMissed && i.deviation == null) return i.id;
    }
    return items.first.id;
  }

  /// The road runs top (first task) to bottom (last task): bring the traveller's stop into the upper part of the
  /// screen on first show (and when it changes), so the screen opens where the day is.
  void _revealTarget() {
    final id = _targetId;
    if (id == null || id == _revealedFor) return;
    _revealedFor = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _targetKey.currentContext;
      if (!mounted || ctx == null || Scrollable.maybeOf(ctx) == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.3, duration: Duration.zero);
    });
  }

  DayRoutePalette _palette(BuildContext context) {
    final dark = FlowColors.isDark(context);
    return DayRoutePalette(
      traveled: FlowColors.successOf(context),
      ahead: Theme.of(context).colorScheme.primary,
      skipped: FlowColors.routeSkippedOf(context),
      recovery: FlowColors.routeRecoveryOf(context),
      failed: FlowColors.errorOf(context),
      bed: FlowColors.textMutedOf(context).withValues(alpha: dark ? 0.16 : 0.12),
      bedEdge: FlowColors.textMutedOf(context).withValues(alpha: dark ? 0.28 : 0.2),
      fadeTo: FlowColors.background(context),
      bypassed: FlowColors.textMutedOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final dayDone = items.isNotEmpty &&
        (items.every((i) => i.isCompleted) || (widget.dayComplete?.eligible ?? false));
    _revealTarget();

    return Column(
      key: const Key('flow_day_path_line'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.of(context).size.width;
          final geo = DayRouteGeometry.compute(items, widget.nowItemId, width);
          final targetId = _targetId;
          return SizedBox(
            width: width,
            height: geo.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(child: _AnimatedRoute(geometry: geo, palette: _palette(context))),
                for (final stop in geo.stops)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: stop.center.dy - FlowDayPath.rowHeight / 2,
                    height: FlowDayPath.rowHeight,
                    child: _PathStop(
                      key: Key('path_stop_${stop.id}'),
                      rowKey: stop.id == targetId ? _targetKey : null,
                      item: items[stop.index],
                      stop: stop,
                      width: width,
                      isNow: stop.id == widget.nowItemId,
                      reflection: items[stop.index].isCompleted ? widget.reflectionFor(items[stop.index]) : null,
                      completedAt: items[stop.index].isCompleted
                          ? (widget.reflectionFor(items[stop.index])?.completedAt ?? widget.completedAtFor(items[stop.index]))
                          : null,
                      category: FlowDayPath.categoryLabel(items[stop.index], widget.categoryFor?.call(items[stop.index])),
                      palette: _palette(context),
                      onTap: () => widget.onTap(items[stop.index]),
                    ),
                  ),
              ],
            ),
          );
        }),
        // The finish of a completed day sits at the end of the road, at the bottom.
        if (dayDone)
          _DayComplete(
            items: [for (final i in items) if (i.isCompleted) i],
            reflectionFor: widget.reflectionFor,
            status: widget.dayComplete,
            onClaim: widget.onClaimTrophy,
          ),
      ],
    );
  }
}

/// Paints the route and, when the geometry changes for the same stops (a skip, a recovery, a completion),
/// morphs the route itself — the sampled x positions interpolate — over 400 ms. Reduced motion snaps.
class _AnimatedRoute extends StatefulWidget {
  final DayRouteGeometry geometry;
  final DayRoutePalette palette;

  const _AnimatedRoute({required this.geometry, required this.palette});

  @override
  State<_AnimatedRoute> createState() => _AnimatedRouteState();
}

class _AnimatedRouteState extends State<_AnimatedRoute> with SingleTickerProviderStateMixin {
  static const Duration morph = Duration(milliseconds: 400);
  late final AnimationController _c = AnimationController(vsync: this, duration: morph, value: 1);
  List<double>? _fromXs;
  List<bool>? _fromTraveled;
  bool _extrasFade = false;

  @override
  void didUpdateWidget(_AnimatedRoute old) {
    super.didUpdateWidget(old);
    if (old.geometry.sameRoute(widget.geometry)) return;
    final comparable = old.geometry.layoutSignature == widget.geometry.layoutSignature && old.geometry.hasRoute;
    if (!comparable || FlowMotion.isReducedMotion(context)) {
      _fromXs = null;
      _fromTraveled = null;
      _extrasFade = false;
      _c.value = 1;
      return;
    }
    // Start from what is on screen right now, so a change mid-morph never jumps.
    final eased = Curves.easeInOutCubic.transform(_c.value);
    final shown = <double>[
      for (var i = 0; i < old.geometry.sampleXs.length; i++)
        _fromXs == null ? old.geometry.sampleXs[i] : _fromXs![i] + (old.geometry.sampleXs[i] - _fromXs![i]) * eased,
    ];
    _fromXs = shown;
    _fromTraveled = old.geometry.sampleTraveled;
    _extrasFade = old.geometry.spurs.length != widget.geometry.spurs.length || old.geometry.detours.length != widget.geometry.detours.length;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_c.value);
        return CustomPaint(
          key: const Key('flow_day_route'),
          painter: DayRoutePainter(
            geometry: widget.geometry,
            palette: widget.palette,
            fromXs: _c.isCompleted ? null : _fromXs,
            fromTraveled: _c.isCompleted ? null : _fromTraveled,
            t: t,
            extrasOpacity: _extrasFade ? t : 1,
          ),
        );
      },
    );
  }
}

/// The one milestone on a finished day: Noya's thumbs-up, what the day added up to and, at the very end of the road,
/// the day's trophy: Noya's XP for finishing everything, collected once (the server decides it is earned).
class _DayComplete extends StatefulWidget {
  final List<ScheduleItem> items;
  final TaskReflection? Function(ScheduleItem item) reflectionFor;
  final DayCompleteStatus? status;
  final Future<void> Function()? onClaim;

  const _DayComplete({required this.items, required this.reflectionFor, this.status, this.onClaim});

  @override
  State<_DayComplete> createState() => _DayCompleteState();
}

class _DayCompleteState extends State<_DayComplete> {
  bool _claiming = false;
  bool _claimedHere = false;

  Future<void> _claim() async {
    final onClaim = widget.onClaim;
    if (onClaim == null || _claiming) return;
    setState(() => _claiming = true);
    try {
      await onClaim();
      if (mounted) setState(() => _claimedHere = true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Couldn't collect the trophy right now. Try again in a moment.")),
        );
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final minutes = items.fold<int>(0, (sum, i) => sum + (widget.reflectionFor(i)?.actualMinutes ?? i.durationMinutes));
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    final total = hours == 0 ? '$rest min' : (rest == 0 ? '${hours}h' : '${hours}h ${rest}m');
    final count = items.length == 1 ? '1 task' : '${items.length} tasks';
    final status = widget.status;
    final claimed = (status?.claimed ?? false) || _claimedHere;
    final xp = status?.xp ?? 0;
    const gold = Color(0xFFF2B233);

    return Column(
      key: const Key('path_day_complete'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 96,
                child: Center(child: NoyaCompanionView(state: NoyaState.goodJob, size: 56)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Day complete',
                      style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text('$count · $total', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (status != null && status.eligible)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Center(
                    child: Container(
                      key: const Key('path_trophy'),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.alphaBlend(gold.withValues(alpha: claimed ? 0.28 : 0.16), FlowColors.surface(context)),
                        border: Border.all(color: gold, width: 2.5),
                      ),
                      child: const Icon(Icons.emoji_events_rounded, color: gold, size: 26),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Semantics(
                    liveRegion: claimed,
                    child: Text(
                      claimed ? '+$xp XP earned for Noya' : 'Every task done. Noya earned a trophy.',
                      style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                if (!claimed && widget.onClaim != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                    child: FilledButton.tonal(
                      key: const Key('path_trophy_claim'),
                      onPressed: _claiming ? null : _claim,
                      child: Text(_claiming ? 'Claiming…' : 'Claim +$xp XP'),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PathStop extends StatelessWidget {
  final Key? rowKey;
  final ScheduleItem item;
  final StopGeometry stop;
  final double width;
  final bool isNow;
  final TaskReflection? reflection;
  final DateTime? completedAt;
  final String? category;
  final DayRoutePalette palette;
  final VoidCallback onTap;

  const _PathStop({
    super.key,
    this.rowKey,
    required this.item,
    required this.stop,
    required this.width,
    required this.isNow,
    required this.reflection,
    required this.completedAt,
    required this.category,
    required this.palette,
    required this.onTap,
  });

  static const double _nodeBox = 56;

  String get _time => '${item.time} ${item.period}'.trim();

  bool get _isSkippedFamily => item.isSkipped || item.deviation == 'skipped' || item.deviation == 'deferred';

  /// Which node is drawn; a change here is a real state change and crossfades.
  String get _nodeState {
    if (item.isCompleted) {
      return item.isCompletedAfterDeviation ? 'recovered' : 'done';
    }
    if (isNow) return item.isActive ? 'focus' : 'now';
    if (_isSkippedFamily) return 'skipped';
    if (item.isFailed) return 'failed';
    if (item.isMissed) return 'missed';
    if (item.isCommitment) return 'commitment';
    return 'ahead';
  }

  String? get _stateLabel {
    if (item.isFailed) return 'Unfinished';
    if (_isSkippedFamily) return item.deviation == 'deferred' ? 'Deferred' : 'Skipped';
    if (item.isConflict) return 'Conflict';
    if (item.isFixed || item.isCommitment) return 'Fixed';
    if (item.isMissed) return 'Missed';
    if (item.isSuggested) return 'Suggested';
    return null;
  }

  String _semanticsLabel() {
    if (item.isCompleted) {
      return [
        item.title,
        completedAt == null ? 'completed' : 'completed at ${DateFormat('h:mm a').format(completedAt!)}',
        if (item.isCompletedAfterDeviation) 'completed after deviation',
        if (reflection != null) 'felt ${TaskReflection.feelingLabel(reflection!.feeling)}',
      ].join(', ');
    }
    return [
      item.title,
      if (isNow) 'now',
      if (_time.isNotEmpty) _time,
      '${item.durationMinutes} minutes',
      if (_stateLabel != null) _stateLabel!,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final x = stop.center.dx;
    final labelOnLeft = stop.labelOnLeft;
    final reduced = FlowMotion.isReducedMotion(context);

    return Semantics(
      container: true,
      button: true,
      label: _semanticsLabel(),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        key: rowKey,
        onTap: () {
          FlowHaptics.selection();
          onTap();
        },
        borderRadius: FlowRadii.chipRadius,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Label: beside the road, on the side opposite its bend.
            Positioned(
              top: 0,
              bottom: 0,
              left: labelOnLeft ? 12 : x + _nodeBox / 2 + 4,
              right: labelOnLeft ? width - (x - _nodeBox / 2 - 4) : 12,
              child: Align(
                alignment: labelOnLeft ? Alignment.centerRight : Alignment.centerLeft,
                child: _label(context, accent, alignEnd: labelOnLeft),
              ),
            ),
            // Noya joins the path only while this task is actually in focus, on the bend side of the road.
            if (isNow && item.isActive)
              Positioned(
                top: (FlowDayPath.rowHeight - 44) / 2,
                left: labelOnLeft ? x + _nodeBox / 2 + 2 : null,
                right: labelOnLeft ? null : width - (x - _nodeBox / 2 - 2),
                child: const NoyaMotionView(mood: NoyaMood.focusing, pose: NoyaState.focusing, size: 44),
              ),
            // Node: slides to its x when its position changes, scaled by depth (larger near, smaller far).
            Positioned(
              top: (FlowDayPath.rowHeight - _nodeBox) / 2,
              left: x - _nodeBox / 2,
              width: _nodeBox,
              height: _nodeBox,
              child: SizedBox(
                key: Key('path_node_${item.id}'),
                child: Center(
                  child: Transform.scale(
                    scale: isNow ? 1.0 : stop.scale,
                    child: AnimatedSwitcher(
                      duration: reduced ? Duration.zero : FlowMotion.standardDuration,
                      switchInCurve: FlowMotion.easeOut,
                      switchOutCurve: FlowMotion.easeOut,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(animation), child: child),
                      ),
                      child: KeyedSubtree(key: ValueKey('node_${item.id}_$_nodeState'), child: _node(context, accent)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _node(BuildContext context, Color accent) {
    final surface = FlowColors.surface(context);
    final dark = FlowColors.isDark(context);
    if (item.isCompleted) {
      if (item.isCompletedAfterDeviation) {
        // Recovered: a green check ringed in orange — it was done, but not on the first pass.
        final ok = FlowColors.successOf(context);
        final ring = palette.recovery;
        return Container(
          key: Key('path_check_${item.id}'),
          width: FlowDayPath.doneNodeSize,
          height: FlowDayPath.doneNodeSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.alphaBlend(ok.withValues(alpha: dark ? 0.2 : 0.14), surface),
            border: Border.all(color: ring, width: 2.5),
          ),
          child: Icon(Icons.check_rounded, size: 20, color: ok),
        );
      }
      // History along normal planned route: a clear green check, calm — tinted fill, no glow, no motion.
      final ok = FlowColors.successOf(context);
      return Container(
        key: Key('path_check_${item.id}'),
        width: FlowDayPath.doneNodeSize,
        height: FlowDayPath.doneNodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.alphaBlend(ok.withValues(alpha: dark ? 0.2 : 0.14), surface),
          border: Border.all(color: ok, width: 2),
        ),
        child: Icon(Icons.check_rounded, size: 20, color: ok),
      );
    }
    if (isNow) return _NowNode(key: Key('path_now_${item.id}'), active: item.isActive, accent: accent, surface: surface);

    if (_isSkippedFamily) {
      // Skipped or deferred: yellow. The route goes around this stop; it is not a failure.
      final yellow = palette.skipped;
      return Container(
        key: Key('path_skipped_${item.id}'),
        width: FlowDayPath.upcomingNodeSize,
        height: FlowDayPath.upcomingNodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.alphaBlend(yellow.withValues(alpha: dark ? 0.18 : 0.12), surface),
          border: Border.all(color: yellow, width: 2.5),
        ),
        child: Icon(Icons.alt_route_rounded, size: 17, color: yellow),
      );
    }

    if (item.isFailed) {
      // Failed / Unfinished: the only red on the path.
      final err = palette.failed;
      return Container(
        key: Key('path_failed_${item.id}'),
        width: FlowDayPath.upcomingNodeSize,
        height: FlowDayPath.upcomingNodeSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Color.alphaBlend(err.withValues(alpha: dark ? 0.18 : 0.12), surface),
          border: Border.all(color: err, width: 2.5),
        ),
        child: Icon(Icons.close_rounded, size: 18, color: err),
      );
    }

    final locked = item.isFixed || item.isCommitment;
    final color = item.isConflict
        ? FlowColors.errorOf(context)
        : item.isMissed
            ? FlowColors.warningOf(context)
            : (locked ? FlowColors.textSecondaryOf(context) : accent);
    // State glyphs win; otherwise the kind of work, when it is known, so the road ahead can be
    // read at a glance. Generic tasks stay a clean ring.
    final icon = item.isConflict
        ? Icons.error_outline_rounded
        : item.isMissed
            ? Icons.history_rounded
            : (locked ? Icons.lock_rounded : _kindIcon(workKindOf(category: category, type: item.type, title: item.title)));
    return Container(
      key: item.isCommitment ? Key('path_commitment_${item.id}') : null,
      width: FlowDayPath.upcomingNodeSize,
      height: FlowDayPath.upcomingNodeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: surface,
        border: Border.all(color: item.isSuggested ? color.withValues(alpha: 0.55) : color, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? 0.25 : 0.08), offset: const Offset(0, 2), blurRadius: 4)],
      ),
      child: icon == null ? null : Icon(icon, size: 17, color: color),
    );
  }

  static IconData? _kindIcon(WorkKind kind) {
    switch (kind) {
      case WorkKind.physical:
        return Icons.directions_run_rounded;
      case WorkKind.study:
        return Icons.menu_book_rounded;
      case WorkKind.planning:
        return Icons.checklist_rounded;
      case WorkKind.deepWork:
        return Icons.bolt_rounded;
      case WorkKind.other:
        return null;
    }
  }

  Widget _label(BuildContext context, Color accent, {required bool alignEnd}) {
    final done = item.isCompleted;
    final isRecovered = item.isCompletedAfterDeviation;
    final muted = FlowColors.textMutedOf(context);
    final meta = FlowTypography.bodySmall(color: muted);
    final tagStyle = FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w600);
    final align = alignEnd ? TextAlign.end : TextAlign.start;

    final minutes = done && reflection != null && reflection!.actualMinutes > 0 ? reflection!.actualMinutes : item.durationMinutes;
    var when = done ? (completedAt == null ? 'Done' : 'Done ${DateFormat('h:mm a').format(completedAt!)}') : _time;
    if (!done && item.isCommitment && item.startTime != null && item.endTime != null) {
      // A protected block reads as a span of time, not a start plus a length.
      when = '${DateFormat('h:mm').format(item.startTime!)}–${DateFormat('h:mm a').format(item.endTime!)}';
    }

    // Category and state on one quiet line; only the state that needs attention is coloured.
    final stateLabel = _stateLabel;
    final tags = <(String, Color?)>[
      if (isNow) (item.isActive ? 'In focus' : 'Up now', accent),
      if (done && isRecovered) ('Recovered', palette.recovery),
      if (!done && stateLabel != null)
        (
          stateLabel,
          item.isFailed
              ? palette.failed
              : _isSkippedFamily
                  ? palette.skipped
                  : item.isConflict
                      ? FlowColors.errorOf(context)
                      : (item.isMissed ? FlowColors.warningOf(context) : null),
        ),
      if (category != null) (category!, null),
      if (done && reflection != null) ('Felt ${TaskReflection.feelingLabel(reflection!.feeling).toLowerCase()}', null),
    ];

    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          textAlign: align,
          overflow: TextOverflow.ellipsis,
          style: FlowTypography.bodyLarge(
            color: done ? FlowColors.textSecondaryOf(context) : FlowColors.textPrimaryOf(context),
          ).copyWith(fontWeight: isNow ? FontWeight.w700 : FontWeight.w600, height: 1.25, fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text.rich(
          TextSpan(children: [
            if (when.isNotEmpty) TextSpan(text: when, style: meta.copyWith(fontWeight: FontWeight.w600)),
            TextSpan(text: '${when.isNotEmpty ? ' · ' : ''}$minutes min'),
          ]),
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: meta,
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              for (var i = 0; i < tags.length; i++) ...[
                if (i > 0) const TextSpan(text: ' · '),
                TextSpan(
                  text: tags[i].$1,
                  style: tags[i].$2 == null ? null : TextStyle(color: tags[i].$2, fontWeight: FontWeight.w800),
                ),
              ],
            ]),
            key: Key('path_tags_${item.id}'),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tagStyle,
          ),
        ],
      ],
    );
  }
}

/// The strongest stop on the path: a filled disc inside a quiet ring, one size step above the
/// other stops — a marker, not a button; the glyph inside stays small.
///
/// When a task becomes NOW, a soft ring breathes out from the disc three times (≈7 s) and then
/// rests: enough to say "you are here" on arrival without a loop competing with the day. Loops
/// are off under reduced motion (and in tests), where the node is simply still.
class _NowNode extends StatefulWidget {
  final bool active;
  final Color accent;
  final Color surface;

  const _NowNode({super.key, required this.active, required this.accent, required this.surface});

  static const Duration breath = Duration(milliseconds: 2400);
  static const int breaths = 3;

  @override
  State<_NowNode> createState() => _NowNodeState();
}

class _NowNodeState extends State<_NowNode> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: _NowNode.breath);
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!FlowMotion.loopsEnabled(context)) {
      _breath
        ..stop()
        ..value = 0;
    } else if (!_played) {
      _play();
    }
  }

  @override
  void didUpdateWidget(_NowNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Starting focus is a new state: breathe again.
    if (widget.active != oldWidget.active && FlowMotion.loopsEnabled(context)) _play();
  }

  void _play() {
    _played = true;
    _breath.repeat(count: _NowNode.breaths).whenCompleteOrCancel(() {
      if (mounted) _breath.value = 0;
    });
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const outer = FlowDayPath.nowNodeSize + 12;
    final accent = widget.accent;
    final disc = Container(
      width: FlowDayPath.nowNodeSize,
      height: FlowDayPath.nowNodeSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent,
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.25), offset: const Offset(0, 3), blurRadius: 10)],
      ),
      child: Icon(
        widget.active ? Icons.timelapse_rounded : Icons.play_arrow_rounded,
        // Secondary to the disc: small and slightly soft, so the node reads as a place, not a button.
        size: 14,
        color: FlowColors.textInverse.withValues(alpha: 0.8),
      ),
    );
    return SizedBox(
      width: outer,
      height: outer,
      child: AnimatedBuilder(
        animation: _breath,
        child: disc,
        builder: (context, disc) {
          // One breath: rises and settles with zero velocity at both ends.
          final b = (1 - math.cos(2 * math.pi * _breath.value)) / 2;
          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Static quiet ring: the NOW marker even when nothing moves.
              Container(
                width: outer,
                height: outer,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.surface,
                  border: Border.all(color: accent.withValues(alpha: 0.4), width: 2),
                ),
              ),
              // Breathing ring: expands a little and fades as it goes.
              if (_breath.isAnimating)
                Transform.scale(
                  key: const Key('path_now_breath'),
                  scale: 1 + 0.22 * _breath.value,
                  child: Container(
                    width: outer,
                    height: outer,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: accent.withValues(alpha: 0.45 * (1 - _breath.value)), width: 2),
                    ),
                  ),
                ),
              Transform.scale(scale: 1 + 0.04 * b, child: disc),
            ],
          );
        },
      ),
    );
  }
}

/// A moment of the day opened from the path (or Today so far): what happened, when, and how it
/// felt. Read-only — this is a memory, not an edit dialog — so it slides in from the side as a
/// panel over the day rather than interrupting as a modal sheet.
Future<void> showHistoryMomentSheet(
  BuildContext context, {
  required ScheduleItem item,
  TaskReflection? reflection,
  DateTime? completedAt,
  String? category,
}) {
  // iOS-like drawer curve; the exit uses the same curve flipped, so it leaves the way it came
  // and never starts slowly.
  const drawer = Cubic(0.32, 0.72, 0, 1);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close ${item.title}',
    barrierColor: Colors.black.withValues(alpha: FlowColors.isDark(context) ? 0.5 : 0.28),
    transitionDuration: FlowMotion.responsiveDuration(context, const Duration(milliseconds: 340)),
    pageBuilder: (context, _, __) => _HistoryMomentPanel(
      item: item,
      reflection: reflection,
      completedAt: reflection?.completedAt ?? completedAt,
      category: category,
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: drawer, reverseCurve: drawer.flipped);
      if (FlowMotion.isReducedMotion(context)) return FadeTransition(opacity: curved, child: child);
      return SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
        child: child,
      );
    },
  );
}

class _HistoryMomentPanel extends StatefulWidget {
  final ScheduleItem item;
  final TaskReflection? reflection;
  final DateTime? completedAt;
  final String? category;

  const _HistoryMomentPanel({required this.item, required this.reflection, required this.completedAt, this.category});

  @override
  State<_HistoryMomentPanel> createState() => _HistoryMomentPanelState();
}

class _HistoryMomentPanelState extends State<_HistoryMomentPanel> {
  final NoyaReactionController _reactions = NoyaReactionController(clock: DateTime.now);

  @override
  void initState() {
    super.initState();
    // Noya waves hello once the panel has arrived (her entrance plays first).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reactions.react(NoyaReaction.greet);
    });
  }

  @override
  void dispose() {
    _reactions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final r = widget.reflection;
    final done = item.isCompleted;
    final time = DateFormat('h:mm a');
    final plannedStart = r?.plannedStart ?? item.startTime;
    final plannedText = plannedStart != null ? time.format(plannedStart) : ('${item.time} ${item.period}'.trim());
    final plannedMinutes = r?.plannedMinutes ?? item.durationMinutes;
    final category = FlowDayPath.categoryLabel(item, widget.category);
    final kind = workKindOf(category: category ?? widget.category, type: item.type, title: item.title);
    final pose = noyaStateForTask(kind: kind, done: done, reflection: r);
    final day = plannedStart ?? widget.completedAt;
    final media = MediaQuery.of(context);
    final width = math.min(media.size.width * 0.88, 420.0);
    final pace = r == null ? null : durationFeedbackLabel(r.durationFeedback);

    final facts = <(String, String)>[
      if (done) ('Completed', widget.completedAt != null ? time.format(widget.completedAt!) : 'Time not recorded'),
      if (plannedText.isNotEmpty) ('Planned', plannedText),
      ('Duration', r != null ? '${r.actualMinutes} min · planned $plannedMinutes' : '$plannedMinutes min planned'),
      if (done && r != null) ('How it felt', TaskReflection.feelingLabel(r.feeling)),
      if (done && pace != null) ('Pace', pace),
    ];

    final subtitle = [
      if (day != null) DateFormat('EEEE, MMMM d').format(day),
      if (category != null) category,
    ].join(' · ');

    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        key: const Key('history_moment_sheet'),
        color: FlowColors.surface(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(left: Radius.circular(FlowRadii.cardLarge))),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: media.size.height,
          child: SafeArea(
            left: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      key: const Key('history_moment_close'),
                      tooltip: 'Close',
                      icon: const Icon(Icons.close_rounded),
                      color: FlowColors.textMutedOf(context),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  NoyaMotionView(pose: pose, size: 88, enter: true, reactions: _reactions),
                  const SizedBox(height: 16),
                  Text(
                    done ? 'Finished' : (item.isMissed ? 'Missed' : 'Planned'),
                    style: FlowTypography.labelMedium(color: done ? FlowColors.successOf(context) : FlowColors.textMutedOf(context))
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.title,
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context))
                        .copyWith(fontWeight: FontWeight.w800, height: 1.2),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))),
                  ],
                  if (plannedStart != null && done && widget.completedAt != null) ...[
                    const SizedBox(height: 24),
                    _TimeRibbon(
                      plannedStart: plannedStart,
                      plannedMinutes: plannedMinutes,
                      completedAt: widget.completedAt!,
                      actualMinutes: r != null && r.actualMinutes > 0 ? r.actualMinutes : null,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Divider(height: 1, color: FlowColors.border(context)),
                  const SizedBox(height: 12),
                  for (final (label, value) in facts) _Fact(label: label, value: value),
                  if (done && r != null) ...[
                    const SizedBox(height: 16),
                    _Signal(name: 'Energy', value: r.energy),
                    _Signal(name: 'Focus', value: r.focus),
                    _Signal(name: 'Difficulty', value: r.difficulty),
                    _Signal(name: 'Distraction', value: r.distraction),
                    if (r.note != null && r.note!.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        r.note!,
                        style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context))
                            .copyWith(fontStyle: FontStyle.italic, height: 1.45),
                      ),
                    ],
                  ] else if (done) ...[
                    const SizedBox(height: 12),
                    Text(
                      'No reflection recorded for this task on this device.',
                      style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Planned slot against what really happened, on one shared clock: the planned block as an
/// outline on the upper lane, the actual session as a filled bar ending at the completion time.
class _TimeRibbon extends StatelessWidget {
  final DateTime plannedStart;
  final int plannedMinutes;
  final DateTime completedAt;

  /// Recorded session length; without it only the completion moment is known.
  final int? actualMinutes;

  const _TimeRibbon({required this.plannedStart, required this.plannedMinutes, required this.completedAt, this.actualMinutes});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final plannedEnd = plannedStart.add(Duration(minutes: plannedMinutes));
    final actualStart = actualMinutes == null ? null : completedAt.subtract(Duration(minutes: actualMinutes!));
    final from = [plannedStart, if (actualStart != null) actualStart, completedAt].reduce((a, b) => a.isBefore(b) ? a : b);
    final to = [plannedEnd, completedAt].reduce((a, b) => a.isAfter(b) ? a : b);
    final span = math.max(1, to.difference(from).inMinutes);
    double at(DateTime t) => t.difference(from).inMinutes / span;
    final hm = DateFormat('h:mm');
    final delta = completedAt.difference(plannedEnd).inMinutes;
    final verdict =
        delta.abs() <= 5 ? 'Finished on plan' : (delta < 0 ? 'Finished ${-delta} min early' : 'Finished $delta min past the plan');

    return Semantics(
      label: 'Planned ${hm.format(plannedStart)} to ${hm.format(plannedEnd)}, finished ${hm.format(completedAt)}. $verdict',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 40,
            width: double.infinity,
            child: CustomPaint(
              painter: _RibbonPainter(
                plannedFrom: at(plannedStart),
                plannedTo: at(plannedEnd),
                actualFrom: actualStart == null ? null : at(actualStart),
                actualTo: at(completedAt),
                accent: accent,
                outline: FlowColors.textMutedOf(context),
                track: FlowColors.border(context),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Plan ${hm.format(plannedStart)}–${hm.format(plannedEnd)}',
                  style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
              Text(verdict, style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final double plannedFrom;
  final double plannedTo;
  final double? actualFrom;
  final double actualTo;
  final Color accent;
  final Color outline;
  final Color track;

  _RibbonPainter({
    required this.plannedFrom,
    required this.plannedTo,
    required this.actualFrom,
    required this.actualTo,
    required this.accent,
    required this.outline,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 7.0;
    final w = size.width - pad * 2;
    double x(double f) => pad + w * f;
    canvas.drawRRect(
      RRect.fromLTRBR(x(plannedFrom), 4, x(plannedTo), 16, const Radius.circular(6)),
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.drawLine(
      const Offset(pad, 30),
      Offset(size.width - pad, 30),
      Paint()
        ..color = track
        ..strokeWidth = 1,
    );
    if (actualFrom != null) {
      canvas.drawRRect(RRect.fromLTRBR(x(actualFrom!), 24, x(actualTo), 36, const Radius.circular(6)), Paint()..color = accent);
    } else {
      canvas.drawCircle(Offset(x(actualTo), 30), 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.plannedFrom != plannedFrom ||
      old.plannedTo != plannedTo ||
      old.actualFrom != actualFrom ||
      old.actualTo != actualTo ||
      old.accent != accent ||
      old.outline != outline ||
      old.track != track;
}

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
          ),
          Expanded(
            child: Text(
              value,
              style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 1–5 reflection signal as five pips (filled up to the value).
class _Signal extends StatelessWidget {
  final String name;
  final int value;

  const _Signal({required this.name, required this.value});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      label: '$name $value of 5',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          key: Key('history_signal_${name.toLowerCase()}_$value'),
          children: [
            SizedBox(width: 110, child: Text(name, style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)))),
            for (var i = 1; i <= 5; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnimatedContainer(
                  duration: FlowMotion.microDuration,
                  width: 18,
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: FlowRadii.pillRadius,
                    color: i <= value ? accent.withValues(alpha: 0.85) : FlowColors.border(context),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
