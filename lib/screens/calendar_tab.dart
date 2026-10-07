import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/companion/noya_reaction_controller.dart';
import '../components/flow_date_strip.dart';
import '../components/flow_month_picker.dart';
import '../components/flow_day_path.dart';
import '../components/noya_motion_view.dart';
import '../components/primary_button.dart';
import '../components/skeleton_loaders.dart';
import '../components/timeline_item_widget.dart';
import '../engines/day_path_order.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_motion.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

import 'package:intl/intl.dart';
import '../components/edit_task_sheet.dart';
import '../models/schedule_item.dart';
import '../models/task_item.dart';
import '../services/flow_clock.dart';
import 'brain_dump_sheet.dart';
import 'replan_day_sheet.dart';

/// How Calendar shows a day: the history path (default) or the classic timeline list.
enum CalendarView { path, list }

/// Screen 8: Calendar Tab with Focus Windows & "Optimize My Day" Engine Action
class CalendarTab extends StatefulWidget {
  final CalendarView initialView;

  const CalendarTab({super.key, this.initialView = CalendarView.path});

  /// Noya's mood on an empty day (spec §7.1, D5): wind-down on an evening today, otherwise rest.
  /// The full day-mood resolver (asleep once the day is finished) arrives with Today's Noya (M4).
  static NoyaMood emptyMoodFor(DateTime now, {required bool isToday}) {
    if (isToday && now.hour >= 20) return NoyaMood.windDown;
    return NoyaMood.rest;
  }

  @override
  State<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<CalendarTab> {
  /// Used only when no [FlowProvider] is above Calendar (tests, isolated previews).
  NoyaReactionController? _localReactions;
  DateTime? _shownDate;
  bool _slideForward = true;
  bool _replanSheetOpen = false;

  // The route moves past a slot that ended on its own: re-derive against the clock every minute (and on resume).
  void _onClockTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    FlowClock().addListener(_onClockTick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final state = Provider.of<AppStateProvider>(context, listen: false);
        if (state.selectedDateSchedule == null) {
          state.loadCalendarDay(state.selectedCalendarDate);
        }
      }
    });
  }

  @override
  void dispose() {
    FlowClock().removeListener(_onClockTick);
    _localReactions?.dispose();
    super.dispose();
  }

  NoyaReactionController get _reactions {
    try {
      return Provider.of<FlowProvider>(context, listen: false).animController.reactions;
    } catch (_) {
      return _localReactions ??= NoyaReactionController();
    }
  }

  List<DateTime> _daysFor(DateTime selected) {
    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    // Two weeks of history behind today (finished days stay explorable) and 12 days ahead.
    final window = List.generate(27, (index) => today.add(Duration(days: index - 14)));
    if (!selected.isBefore(window.first) && !selected.isAfter(window.last)) return window;
    // A day picked from the month view outside that window: the strip re-centres on it.
    return List.generate(27, (index) => selected.add(Duration(days: index - 13)));
  }

  Future<void> _openMonthPicker(AppStateProvider state, DateTime selected, DateTime today) async {
    FlowHaptics.lightTap();
    // Dots only from tasks already in memory: drawing the month never costs a request.
    final days = <DateTime>{};
    for (final t in state.tasks) {
      final d = t.plannedDate ?? t.scheduledStart;
      if (d != null) days.add(DateTime(d.year, d.month, d.day));
    }
    final picked = await showFlowMonthPicker(context, selected: selected, today: today, daysWithTasks: days);
    if (picked != null && mounted) state.loadCalendarDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final pageMargin = FlowSpacing.pageMargin(context);
    final accent = Theme.of(context).colorScheme.primary;

    final now = FlowClock().now;
    final today = DateTime(now.year, now.month, now.day);
    final selectedDate = DateTime(
      state.selectedCalendarDate.year,
      state.selectedCalendarDate.month,
      state.selectedCalendarDate.day,
    );

    // Direction of the date-change slide (§8.4): forward dates enter from the right.
    if (_shownDate != selectedDate) {
      if (_shownDate != null) _slideForward = selectedDate.isAfter(_shownDate!);
      _shownDate = selectedDate;
    }

    final daySchedule = state.selectedDateSchedule;
    final hasTimeline = daySchedule?.timeline.isNotEmpty ?? false;
    final focusWindow = daySchedule?.focusWindow ?? state.readiness.focusWindowRange;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: hasTimeline
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8.0, right: 4.0),
              child: Material(
                elevation: 4,
                shadowColor: accent.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(FlowRadii.pill),
                color: FlowColors.surfaceElevated(context),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(FlowRadii.pill),
                    border: Border.all(color: accent.withValues(alpha: 0.35), width: 1.5),
                  ),
                  child: TextButton.icon(
                    key: const Key('calendar_replan_button'),
                    onPressed: () {
                      if (_replanSheetOpen) return; // taps before the sheet's barrier exists: one sheet
                      _replanSheetOpen = true;
                      FlowHaptics.lightTap();
                      showReplanDaySheet(
                        context,
                        selectedDate: selectedDate,
                        currentSchedule: state.selectedDateSchedule,
                      ).whenComplete(() => _replanSheetOpen = false);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: accent,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.pill)),
                      textStyle: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w700),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Replan'),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: pageMargin, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title + selected date, month picker alone in top right
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Calendar',
                          style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('EEEE, MMMM d').format(selectedDate),
                          key: const Key('calendar_selected_date_header'),
                          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 2),
                    child: Tooltip(
                      message: 'Pick a day',
                      child: Semantics(
                        button: true,
                        label: 'Open month view',
                        excludeSemantics: true,
                        child: InkWell(
                          key: const Key('calendar_month_picker_button'),
                          onTap: () => _openMonthPicker(state, selectedDate, today),
                          borderRadius: FlowRadii.chipRadius,
                          child: Ink(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: FlowRadii.chipRadius,
                            ),
                            child: Icon(Icons.calendar_month_rounded, size: 20, color: accent),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FlowDateStrip(
                days: _daysFor(selectedDate),
                selected: selectedDate,
                today: today,
                onSelect: state.loadCalendarDay,
              ),
              const SizedBox(height: 16),

              // Focus window: one line of context for the timeline (B2.3)
              ConstrainedBox(
                key: const Key('calendar_focus_window'),
                constraints: const BoxConstraints(maxHeight: 32),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded, color: accent, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _FocusWindow.parse(focusWindow) != null ? 'Focus window $focusWindow' : focusWindow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Day section: the canonical path through the day
              Text(
                'Your day',
                style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              _DaySwitcher(
                forward: _slideForward,
                child: KeyedSubtree(
                  key: ValueKey<DateTime>(selectedDate),
                  child: KeyedSubtree(
                    key: const Key('calendar_day_content'),
                    child: _buildDayContent(context, state, selectedDate, now, focusWindow),
                  ),
                ),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayContent(BuildContext context, AppStateProvider state, DateTime selectedDate, DateTime now, String focusWindow) {
    if (state.isLoadingCalendarDay && state.selectedDateSchedule == null) {
      return const _TimelineSkeleton(key: Key('calendar_loading_skeleton'));
    }

    final daySchedule = state.selectedDateSchedule;
    final dayTasks = daySchedule?.timeline ?? [];
    final unscheduled = daySchedule?.unscheduledTasks ?? [];
    // History nodes (skipped / deferred / missed at their original slot) stay on the day they happened.
    final history = daySchedule?.deviations ?? const <ScheduleItem>[];
    final allItems = [...dayTasks, ...unscheduled];

    if (allItems.isEmpty && history.isEmpty) {
      final isTodaySelected = selectedDate.year == now.year && selectedDate.month == now.month && selectedDate.day == now.day;
      return _EmptyDay(
        dayName: DateFormat('EEEE').format(selectedDate),
        mood: CalendarTab.emptyMoodFor(now, isToday: isTodaySelected),
        reactions: _reactions,
      );
    }

    final isToday = (daySchedule?.isToday ?? false) ||
        (selectedDate.year == now.year && selectedDate.month == now.month && selectedDate.day == now.day);
    final isPast = selectedDate.isBefore(DateTime(now.year, now.month, now.day));

    final bedtimeHour = state.personalData.bedtimeHour;
    final skippedHere = state.skippedTaskIdsOn(selectedDate);
    final doneHere = state.locallyCompletedTaskIds;

    // Enrich items with semantic deviation, recovery, and failure states
    final enrichedItems = <ScheduleItem>[...allItems.map((item) {
      final key = item.taskId ?? item.id;
      final cleanKey = key.startsWith('sched-') ? key.substring(6) : key;
      // completed here a moment ago: drawn done at once, before the server's day is re-read
      if (!item.isCompleted && item.taskId != null && doneHere.contains(cleanKey) && !item.isCommitment) {
        item = item.copyWith(isCompleted: true, isActive: false, isMissed: false);
      }
      final isSkippedExplicitly = !item.isCompleted &&
          (skippedHere.contains(key) ||
              skippedHere.contains(cleanKey) ||
              item.isSkipped);
      final isCompletedAfterDev = item.isCompleted &&
          (state.completedAfterDeviationTaskIds.contains(key) ||
              state.completedAfterDeviationTaskIds.contains(cleanKey) ||
              item.isCompletedAfterDeviation);

      if (item.isCompleted) {
        return item.copyWith(
          isSkipped: false,
          isCompletedAfterDeviation: isCompletedAfterDev,
          isFailed: false,
        );
      }

      // scheduled / missed / failed come from the one rule shared with the backend (engines/task_state.dart),
      // recomputed against the live clock and the user's bedtime: a slot that ended unstarted is missed (recoverable
      // through Replan/Redo, kept at its original place) and only fails once the day's sleep boundary has passed.
      final derived = item.withDerivedState(now: now, bedtimeHours: bedtimeHour);
      final isFailed = derived.isFailed;
      final isSkipped = isSkippedExplicitly && !isFailed;

      return derived.copyWith(
        isSkipped: isSkipped,
        isCompletedAfterDeviation: false,
        isMissed: derived.isMissed && !isSkippedExplicitly,
      );
    }), ...history];

    // THE stop list: one stop per task, sorted once by its anchor (history slot / first place seen / planned slot),
    // with a stable id. State changes (done, skipped, bypassed, recovered, Do this now) redraw the stop and the route;
    // they never move a stop or remount it.
    final orderedItems = buildCanonicalDayStops(
      live: enrichedItems.where((i) => i.deviation == null).toList(),
      history: history,
      anchors: state.dayPathAnchorsFor(selectedDate),
    );

    // Where the traveller is (only on today): the Do-this-now pick, a running task, else the next open stop in path
    // order. Bypassed / skipped / missed stops are never the target.
    final String? nowItemId = isToday
        ? pickDayPathNowId(
            orderedItems,
            now: now,
            preferredTaskId: state.preferredActiveTaskId,
            focusTaskId: state.activeFocusTask?.id,
          )
        : null;

    DateTime? completedAt(ScheduleItem item) {
      final id = item.taskId;
      if (id == null) return null;
      for (final t in state.tasks) {
        if (t.id == id) return t.completedAt;
      }
      return null;
    }

    String? categoryOf(ScheduleItem item) {
      final id = item.taskId;
      if (id == null) return null;
      for (final t in state.tasks) {
        if (t.id == id) return t.category;
      }
      return null;
    }

    final timeline = FlowDayPath(
      items: orderedItems,
      nowItemId: isToday ? nowItemId : null,
      dayComplete: daySchedule?.dayComplete,
      onClaimTrophy: state.isAuthenticated
          ? () async {
              final res = await state.claimDayComplete(selectedDate);
              if (res == null) throw StateError('not claimed');
              FlowHaptics.success();
              if (context.mounted) {
                final xp = (res['xp_awarded'] as num?)?.toInt() ?? 0;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(xp > 0 ? 'Noya earned +$xp XP for finishing the day.' : 'Already collected for this day.'),
                ));
              }
            }
          : null,
      reflectionFor: (item) => state.reflectionFor(item.taskId ?? item.id) ?? state.reflectionFor(item.id),
      completedAtFor: completedAt,
      categoryFor: categoryOf,
      onTap: (item) {
        if (item.deviation != null) return; // history node: the live task is on its new slot
        if (item.isCompleted) {
          showHistoryMomentSheet(
            context,
            item: item,
            category: categoryOf(item),
            reflection: state.reflectionFor(item.taskId ?? item.id) ?? state.reflectionFor(item.id),
            completedAt: completedAt(item),
          );
        } else {
          _showCalendarTaskActionSheet(
            context: context,
            item: item,
            state: state,
            isCurrent: isToday && item.id == nowItemId,
          );
        }
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (enrichedItems.isNotEmpty) ...[
          _DaySummary(
            items: enrichedItems.where((i) => i.deviation == null).toList(),
            isPast: isPast,
            minutesFor: (item) {
              final r = state.reflectionFor(item.taskId ?? item.id) ?? state.reflectionFor(item.id);
              return r != null && r.actualMinutes > 0 ? r.actualMinutes : item.durationMinutes;
            },
          ),
          const SizedBox(height: 8),
        ],
        timeline,
      ],
    );
  }

  void _showCalendarTaskActionSheet({
    required BuildContext context,
    required ScheduleItem item,
    required AppStateProvider state,
    required bool isCurrent,
  }) {
    final dark = FlowColors.isDark(context);
    final accent = Theme.of(context).colorScheme.primary;
    final id = item.taskId ?? (item.id.startsWith('sched-') ? item.id.substring(6) : item.id);
    final matchingTask = state.tasks.cast<TaskItem?>().firstWhere(
      (t) => t?.id == id || t?.title.toLowerCase() == item.title.toLowerCase(),
      orElse: () => null,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: FlowColors.textMutedOf(context).withValues(alpha: 0.3),
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context))
                                .copyWith(fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.time} ${item.period} · ${item.durationMinutes} min',
                            style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: dark ? 0.2 : 0.12),
                          borderRadius: FlowRadii.pillRadius,
                          border: Border.all(color: accent.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'IN FOCUS',
                          style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w700),
                        ),
                      )
                    else if (item.isSkipped)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: dark ? 0.2 : 0.12),
                          borderRadius: FlowRadii.pillRadius,
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          'SKIPPED',
                          style: FlowTypography.labelSmall(color: const Color(0xFFF59E0B)).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 8),
                // A commitment (going out) is a fixed block, not work: no start/complete/skip.
                if (!isCurrent && !item.isCommitment)
                  _buildActionTile(
                    context: sheetContext,
                    key: const Key('calendar_action_do_now'),
                    icon: Icons.alt_route_rounded,
                    iconColor: accent,
                    title: item.isMissed ? 'Redo now' : 'Do this now',
                    subtitle: item.isMissed
                        ? 'Its time passed. Start it now; the miss stays on record'
                        : 'Reroute your planned path to start this task immediately',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      FlowHaptics.selection();
                      state.setPreferredActiveTask(id);
                    },
                  ),
                if (!item.isCommitment)
                _buildActionTile(
                  context: sheetContext,
                  key: const Key('calendar_action_mark_done'),
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: FlowColors.successOf(context),
                  title: 'Mark as completed',
                  subtitle: item.isSkipped
                      ? 'Record as recovered after deviation'
                      : 'Mark finished along today\'s path',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    FlowHaptics.success();
                    state.toggleTaskCompletion(id);
                  },
                ),
                if (!item.isSkipped && !isCurrent && !item.isCommitment)
                  _buildActionTile(
                    context: sheetContext,
                    key: const Key('calendar_action_skip'),
                    icon: Icons.arrow_forward_rounded,
                    iconColor: const Color(0xFFF59E0B),
                    title: 'Skip / Defer for now',
                    subtitle: 'Bypass this stop and reroute the active path',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      FlowHaptics.selection();
                      state.skipTask(id);
                    },
                  ),
                if (matchingTask != null)
                  _buildActionTile(
                    context: sheetContext,
                    key: const Key('calendar_action_edit'),
                    icon: Icons.edit_outlined,
                    iconColor: FlowColors.textSecondaryOf(context),
                    title: 'Edit task details',
                    subtitle: 'Change time, duration, focus requirement, or priority',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      FlowHaptics.lightTap();
                      EditTaskSheet.show(context, matchingTask);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      key: key,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: FlowColors.isDark(context) ? 0.15 : 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: FlowTypography.bodyLarge(color: FlowColors.textPrimaryOf(context))
            .copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
      ),
      onTap: onTap,
    );
  }
}

/// One quiet line above the path: how far through the day the user is (or got).
class _DaySummary extends StatelessWidget {
  final List<ScheduleItem> items;
  final bool isPast;
  final int Function(ScheduleItem item) minutesFor;

  const _DaySummary({required this.items, required this.isPast, required this.minutesFor});

  @override
  Widget build(BuildContext context) {
    final done = items.where((i) => i.isCompleted).length;
    final minutes = items.where((i) => i.isCompleted).fold<int>(0, (sum, i) => sum + minutesFor(i));
    final h = minutes ~/ 60;
    final m = minutes % 60;
    final time = minutes == 0 ? null : (h == 0 ? '$m min' : (m == 0 ? '${h}h' : '${h}h ${m}m'));
    final text = [
      isPast ? '$done of ${items.length} finished' : '$done of ${items.length} done',
      if (time != null) '$time of work',
    ].join(' · ');
    return Text(
      text,
      key: const Key('calendar_day_summary'),
      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context))
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
    );
  }
}

/// Date-change transition (§8.4): the incoming day slides 16 px from the side of travel and
/// fades in over 220 ms; the outgoing day fades out in place.
class _DaySwitcher extends StatelessWidget {
  final bool forward;
  final Widget child;

  const _DaySwitcher({required this.forward, required this.child});

  @override
  Widget build(BuildContext context) {
    final incomingKey = child.key;
    return AnimatedSwitcher(
      duration: FlowMotion.responsiveDuration(context, FlowMotion.standardDuration),
      switchInCurve: FlowMotion.easeOut,
      switchOutCurve: FlowMotion.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        if (child.key != incomingKey) return FadeTransition(opacity: animation, child: child);
        final dx = forward ? 16.0 : -16.0;
        return FadeTransition(
          opacity: animation,
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, child) => Transform.translate(offset: Offset(dx * (1 - animation.value), 0), child: child),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Keeps rows keyed by id so a reload animates only what changed (§8.5): inserted rows fade and
/// size in over 220 ms; removed rows fade out over 150 ms, then collapse over 180 ms.
class _AnimatedRows extends StatefulWidget {
  final List<ScheduleItem> items;
  final Widget Function(ScheduleItem item, bool isLast) builder;

  const _AnimatedRows({required this.items, required this.builder});

  @override
  State<_AnimatedRows> createState() => _AnimatedRowsState();
}

class _AnimatedRowsState extends State<_AnimatedRows> {
  late List<ScheduleItem> _shown = List.of(widget.items);
  final Set<String> _entering = {};
  final Set<String> _leaving = {};

  @override
  void didUpdateWidget(_AnimatedRows oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIds = widget.items.map((i) => i.id).toSet();
    final shownIds = _shown.map((i) => i.id).toSet();
    final merged = List.of(widget.items);
    for (var i = 0; i < _shown.length; i++) {
      final old = _shown[i];
      if (!nextIds.contains(old.id)) {
        _leaving.add(old.id);
        merged.insert(i.clamp(0, merged.length), old);
      }
    }
    for (final item in widget.items) {
      if (!shownIds.contains(item.id)) _entering.add(item.id);
      _leaving.remove(item.id);
    }
    _shown = merged;
  }

  void _removed(String id) {
    if (!mounted) return;
    setState(() {
      _leaving.remove(id);
      _shown.removeWhere((i) => i.id == id && !widget.items.any((n) => n.id == id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final present = _shown.where((i) => !_leaving.contains(i.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _shown)
          _RowTransition(
            key: Key('calendar_row_transition_${item.id}'),
            entering: _entering.remove(item.id),
            leaving: _leaving.contains(item.id),
            onRemoved: () => _removed(item.id),
            child: widget.builder(item, present.isNotEmpty && identical(item, present.last)),
          ),
      ],
    );
  }
}

class _RowTransition extends StatefulWidget {
  final bool entering;
  final bool leaving;
  final VoidCallback onRemoved;
  final Widget child;

  const _RowTransition({super.key, required this.entering, required this.leaving, required this.onRemoved, required this.child});

  @override
  State<_RowTransition> createState() => _RowTransitionState();
}

class _RowTransitionState extends State<_RowTransition> with SingleTickerProviderStateMixin {
  static const Duration _fadeOut = FlowMotion.microDuration; // 150 ms
  static const Duration _collapse = Duration(milliseconds: 180);

  late final AnimationController _controller = AnimationController(vsync: this);
  Animation<double> _opacity = const AlwaysStoppedAnimation(1);
  Animation<double> _size = const AlwaysStoppedAnimation(1);

  @override
  void initState() {
    super.initState();
    if (widget.entering) {
      // Start hidden so the first frame doesn't flash the row at full size.
      _opacity = _controller;
      _size = _controller;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _enter();
      });
    }
  }

  @override
  void didUpdateWidget(_RowTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.leaving && !oldWidget.leaving) {
      _leave();
    } else if (!widget.leaving && oldWidget.leaving) {
      _controller.stop();
      _opacity = const AlwaysStoppedAnimation(1);
      _size = const AlwaysStoppedAnimation(1);
    }
  }

  void _enter() {
    final duration = FlowMotion.responsiveDuration(context, FlowMotion.standardDuration);
    if (duration == Duration.zero) {
      setState(() {
        _opacity = const AlwaysStoppedAnimation(1);
        _size = const AlwaysStoppedAnimation(1);
      });
      return;
    }
    final curved = CurvedAnimation(parent: _controller, curve: FlowMotion.easeOut);
    setState(() {
      _opacity = curved;
      _size = curved;
    });
    _controller
      ..duration = duration
      ..forward(from: 0);
  }

  void _leave() {
    if (FlowMotion.isReducedMotion(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onRemoved());
      return;
    }
    final total = _fadeOut + _collapse;
    final split = _fadeOut.inMicroseconds / total.inMicroseconds;
    _opacity = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Interval(0, split, curve: FlowMotion.easeOut)),
    );
    _size = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Interval(split, 1, curve: FlowMotion.easeInOut)),
    );
    _controller
      ..duration = total
      ..forward(from: 0).whenCompleteOrCancel(() {
        if (mounted && widget.leaving && _controller.isCompleted) widget.onRemoved();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _size,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _opacity, child: widget.child),
    );
  }
}

/// Three skeleton rows in the timeline row geometry (B2.5), sharing one shimmer driver.
class _TimelineSkeleton extends StatelessWidget {
  const _TimelineSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final gutter = FlowTimelineRow.gutterWidthOf(context);
    return FlowShimmerScope(
      child: Column(
        children: List.generate(3, (i) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: gutter,
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowShimmerBox(width: 44, height: 16),
                      SizedBox(height: 6),
                      FlowShimmerBox(width: 32, height: 12),
                    ],
                  ),
                ),
                const SizedBox(width: 30),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FlowShimmerBox(width: i == 1 ? 140 : 190, height: 16),
                      const SizedBox(height: 8),
                      const FlowShimmerBox(width: 90, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Unboxed empty day with Noya (§7.1, B2.5): one greet per session, none under wind-down.
class _EmptyDay extends StatefulWidget {
  final String dayName;
  final NoyaMood mood;
  final NoyaReactionController reactions;

  const _EmptyDay({required this.dayName, required this.mood, required this.reactions});

  @override
  State<_EmptyDay> createState() => _EmptyDayState();
}

class _EmptyDayState extends State<_EmptyDay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.mood != NoyaMood.rest) return;
      if (widget.reactions.greetOnce('calendar_empty')) widget.reactions.react(NoyaReaction.greet);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            NoyaMotionView(
              mood: widget.mood,
              size: 72,
              enter: true,
              reactions: widget.reactions,
            ),
            const SizedBox(height: 12),
            Text(
              'No plan for ${widget.dayName} yet.',
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Tell Flowstate what you need to get done and we\'ll build the day.',
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            PrimaryButton(
              label: 'Build My Day',
              icon: const Icon(Icons.auto_awesome_rounded, color: FlowColors.textInverse, size: 18),
              onPressed: () {
                FlowHaptics.lightTap();
                showBrainDumpSheet(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A parsed focus window such as "9:30 AM – 11:30 AM" (or "8:30–11:30 AM"), in minutes of day.
class _FocusWindow {
  final int startMinute;
  final int endMinute;

  const _FocusWindow(this.startMinute, this.endMinute);

  static final RegExp _clock = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?');

  static int _minutes(String hour, String minute, String? period) {
    var h = int.parse(hour);
    if (period != null) {
      if (h == 12) h = 0;
      if (period.toUpperCase() == 'PM') h += 12;
    }
    return h * 60 + int.parse(minute);
  }

  static _FocusWindow? parse(String text) {
    final parts = text.split(RegExp(r'\s*[–—-]\s*'));
    if (parts.length != 2) return null;
    final a = _clock.firstMatch(parts[0]);
    final b = _clock.firstMatch(parts[1]);
    if (a == null || b == null) return null;
    final endPeriod = b.group(3);
    final start = _minutes(a.group(1)!, a.group(2)!, a.group(3) ?? endPeriod);
    final end = _minutes(b.group(1)!, b.group(2)!, endPeriod);
    if (end <= start) return null;
    return _FocusWindow(start, end);
  }

  bool contains(ScheduleItem item) {
    final m = _clock.firstMatch('${item.time} ${item.period}');
    if (m == null) return false;
    final t = _minutes(m.group(1)!, m.group(2)!, m.group(3));
    return t >= startMinute && t < endMinute;
  }
}

