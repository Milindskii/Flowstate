import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import '../theme/flow_haptics.dart';

/// Bottom sheet that shows parsed tasks for user review + quick confirmation.
/// Shows title, duration, deadline/time (with AM/PM toggle for ambiguous times), and type.
void showParsedPlanConfirmSheet(
  BuildContext context, {
  required List<TaskItem> candidates,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.darkSurface,
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
  int? _editingIndex;

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.candidates);
  }

  void _confirm() {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.confirmCandidates(_tasks);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${_tasks.length} task${_tasks.length == 1 ? '' : 's'} added to your plan',
        style: FlowTypography.bodySmall(color: FlowColors.textPrimary),
      ),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _toggleAmPm(int index) {
    FlowHaptics.selection();
    final task = _tasks[index];
    final curTime = task.scheduledTime ?? '';
    String newTime = curTime;
    DateTime? newStart = task.scheduledStart;

    if (curTime.contains('PM')) {
      newTime = curTime.replaceAll('PM', 'AM');
      if (newStart != null) {
        newStart = newStart.subtract(const Duration(hours: 12));
      }
    } else if (curTime.contains('AM')) {
      newTime = curTime.replaceAll('AM', 'PM');
      if (newStart != null) {
        newStart = newStart.add(const Duration(hours: 12));
      }
    }

    final updatedAmbiguities = List<String>.from(task.ambiguities)..remove('time_am_pm');

    setState(() {
      _tasks[index] = task.copyWith(
        scheduledTime: newTime,
        scheduledStart: newStart,
        ambiguities: updatedAmbiguities,
      );
    });
  }

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
                decoration: const BoxDecoration(
                  color: FlowColors.darkBorder,
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Review parsed tasks',
                      style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Quick confirm or tap pills to adjust',
                      style: FlowTypography.bodySmall(color: FlowColors.textMuted),
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
                    style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Task cards list
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.48),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tasks.length,
                itemBuilder: (ctx, i) => _buildCandidateCard(i, accent),
              ),
            ),
            const SizedBox(height: 16),

            // Bottom Add Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _tasks.isEmpty ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tasks.isEmpty ? FlowColors.darkBorder : accent,
                  foregroundColor: FlowColors.textInverse,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: Text(
                  'Add ${_tasks.length} task${_tasks.length == 1 ? '' : 's'}',
                  style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700),
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
    final editing = _editingIndex == i;
    final isAmbiguousTime = task.ambiguities.contains('time_am_pm');
    final isMissingDuration = task.missingFields.contains('duration');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: editing ? accent : FlowColors.darkBorder,
          width: editing ? 1.5 : 1.0,
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
                  style: FlowTypography.bodyLarge().copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  FlowHaptics.lightTap();
                  setState(() {
                    _tasks.removeAt(i);
                    _editingIndex = null;
                  });
                },
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(Icons.close_rounded, size: 18, color: FlowColors.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Pills (Duration, Scheduled Time / AM-PM toggle, Deadline, Type badge)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              // Duration Pill (Tap to edit)
              GestureDetector(
                onTap: () => setState(() => _editingIndex = editing ? null : i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isMissingDuration
                        ? FlowColors.warning.withValues(alpha: 0.12)
                        : FlowColors.darkCardElevated,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(
                      color: isMissingDuration ? FlowColors.warning : FlowColors.darkBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: isMissingDuration ? FlowColors.warning : FlowColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isMissingDuration ? '${task.durationMinutes}m (default)' : '${task.durationMinutes} min',
                        style: FlowTypography.labelSmall(
                          color: isMissingDuration ? FlowColors.warning : FlowColors.textSecondary,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        editing ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                        size: 14,
                        color: FlowColors.textMuted,
                      ),
                    ],
                  ),
                ),
              ),

              // Time Pill with AM/PM toggle if ambiguous
              if (task.scheduledTime != null)
                GestureDetector(
                  onTap: () => _toggleAmPm(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isAmbiguousTime
                          ? FlowColors.accentCyan.withValues(alpha: 0.14)
                          : FlowColors.darkCardElevated,
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(
                        color: isAmbiguousTime ? FlowColors.accentCyan : FlowColors.darkBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule_rounded, size: 13, color: FlowColors.accentCyan),
                        const SizedBox(width: 4),
                        Text(
                          isAmbiguousTime ? '${task.scheduledTime} ⇄' : task.scheduledTime!,
                          style: FlowTypography.labelSmall(color: FlowColors.textPrimary).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Deadline Pill
              if (task.deadline.isNotEmpty && task.deadline != 'Today')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: FlowColors.darkCardElevated,
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: FlowColors.darkBorder),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 12, color: FlowColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        task.deadline,
                        style: FlowTypography.labelSmall(color: FlowColors.textSecondary),
                      ),
                    ],
                  ),
                ),

              // Type / Difficulty Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getDifficultyColor(task.difficulty).withValues(alpha: 0.12),
                  borderRadius: FlowRadii.pillRadius,
                ),
                child: Text(
                  task.difficulty.tagText,
                  style: FlowTypography.labelSmall(
                    color: _getDifficultyColor(task.difficulty),
                  ).copyWith(fontWeight: FontWeight.w700, fontSize: 10),
                ),
              ),
            ],
          ),

          // Duration picker drawer when editing
          if (editing) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: FlowColors.darkCardElevated,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select duration:', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [15, 30, 45, 60, 90, 120].map((m) {
                      final sel = task.durationMinutes == m;
                      return GestureDetector(
                        onTap: () {
                          FlowHaptics.selection();
                          final updatedMissing = List<String>.from(task.missingFields)..remove('duration');
                          final u = List<TaskItem>.from(_tasks)
                            ..[i] = task.copyWith(durationMinutes: m, missingFields: updatedMissing);
                          setState(() {
                            _tasks = u;
                            _editingIndex = null;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sel ? accent.withValues(alpha: 0.18) : FlowColors.darkCard,
                            borderRadius: FlowRadii.pillRadius,
                            border: Border.all(color: sel ? accent : FlowColors.darkBorder),
                          ),
                          child: Text(
                            '$m min',
                            style: FlowTypography.labelSmall(
                              color: sel ? accent : FlowColors.textSecondary,
                            ).copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
