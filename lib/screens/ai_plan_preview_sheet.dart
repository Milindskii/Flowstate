import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/noya_companion_view.dart';
import '../models/ai_plan_models.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../providers/theme_provider.dart';
import '../services/plan_confirm_exception.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'parsed_plan_confirm_sheet.dart';
import '../utils/friendly_error.dart';

/// Shows the Gemini Brain Dump confirmation or compact preview sheet.
///
/// If extracted information is clear:
///   Header: "Here's what I found"
///   Compact preview with:
///   - Title
///   - Type Â· Duration
///   - Priority
///   - Deadline or Fixed time
///   [ Build my day ]
///
/// If Gemini inferred something important or is uncertain:
///   Header: "Flowstate isn't completely sure about this."
///   "Is this correct?"
///   [ Yes, build my day ]
///   [ Edit ]
void showAIPlanPreviewSheet(
  BuildContext context, {
  required AIPlanResult planResult,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AIPlanPreviewSheet(planResult: planResult),
  );
}

class _AIPlanPreviewSheet extends StatelessWidget {
  final AIPlanResult planResult;

  const _AIPlanPreviewSheet({required this.planResult});

  Future<void> _buildMyDay(BuildContext context, List<TaskItem> candidates) async {
    FlowHaptics.success();
    // Capture everything that needs BuildContext BEFORE the async gap.
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final textStyle = FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context));
    final snackBg = FlowColors.surfaceElevated(context);
    try {
      await provider.confirmCandidates(candidates);
    } on PlanConfirmException catch (e) {
      // Nothing was saved; keep the sheet open so the user can retry or edit.
      messenger.showSnackBar(SnackBar(
        content: Text(plainOr(e.message, 'This plan needs another look. Please review it and try again.'), style: textStyle),
        backgroundColor: snackBg,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    navigator.pop(); // Close sheet

    messenger.showSnackBar(SnackBar(
      content: Text(
        '${candidates.length} task${candidates.length == 1 ? '' : 's'} added to your day',
        style: textStyle,
      ),
      backgroundColor: snackBg,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _onEdit(BuildContext context, List<TaskItem> candidates) {
    FlowHaptics.selection();
    Navigator.of(context).pop(); // Close preview sheet
    showParsedPlanConfirmSheet(context, candidates: candidates);
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    final candidates = planResult.tasks.map((t) => t.toTaskItem()).toList();
    final needsConfirmation = planResult.needsConfirmation ||
        planResult.tasks.any((t) => t.needsConfirmation || t.prioritySource == 'inferred');

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
                      NoyaCompanionView(
                        state: needsConfirmation ? NoyaState.thinking : NoyaState.proud,
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
                              style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(context)).copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              needsConfirmation
                                  ? '$name wants to make sure these match your day.'
                                  : '$name structured your brain dump into tasks.',
                              style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                                height: 1.3,
                              ),
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

            // Header Section
            if (needsConfirmation) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: FlowColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.help_outline_rounded, color: FlowColors.warning, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Flowstate isn't completely sure about this.",
                      style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Is this correct?',
                style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Here's what I found",
                    style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: FlowRadii.pillRadius,
                    ),
                    child: Text(
                      '${planResult.tasks.length} task${planResult.tasks.length == 1 ? '' : 's'}',
                      style: FlowTypography.labelSmall(color: accent).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Tasks List
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: planResult.tasks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  final task = planResult.tasks[i];
                  return _buildTaskCard(context, task, accent, needsConfirmation);
                },
              ),
            ),

            const SizedBox(height: 18),

            // Pinned Action Buttons: Single Final Action [ Add & Schedule ] + Optional Secondary [ Edit ]
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('edit_button'),
                    onPressed: () => _onEdit(context, candidates),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textPrimaryOf(context),
                      side: BorderSide(color: FlowColors.border(context)),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Edit',
                      style: FlowTypography.labelLarge(color: FlowColors.textPrimaryOf(context))
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    key: const Key('add_and_schedule_button'),
                    onPressed: () => _buildMyDay(context, candidates),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Add & Schedule',
                      style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(BuildContext context, ExtractedTaskItem task, Color accent, bool showInferredHighlight) {
    final typeFormatted = _formatType(task.type);
    final isPriorityInferred = task.prioritySource == 'inferred';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: (showInferredHighlight && (task.needsConfirmation || isPriorityInferred))
              ? FlowColors.warning.withValues(alpha: 0.6)
              : FlowColors.border(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: FlowTypography.bodyLarge().copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (task.fixedStart != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: FlowColors.accentCyan.withValues(alpha: 0.14),
                    borderRadius: FlowRadii.pillRadius,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule_rounded, size: 12, color: FlowColors.accentCyan),
                      const SizedBox(width: 4),
                      Text(
                        // Now renders "Friday Â· 5:00 PM" when targetDate is set,
                        // and falls back to "5:00 PM" when it is not.
                        _formatFixedSchedule(task),
                        style: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context))
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$typeFormatted Â· ${task.isDurationExplicit ? '${task.estimatedMinutes} min' : 'Estimated ${task.estimatedMinutes} min'}',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
              ),
              Text('â€¢', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
              Text(
                task.priority == null
                    ? ''
                    : isPriorityInferred
                        ? 'Suggested: ${_capitalize(task.priority!)}'
                        : '${_capitalize(task.priority!)} priority',
                style: FlowTypography.bodySmall(
                  color: isPriorityInferred
                      ? FlowColors.warning
                      : (task.isPriorityUnspecified ? FlowColors.textMutedOf(context) : FlowColors.textSecondaryOf(context)),
                ).copyWith(fontWeight: isPriorityInferred ? FontWeight.w600 : FontWeight.normal),
              ),
              if (task.deadline != null && task.deadline!.isNotEmpty) ...[
                Text('â€¢', style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context))),
                Text(
                  'Due ${_capitalize(task.deadline!)}',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ],
          ),

          // Scheduler-suggested slot (only shown when the scheduler actually
          // produced a recommendation). Previously this row also rendered the
          // user's own fixed_start time under the label "Recommended:".
          if (task.recommendedSlotDisplay != null) ...[
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                Text(
                  'Scheduler suggests: ',
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  task.recommendedSlotDisplay!,
                  style: FlowTypography.bodySmall(color: FlowColors.accentMint).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],

          if (task.schedulingExplanation != null && task.schedulingExplanation!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: FlowColors.surface(context),
                borderRadius: FlowRadii.cardRadius,
                border: Border.all(color: FlowColors.border(context).withValues(alpha: 0.6)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Why: ',
                    style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      task.schedulingExplanation!,
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatType(String type) {
    switch (type.toLowerCase()) {
      case 'deep_work':
        return 'Deep Work';
      case 'study':
        return 'Study';
      case 'physical':
      case 'fitness':
        return 'Physical';
      case 'admin':
        return 'Admin';
      default:
        return _capitalize(type);
    }
  }

  /// Composes a human-readable fixed slot from `targetDate` + `fixedStart`.
  ///
  /// - `targetDate == null`           â†’ "5:00 PM"          (today implied)
  /// - `targetDate == today (ISO)`    â†’ "Today Â· 5:00 PM"
  /// - `targetDate == tomorrow (ISO)` â†’ "Tomorrow Â· 5:00 PM"
  /// - `targetDate == Fri (this week)`â†’ "Fri Â· 5:00 PM"
  /// - `targetDate == further out`    â†’ "Oct 2 Â· 5:00 PM"
  String _formatFixedSchedule(ExtractedTaskItem task) {
    final time = _formatFixedStart(task.fixedStart!);
    final day = _formatTargetDay(task.targetDate);
    return day == null ? time : '$day Â· $time';
  }

  /// Renders the target day as a short user-facing label. Returns null when
  /// there is no usable target date, so callers can fall back gracefully.
  String? _formatTargetDay(String? targetDate) {
    if (targetDate == null || targetDate.isEmpty) return null;
    final parsed = DateTime.tryParse(targetDate);
    if (parsed == null) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(parsed.year, parsed.month, parsed.day);
    final diff = target.difference(today).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff > 1 && diff < 7) {
      const weekday = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekday[target.weekday - 1];
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[target.month - 1]} ${target.day}';
  }

  String _formatFixedStart(String time) {
    if (!time.contains(':')) return time;
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hour = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final minStr = m.toString().padLeft(2, '0');
    return '$hour:$minStr $ampm';
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}