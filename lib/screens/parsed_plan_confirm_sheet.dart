import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/noya_companion_view.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/plan_confirm_exception.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../theme/flow_haptics.dart';

/// Bottom sheet that shows parsed tasks for user review + quick confirmation.
///
/// Each card offers two independent edit drawers:
///   - Duration drawer  (15 / 30 / 45 / 60 / 90 / 120 min)
///   - Day & time drawer (Today / Tomorrow / +2 / +3 / Next week  Ã—  preset hours)
///
/// The day & time drawer reads and writes `TaskItem.scheduledStart` directly,
/// which is the same DateTime the scheduling engine consumes. `targetDate`
/// from `ExtractedTaskItem` is already folded into `scheduledStart` by
/// `toTaskItem()` upstream, so no additional model field is required here.
void showParsedPlanConfirmSheet(
  BuildContext context, {
  required List<TaskItem> candidates,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _ParsedPlanConfirmSheet(candidates: candidates),
  );
}

class _ParsedPlanConfirmSheet extends StatefulWidget {
  final List<TaskItem> candidates;
  const _ParsedPlanConfirmSheet({required this.candidates});
  @override
  State<_ParsedPlanConfirmSheet> createState() => _ParsedPlanConfirmSheetState();
}

class _ParsedPlanConfirmSheetState extends State<_ParsedPlanConfirmSheet> {
  late List<TaskItem> _tasks;
  int? _editingDurationIndex;
  int? _editingTimeIndex;
  bool _isSubmitting = false;
  final String _planId = 'plan-${DateTime.now().microsecondsSinceEpoch}'; // stable across retries

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.candidates);
  }

  Future<void> _confirm() async {
    if (_isSubmitting || _tasks.isEmpty) return;
    setState(() => _isSubmitting = true);
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    try {
      await provider.confirmCandidates(_tasks, planId: _planId);
    } on PlanConfirmException catch (e) {
      // Nothing was saved: keep the sheet open and say why.
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message, style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context))),
        backgroundColor: FlowColors.surfaceElevated(context),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${_tasks.length} task${_tasks.length == 1 ? '' : 's'} added to your plan',
        style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)),
      ),
      backgroundColor: FlowColors.surfaceElevated(context),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // â”€â”€â”€ Drawer toggles â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _toggleDurationDrawer(int index) {
    FlowHaptics.selection();
    setState(() {
      _editingTimeIndex = null;
      _editingDurationIndex = _editingDurationIndex == index ? null : index;
    });
  }

  void _toggleTimeDrawer(int index) {
    FlowHaptics.selection();
    setState(() {
      _editingDurationIndex = null;
      _editingTimeIndex = _editingTimeIndex == index ? null : index;
    });
  }

  // â”€â”€â”€ Edits â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _updateDuration(int index, int minutes) {
    FlowHaptics.selection();
    final task = _tasks[index];
    final updatedMissing = List<String>.from(task.missingFields)..remove('duration');
    setState(() {
      _tasks[index] = task.copyWith(
        durationMinutes: minutes,
        missingFields: updatedMissing,
      );
      _editingDurationIndex = null;
    });
  }

  /// Move the scheduled slot to a different calendar day, preserving the
  /// current time-of-day. Defaults to 09:00 if the task had no time yet.
  void _updateScheduledDay(int index, DateTime newDay) {
    FlowHaptics.selection();
    final task = _tasks[index];
    final existing = task.scheduledStart;
    final hour = existing?.hour ?? 9;
    final minute = existing?.minute ?? 0;
    final newStart = DateTime(newDay.year, newDay.month, newDay.day, hour, minute);
    setState(() {
      _tasks[index] = task.copyWith(
        scheduledStart: newStart,
        scheduledTime: _formatTimeFromDate(newStart),
      );
    });
  }

  /// Set (or clear, when hour is null) the scheduled time-of-day, keeping
  /// the current day. Defaults to today when the task had no date yet.
  void _updateScheduledHour(int index, int? hour) {
    FlowHaptics.selection();
    final task = _tasks[index];
    if (hour == null) {
      setState(() {
        _tasks[index] = task.copyWith(
          scheduledStart: null,
          scheduledTime: null,
        );
      });
      return;
    }
    final baseDay = task.scheduledStart ?? DateTime.now();
    final newStart = DateTime(baseDay.year, baseDay.month, baseDay.day, hour, 0);
    setState(() {
      _tasks[index] = task.copyWith(
        scheduledStart: newStart,
        scheduledTime: _formatTimeFromDate(newStart),
      );
    });
  }

  /// Quick AM â‡„ PM flip. Now derives everything from `scheduledStart` rather
  /// than string-replacing `scheduledTime`, so it is safe even when the
  /// display string is stale, null, or in an unexpected format.
  void _toggleAmPm(int index) {
    FlowHaptics.selection();
    final task = _tasks[index];
    final current = task.scheduledStart;
    if (current == null) return;
    final newStart = current.hour >= 12
        ? current.subtract(const Duration(hours: 12))
        : current.add(const Duration(hours: 12));
    final updatedAmbiguities = List<String>.from(task.ambiguities)
      ..remove('time_am_pm');
    setState(() {
      _tasks[index] = task.copyWith(
        scheduledStart: newStart,
        scheduledTime: _formatTimeFromDate(newStart),
        ambiguities: updatedAmbiguities,
      );
    });
  }

  // â”€â”€â”€ Formatting helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _formatTimeFromDate(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m.toString().padLeft(2, '0');
    return '$hour12:$mStr $ampm';
  }

  /// Renders `Friday Â· 5:00 PM`, `Tomorrow Â· 10:00 AM`, `Today Â· 5:00 PM`,
  /// or falls back to `scheduledTime` when there is no `scheduledStart`.
  String _formatScheduledLabel(TaskItem task) {
    final start = task.scheduledStart;
    if (start == null) return task.scheduledTime ?? 'No time';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(start.year, start.month, start.day);
    final diff = target.difference(today).inDays;
    final time = _formatTimeFromDate(start);

    if (diff == 0) return 'Today Â· $time';
    if (diff == 1) return 'Tomorrow Â· $time';
    if (diff > 1 && diff < 7) {
      const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${wd[target.weekday - 1]} Â· $time';
    }
    const mo = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${mo[target.month - 1]} ${target.day} Â· $time';
  }

  // â”€â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20.0,
          right: 20.0,
          top: 16.0,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: FlowColors.border(context),
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Canonical Noya Companion Header
            Builder(
              builder: (ctx) {
                FlowProvider? flowProvider;
                try {
                  flowProvider = Provider.of<FlowProvider>(ctx, listen: true);
                } catch (_) {}
                final companion = flowProvider?.companion;
                final name = companion?.name ?? 'Noya';

                return Container(
                  key: const Key('noya_companion_header'),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: FlowColors.surfaceElevated(context),
                    borderRadius: FlowRadii.cardRadius,
                    border: Border.all(color: FlowColors.border(context)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const NoyaCompanionView(
                        state: NoyaState.proud,
                        size: 72.0,
                        showAmbientGlow: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              style: FlowTypography
                                  .labelLarge(color: FlowColors.textPrimaryOf(context))
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$name reviewed your candidate tasks.',
                              style: FlowTypography
                                  .bodySmall(color: FlowColors.textSecondaryOf(context))
                                  .copyWith(height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review parsed tasks',
                      style: FlowTypography.titleMedium()
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quick confirm or tap pills to adjust',
                      style: FlowTypography
                          .bodySmall(color: FlowColors.textMutedOf(context)),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                  child: Text(
                    '${_tasks.length} found',
                    style: FlowTypography.labelSmall(color: accent)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Task cards list
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tasks.length,
                itemBuilder: (ctx, i) => _buildCandidateCard(i, accent),
              ),
            ),
            const SizedBox(height: 16),

            // Single Final Action: [ Add & Schedule ]
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                key: const Key('add_and_schedule_button'),
                onPressed: (_tasks.isEmpty || _isSubmitting) ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _tasks.isEmpty ? FlowColors.border(context) : accent,
                  foregroundColor: FlowColors.textInverse,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(
                      borderRadius: FlowRadii.buttonRadius),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: FlowColors.textInverse, strokeWidth: 2),
                      )
                    : Text(
                        'Add & Schedule',
                        style: FlowTypography
                            .labelLarge(color: FlowColors.textInverse)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCandidateCard(int i, Color accent) {
    final task = _tasks[i];
    final editingDuration = _editingDurationIndex == i;
    final editingTime = _editingTimeIndex == i;
    final isAmbiguousTime = task.ambiguities.contains('time_am_pm');
    final isMissingDuration = task.missingFields.contains('duration');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: (editingDuration || editingTime) ? accent : FlowColors.border(context),
          width: (editingDuration || editingTime) ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Title and Delete Button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: FlowTypography.bodyLarge()
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  FlowHaptics.lightTap();
                  setState(() {
                    _tasks.removeAt(i);
                    _editingDurationIndex = null;
                    _editingTimeIndex = null;
                  });
                },
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(Icons.close_rounded,
                      size: 18, color: FlowColors.textMutedOf(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Pills (Duration Â· Scheduled day+time Â· Deadline Â· Type)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // â”€â”€ Duration pill â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              GestureDetector(
                onTap: () => _toggleDurationDrawer(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isMissingDuration
                        ? FlowColors.warning.withValues(alpha: 0.12)
                        : FlowColors.surface(context),
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(
                      color: isMissingDuration
                          ? FlowColors.warning
                          : FlowColors.border(context),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: isMissingDuration
                            ? FlowColors.warning
                            : FlowColors.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMissingDuration
                            ? 'Estimated ${task.durationMinutes} min'
                            : '${task.durationMinutes} min',
                        style: FlowTypography.labelSmall(
                          color: isMissingDuration
                              ? FlowColors.warning
                              : FlowColors.textSecondaryOf(context),
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        editingDuration
                            ? Icons.arrow_drop_up_rounded
                            : Icons.arrow_drop_down_rounded,
                        size: 14,
                        color: FlowColors.textMutedOf(context),
                      ),
                    ],
                  ),
                ),
              ),

              // â”€â”€ Scheduled day + time pill â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // Renders "Friday Â· 5:00 PM" (or "Today Â· 5:00 PM") using the
              // task's own `scheduledStart`, so the target day is always
              // visible and editable.
              if (task.scheduledStart != null || task.scheduledTime != null)
                GestureDetector(
                  onTap: () => _toggleTimeDrawer(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isAmbiguousTime
                          ? FlowColors.accentCyan.withValues(alpha: 0.14)
                          : FlowColors.surface(context),
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(
                        color: isAmbiguousTime
                            ? FlowColors.accentCyan
                            : FlowColors.border(context),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded,
                            size: 13, color: FlowColors.accentCyan),
                        const SizedBox(width: 4),
                        Text(
                          _formatScheduledLabel(task),
                          style: FlowTypography
                              .labelSmall(color: FlowColors.textPrimaryOf(context))
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        // Quick AM â‡„ PM flip for ambiguous times only.
                        if (isAmbiguousTime && task.scheduledStart != null) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _toggleAmPm(i),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 2),
                              child: Icon(Icons.swap_horiz_rounded,
                                  size: 14, color: FlowColors.accentCyan),
                            ),
                          ),
                        ],
                        const SizedBox(width: 2),
                        Icon(
                          editingTime
                              ? Icons.arrow_drop_up_rounded
                              : Icons.arrow_drop_down_rounded,
                          size: 14,
                          color: FlowColors.textMutedOf(context),
                        ),
                      ],
                    ),
                  ),
                ),

              // â”€â”€ Deadline pill â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              // `toTaskItem()` injects 'Today' as a fallback whenever the
              // backend supplies no real deadline. That sentinel must never
              // be shown as a user-facing deadline, otherwise a target date
              // ("Friday at 5 PM") looks like an implicit deadline. We cannot
              // fix the source of that fallback from this file.
              if (task.deadline.isNotEmpty && task.deadline != 'Today')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: FlowColors.surface(context),
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: FlowColors.border(context)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: FlowColors.textMutedOf(context)),
                      const SizedBox(width: 4),
                      Text(
                        'Due ${task.deadline}',
                        style: FlowTypography
                            .labelSmall(color: FlowColors.textSecondaryOf(context)),
                      ),
                    ],
                  ),
                ),

              // â”€â”€ Type / Difficulty badge â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(task.difficulty).withValues(alpha: 0.12),
                  borderRadius: FlowRadii.pillRadius,
                ),
                child: Text(
                  task.difficulty.tagText,
                  style: FlowTypography
                      .labelSmall(color: _getDifficultyColor(task.difficulty))
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                ),
              ),
            ],
          ),

          // â”€â”€ Duration drawer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (editingDuration) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FlowColors.surface(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select duration:',
                      style: FlowTypography
                          .labelSmall(color: FlowColors.textMutedOf(context))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [15, 30, 45, 60, 90, 120].map((m) {
                      final sel = task.durationMinutes == m;
                      return GestureDetector(
                        onTap: () => _updateDuration(i, m),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel
                                ? accent.withValues(alpha: 0.18)
                                : FlowColors.surfaceElevated(context),
                            borderRadius: FlowRadii.pillRadius,
                            border: Border.all(
                                color: sel ? accent : FlowColors.border(context)),
                          ),
                          child: Text(
                            '$m min',
                            style: FlowTypography
                                .labelSmall(
                                  color: sel ? accent : FlowColors.textSecondaryOf(context),
                                )
                                .copyWith(
                                    fontWeight:
                                        sel ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // â”€â”€ Day & time drawer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          if (editingTime) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FlowColors.surface(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select day:',
                      style: FlowTypography
                          .labelSmall(color: FlowColors.textMutedOf(context))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _buildDayChips(i, accent),
                  ),
                  const SizedBox(height: 12),
                  Text('Select time:',
                      style: FlowTypography
                          .labelSmall(color: FlowColors.textMutedOf(context))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _buildTimeChips(i, accent),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // â”€â”€â”€ Chips for the day/time drawer â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  List<Widget> _buildDayChips(int index, Color accent) {
    final task = _tasks[index];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final current = task.scheduledStart;
    final currentDay = current != null
        ? DateTime(current.year, current.month, current.day)
        : null;

    final options = <MapEntry<String, DateTime>>[
      MapEntry('Today', today),
      MapEntry('Tomorrow', today.add(const Duration(days: 1))),
      MapEntry('+2d', today.add(const Duration(days: 2))),
      MapEntry('+3d', today.add(const Duration(days: 3))),
      MapEntry('Next week', today.add(const Duration(days: 7))),
    ];

    return options.map((opt) {
      final sel = currentDay != null &&
          currentDay.year == opt.value.year &&
          currentDay.month == opt.value.month &&
          currentDay.day == opt.value.day;
      return GestureDetector(
        onTap: () => _updateScheduledDay(index, opt.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: sel
                ? accent.withValues(alpha: 0.18)
                : FlowColors.surfaceElevated(context),
            borderRadius: FlowRadii.pillRadius,
            border: Border.all(color: sel ? accent : FlowColors.border(context)),
          ),
          child: Text(
            opt.key,
            style: FlowTypography
                .labelSmall(
                  color: sel ? accent : FlowColors.textSecondaryOf(context),
                )
                .copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildTimeChips(int index, Color accent) {
    final task = _tasks[index];
    final current = task.scheduledStart;
    // null = "No fixed time"; otherwise 24-h hour to set.
    final options = <int?>[null, 9, 12, 14, 17, 18, 20];

    return options.map((h) {
      final sel = h == null
          ? current == null
          : (current != null && current.hour == h);
      final label = h == null
          ? 'No fixed time'
          : _formatTimeFromDate(DateTime(2024, 1, 1, h, 0));
      return GestureDetector(
        onTap: () => _updateScheduledHour(index, h),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: sel
                ? accent.withValues(alpha: 0.18)
                : FlowColors.surfaceElevated(context),
            borderRadius: FlowRadii.pillRadius,
            border: Border.all(color: sel ? accent : FlowColors.border(context)),
          ),
          child: Text(
            label,
            style: FlowTypography
                .labelSmall(
                  color: sel ? accent : FlowColors.textSecondaryOf(context),
                )
                .copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
          ),
        ),
      );
    }).toList();
  }

  Color _getDifficultyColor(TaskDifficulty difficulty) {
    switch (difficulty) {
      case TaskDifficulty.high:
        return FlowColors.accentCyan;
      case TaskDifficulty.medium:
        return FlowColors.accentMint;
      case TaskDifficulty.light:
        return FlowColors.accentBlue;
      case TaskDifficulty.physical:
        return FlowColors.accentLime;
    }
  }
}