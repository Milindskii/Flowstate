import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';

/// Post-task feeling feedback entry.
/// Note: feeling is 1–4 (emoji reaction). NOT a "focus score" — do not derive
/// scientific meaning from this. Use it as raw signal for future ML data collection.
class TaskFeedbackEntry {
  final String taskId;
  final int feeling;              // 1=😫 2=😐 3=🙂 4=🔥
  final String? durationFeedback; // 'shorter' | 'about_right' | 'longer'
  final String? blockerNote;      // optional free text
  final DateTime completedAt;
  final int actualMinutes;        // elapsed from in-app timer

  const TaskFeedbackEntry({
    required this.taskId,
    required this.feeling,
    this.durationFeedback,
    this.blockerNote,
    required this.completedAt,
    required this.actualMinutes,
  });

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'feeling': feeling,
    'duration_feedback': durationFeedback,
    'blocker_note': blockerNote,
    'completed_at': completedAt.toUtc().toIso8601String(),
    'actual_minutes': actualMinutes,
  };
}

/// Shows a small post-task feedback bottom sheet.
/// Layout: emoji row → duration row → optional blocker note.
/// Auto-closes 5 seconds after emoji tap if no further interaction.
void showTaskFeedbackSheet(
  BuildContext context, {
  required String taskId,
  required int actualMinutes,
  void Function(TaskFeedbackEntry)? onSubmit,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: FlowColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) => _TaskFeedbackSheet(
      taskId: taskId,
      actualMinutes: actualMinutes,
      onSubmit: onSubmit,
    ),
  );
}

class _TaskFeedbackSheet extends StatefulWidget {
  final String taskId;
  final int actualMinutes;
  final void Function(TaskFeedbackEntry)? onSubmit;

  const _TaskFeedbackSheet({
    required this.taskId,
    required this.actualMinutes,
    this.onSubmit,
  });

  @override
  State<_TaskFeedbackSheet> createState() => _TaskFeedbackSheetState();
}

class _TaskFeedbackSheetState extends State<_TaskFeedbackSheet> {
  int? _feeling; // 1–4
  int? _animatingEmoji;
  String? _durationFeedback;
  final TextEditingController _blockerCtrl = TextEditingController();
  Timer? _autoCloseTimer;
  bool _showDuration = false;
  bool _showBlocker = false;

  static const _emojis = ['😫', '😐', '🙂', '🔥'];
  static const _durationOptions = [
    ('shorter', 'Faster than expected'),
    ('about_right', 'About right'),
    ('longer', 'Too long'),
  ];

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
    _blockerCtrl.dispose();
    super.dispose();
  }

  void _onEmojiTap(int feeling) {
    FlowHaptics.selection();
    setState(() {
      _feeling = feeling;
      _animatingEmoji = feeling;
      _showDuration = true;
    });

    // Quick settle animation: 1.0 -> 1.10 -> 1.0 (settles in 160ms)
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted && _animatingEmoji == feeling) {
        setState(() => _animatingEmoji = null);
      }
    });

    // Auto-close in 5 seconds if user doesn't interact with duration row
    _autoCloseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _durationFeedback == null) {
        _submit();
      }
    });
  }

  void _onDurationTap(String code) {
    FlowHaptics.selection();
    _autoCloseTimer?.cancel();
    setState(() {
      _durationFeedback = code;
      _showBlocker = true;
    });
  }

  void _submit() {
    if (_feeling == null) { Navigator.of(context).pop(); return; }
    FlowHaptics.success();
    final entry = TaskFeedbackEntry(
      taskId: widget.taskId,
      feeling: _feeling!,
      durationFeedback: _durationFeedback,
      blockerNote: _blockerCtrl.text.trim().isNotEmpty ? _blockerCtrl.text.trim() : null,
      completedAt: DateTime.now(),
      actualMinutes: widget.actualMinutes,
    );
    widget.onSubmit?.call(entry);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try { accent = Provider.of<ThemeProvider>(context).accentColor; } catch (_) {}

    final margin = FlowSpacing.pageMargin(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: margin,
          right: margin,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
              const SizedBox(height: 20),

              // Question
              Text('How did that feel?', style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // Emoji row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(4, (i) {
                  final feeling = i + 1;
                  final selected = _feeling == feeling;
                  return GestureDetector(
                    onTap: () => _onEmojiTap(feeling),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: selected ? accent.withValues(alpha: 0.12) : FlowColors.darkCardElevated,
                        borderRadius: FlowRadii.cardRadius,
                        border: Border.all(
                          color: selected ? accent : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: AnimatedScale(
                          scale: _animatingEmoji == feeling ? 1.10 : 1.0,
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          child: Text(_emojis[i], style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // Duration row (appears smoothly after emoji tap)
              if (_showDuration) ...[
                const SizedBox(height: 20),
                Text('Duration?', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
                const SizedBox(height: 10),
                Row(
                  children: _durationOptions.map((opt) {
                    final (code, label) = opt;
                    final selected = _durationFeedback == code;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => _onDurationTap(code),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selected ? accent.withValues(alpha: 0.10) : FlowColors.darkCardElevated,
                            borderRadius: FlowRadii.cardRadius,
                            border: Border.all(color: selected ? accent : FlowColors.darkBorder),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: FlowTypography.labelSmall(
                              color: selected ? accent : FlowColors.textSecondary,
                            ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Optional blocker note
              if (_showBlocker) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _blockerCtrl,
                  style: FlowTypography.bodySmall(),
                  decoration: InputDecoration(
                    hintText: 'Anything get in the way? (optional)',
                    hintStyle: FlowTypography.bodySmall(color: FlowColors.textMuted),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: const OutlineInputBorder(borderRadius: FlowRadii.cardRadius, borderSide: BorderSide(color: FlowColors.darkBorder)),
                    enabledBorder: const OutlineInputBorder(borderRadius: FlowRadii.cardRadius, borderSide: BorderSide(color: FlowColors.darkBorder)),
                    focusedBorder: OutlineInputBorder(borderRadius: FlowRadii.cardRadius, borderSide: BorderSide(color: accent)),
                    fillColor: FlowColors.darkCardElevated,
                    filled: true,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submit,
                    child: Text('Done', style: FlowTypography.labelMedium(color: accent).copyWith(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],

              if (!_showBlocker && _feeling != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text('Auto-closing in 5s...', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
                  ),
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
