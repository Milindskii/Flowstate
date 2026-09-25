import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ai_plan_models.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'parsed_plan_confirm_sheet.dart';

/// Shows the Gemini Brain Dump confirmation or compact preview sheet.
///
/// If extracted information is clear:
///   Header: "Here's what I found"
///   Compact preview with:
///   - Title
///   - Type · Duration
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
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _AIPlanPreviewSheet(planResult: planResult),
  );
}

class _AIPlanPreviewSheet extends StatelessWidget {
  final AIPlanResult planResult;

  const _AIPlanPreviewSheet({required this.planResult});

  void _buildMyDay(BuildContext context, List<TaskItem> candidates) {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.confirmCandidates(candidates);
    Navigator.of(context).pop(); // Close sheet

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        '${candidates.length} task${candidates.length == 1 ? '' : 's'} added to your day',
        style: FlowTypography.bodySmall(color: FlowColors.textPrimary),
      ),
      backgroundColor: FlowColors.darkCardElevated,
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
                decoration: const BoxDecoration(
                  color: FlowColors.darkBorder,
                  borderRadius: FlowRadii.pillRadius,
                ),
              ),
            ),
            const SizedBox(height: 18),

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
                style: FlowTypography.bodySmall(color: FlowColors.textMuted),
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
                  return _buildTaskCard(task, accent, needsConfirmation);
                },
              ),
            ),

            const SizedBox(height: 18),

            // Action Buttons
            if (needsConfirmation) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('edit_button'),
                      onPressed: () => _onEdit(context, candidates),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FlowColors.textPrimary,
                        side: const BorderSide(color: FlowColors.darkBorder),
                        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Edit',
                        style: FlowTypography.labelLarge(color: FlowColors.textPrimary)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      key: const Key('yes_build_day_button'),
                      onPressed: () => _buildMyDay(context, candidates),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        'Yes, build my day',
                        style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  key: const Key('build_my_day_button'),
                  onPressed: () => _buildMyDay(context, candidates),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                  ),
                  child: Text(
                    'Build my day',
                    style: FlowTypography.labelLarge(color: FlowColors.textInverse)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(ExtractedTaskItem task, Color accent, bool showInferredHighlight) {
    final typeFormatted = _formatType(task.type);
    final isPriorityInferred = task.prioritySource == 'inferred';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardRadius,
        border: Border.all(
          color: (showInferredHighlight && (task.needsConfirmation || isPriorityInferred))
              ? FlowColors.warning.withValues(alpha: 0.6)
              : FlowColors.darkBorder,
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
                        _formatFixedStart(task.fixedStart!),
                        style: FlowTypography.labelSmall(color: FlowColors.textPrimary)
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
                '$typeFormatted · ${task.estimatedMinutes} min',
                style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
              ),
              Text('•', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
              Text(
                '${_capitalize(task.priority)} priority${isPriorityInferred ? ' (Inferred)' : ''}',
                style: FlowTypography.bodySmall(
                  color: isPriorityInferred ? FlowColors.warning : FlowColors.textSecondary,
                ).copyWith(fontWeight: isPriorityInferred ? FontWeight.w600 : FontWeight.normal),
              ),
              if (task.deadline != null && task.deadline!.isNotEmpty) ...[
                Text('•', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
                Text(
                  'Due ${_capitalize(task.deadline!)}',
                  style: FlowTypography.bodySmall(color: FlowColors.textSecondary),
                ),
              ],
            ],
          ),
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
