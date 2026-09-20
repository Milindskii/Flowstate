import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';

/// Bottom sheet that shows parsed tasks for user review + confirmation.
/// User can remove tasks or adjust duration, then tap Confirm to add them.
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
  void initState() { super.initState(); _tasks = List.from(widget.candidates); }

  void _confirm() {
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.confirmCandidates(_tasks);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_tasks.length} tasks added', style: FlowTypography.bodySmall(color: FlowColors.textPrimary)),
      backgroundColor: FlowColors.darkCardElevated,
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try { accent = Provider.of<ThemeProvider>(context).accentColor; } catch (_) {}

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 36, height: 4,
              decoration: const BoxDecoration(color: FlowColors.darkBorder, borderRadius: FlowRadii.pillRadius),
            )),
            const SizedBox(height: 20),
            Text('Parsed plan', style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Tap to edit. Remove what you don\'t need.', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
            const SizedBox(height: 16),

            // Task list
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _tasks.length,
                itemBuilder: (ctx, i) => _buildRow(i, accent),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton(
                onPressed: _tasks.isEmpty ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _tasks.isEmpty ? FlowColors.darkBorder : accent,
                  foregroundColor: FlowColors.textInverse,
                  elevation: 0,
                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                ),
                child: Text('Add ${_tasks.length} task${_tasks.length == 1 ? '' : 's'}',
                  style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(int i, Color accent) {
    final task = _tasks[i];
    final editing = _editingIndex == i;
    return GestureDetector(
      onTap: () => setState(() => _editingIndex = editing ? null : i),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: FlowColors.darkCard,
          borderRadius: FlowRadii.cardRadius,
          border: Border.all(color: editing ? accent : FlowColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(task.title, style: FlowTypography.bodyMedium().copyWith(fontWeight: FontWeight.w600))),
                Text('${task.durationMinutes}m', style: FlowTypography.bodySmall(color: FlowColors.textMuted)),
                const SizedBox(width: 6),
                Icon(editing ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 16, color: FlowColors.textMuted),
              ],
            ),
            if (editing) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 6, children: [30, 45, 60, 90, 120].map((m) {
                final sel = task.durationMinutes == m;
                return GestureDetector(
                  onTap: () {
                    final u = List<TaskItem>.from(_tasks)..[i] = task.copyWith(durationMinutes: m);
                    setState(() { _tasks = u; _editingIndex = null; });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: sel ? accent.withValues(alpha: 0.12) : FlowColors.darkCardElevated,
                      borderRadius: FlowRadii.pillRadius,
                      border: Border.all(color: sel ? accent : FlowColors.darkBorder),
                    ),
                    child: Text('$m min', style: FlowTypography.labelSmall(color: sel ? accent : FlowColors.textSecondary).copyWith(fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ),
                );
              }).toList()),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () { final u = List<TaskItem>.from(_tasks)..removeAt(i); setState(() { _tasks = u; _editingIndex = null; }); },
                child: Text('Remove', style: FlowTypography.labelSmall(color: FlowColors.critical).copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
