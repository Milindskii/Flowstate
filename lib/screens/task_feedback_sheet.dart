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
  final int energyScore;          // 1 (drained) to 5 (energized)
  final int focusScore;           // 1 (scattered) to 5 (flow)
  final int difficultyScore;      // 1 (breeze) to 5 (intense)
  final int distractionScore;     // 1 (none) to 5 (severe)
  final String? durationFeedback; // 'shorter' | 'about_right' | 'longer'
  final String? blockerNote;      // optional free text
  final DateTime completedAt;
  final int actualMinutes;        // elapsed from in-app timer
  final bool taskFinished;        // user confirmed task is completed

  const TaskFeedbackEntry({
    required this.taskId,
    required this.feeling,
    this.energyScore = 3,
    this.focusScore = 3,
    this.difficultyScore = 3,
    this.distractionScore = 1,
    this.durationFeedback,
    this.blockerNote,
    required this.completedAt,
    required this.actualMinutes,
    this.taskFinished = false,
  });

  Map<String, dynamic> toJson() => {
    'task_id': taskId,
    'feeling': feeling,
    'energy_score': energyScore,
    'focus_score': focusScore,
    'difficulty_score': difficultyScore,
    'distraction_score': distractionScore,
    'duration_feedback': durationFeedback,
    'blocker_note': blockerNote,
    'completed_at': completedAt.toUtc().toIso8601String(),
    'actual_minutes': actualMinutes,
    'task_finished': taskFinished,
  };
}

/// Shows a small post-task feedback bottom sheet.
/// Layout: emoji row → duration row → optional blocker note.
/// Auto-closes 5 seconds after emoji tap if no further interaction.
void showTaskFeedbackSheet(
  BuildContext context, {
  required String taskId,
  required int actualMinutes,
  String? taskTitle,
  bool showTaskCompletion = false,
  void Function(TaskFeedbackEntry)? onSubmit,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: FlowColors.surface(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    isScrollControlled: true,
    builder: (ctx) => TaskFeedbackContent(
      taskId: taskId,
      actualMinutes: actualMinutes,
      taskTitle: taskTitle,
      showTaskCompletion: showTaskCompletion,
      onSubmit: onSubmit,
      onDismiss: () {
        if (Navigator.of(ctx).canPop()) {
          Navigator.of(ctx).pop();
        }
      },
      showHandle: true,
    ),
  );
}

/// Reusable feedback content widget suitable for bottom sheets or in-place modal flows.
class TaskFeedbackContent extends StatefulWidget {
  final String taskId;
  final int actualMinutes;
  final String? taskTitle;
  final bool showTaskCompletion;
  final void Function(TaskFeedbackEntry)? onSubmit;
  final VoidCallback? onDismiss;
  final bool showHandle;

  const TaskFeedbackContent({
    super.key,
    required this.taskId,
    required this.actualMinutes,
    this.taskTitle,
    this.showTaskCompletion = false,
    this.onSubmit,
    this.onDismiss,
    this.showHandle = true,
  });

  @override
  State<TaskFeedbackContent> createState() => _TaskFeedbackContentState();
}

class _TaskFeedbackContentState extends State<TaskFeedbackContent> {
  int? _feeling; // 1–4
  int _energyScore = 3;
  int _focusScore = 3;
  int _difficultyScore = 3;
  int _distractionScore = 1;
  bool _taskFinishedByUser = false;

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

      // Seed baseline scores according to feeling
      if (feeling == 1) {
        _energyScore = 1;
        _focusScore = 2;
      } else if (feeling == 2) {
        _energyScore = 2;
        _focusScore = 3;
      } else if (feeling == 3) {
        _energyScore = 4;
        _focusScore = 4;
      } else if (feeling == 4) {
        _energyScore = 5;
        _focusScore = 5;
      }
    });

    // Quick settle animation: 1.0 -> 1.10 -> 1.0 (settles in 160ms)
    Future.delayed(const Duration(milliseconds: 160), () {
      if (mounted && _animatingEmoji == feeling) {
        setState(() => _animatingEmoji = null);
      }
    });

    // Auto-close in 8 seconds if user doesn't interact further
    _autoCloseTimer = Timer(const Duration(seconds: 8), () {
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
    if (_feeling == null) {
      widget.onDismiss?.call();
      return;
    }
    FlowHaptics.success();
    final entry = TaskFeedbackEntry(
      taskId: widget.taskId,
      feeling: _feeling!,
      energyScore: _energyScore,
      focusScore: _focusScore,
      difficultyScore: _difficultyScore,
      distractionScore: _distractionScore,
      durationFeedback: _durationFeedback,
      blockerNote: _blockerCtrl.text.trim().isNotEmpty ? _blockerCtrl.text.trim() : null,
      completedAt: DateTime.now(),
      actualMinutes: widget.actualMinutes,
      taskFinished: _taskFinishedByUser,
    );
    widget.onSubmit?.call(entry);
    widget.onDismiss?.call();
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final margin = FlowSpacing.pageMargin(context);

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: margin,
          right: margin,
          top: widget.showHandle ? 16 : 4,
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
              if (widget.showHandle)
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: FlowColors.border(context),
                      borderRadius: FlowRadii.pillRadius,
                    ),
                  ),
                ),

              // Explicit Task Finished Question (if enabled)
              if (widget.showTaskCompletion) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: FlowColors.surfaceElevated(context),
                    borderRadius: FlowRadii.cardRadius,
                    border: Border.all(color: FlowColors.border(context)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.taskTitle != null ? 'Finished "${widget.taskTitle}"?' : 'Finished the task?',
                        style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                FlowHaptics.lightTap();
                                setState(() => _taskFinishedByUser = false);
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor: !_taskFinishedByUser ? FlowColors.cyan.withValues(alpha: 0.12) : null,
                                side: BorderSide(
                                  color: !_taskFinishedByUser ? FlowColors.cyan : FlowColors.border(context),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: Text(
                                'Not yet',
                                style: TextStyle(
                                  color: !_taskFinishedByUser ? FlowColors.cyan : FlowColors.textSecondaryOf(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                FlowHaptics.success();
                                setState(() => _taskFinishedByUser = true);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _taskFinishedByUser ? FlowColors.mint : FlowColors.surface(context),
                                foregroundColor: _taskFinishedByUser ? Colors.black : FlowColors.textPrimaryOf(context),
                                elevation: 0,
                                side: BorderSide(
                                  color: _taskFinishedByUser ? FlowColors.mint : FlowColors.border(context),
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text(
                                'Yes, finished',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Question
              Text(
                'How did that feel?',
                style: FlowTypography.titleMedium(
                  color: FlowColors.textPrimaryOf(context),
                ).copyWith(fontWeight: FontWeight.w700),
              ),
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
                        color: selected
                            ? accent.withValues(alpha: 0.12)
                            : FlowColors.surfaceElevated(context),
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
                          child: Text(
                            _emojis[i],
                            style: const TextStyle(
                              fontSize: 28,
                              fontFamilyFallback: [
                                'Segoe UI Emoji',
                                'Apple Color Emoji',
                                'Noto Color Emoji',
                                'sans-serif',
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),

              // Duration row (appears smoothly after emoji tap)
              if (_showDuration) ...[
                const SizedBox(height: 20),
                Text(
                  'Duration?',
                  style: FlowTypography.labelSmall(
                    color: FlowColors.textMutedOf(context),
                  ),
                ),
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
                            color: selected
                                ? accent.withValues(alpha: 0.10)
                                : FlowColors.surfaceElevated(context),
                            borderRadius: FlowRadii.cardRadius,
                            border: Border.all(
                              color: selected ? accent : FlowColors.border(context),
                            ),
                          ),
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: FlowTypography.labelSmall(
                              color: selected ? accent : FlowColors.textSecondaryOf(context),
                            ).copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 18),
                Text(
                  'Reflection Signals',
                  style: FlowTypography.labelSmall(
                    color: FlowColors.textMutedOf(context),
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                _buildScoreRow('Energy', _energyScore, (v) => setState(() => _energyScore = v), accent),
                _buildScoreRow('Focus', _focusScore, (v) => setState(() => _focusScore = v), accent),
                _buildScoreRow('Difficulty', _difficultyScore, (v) => setState(() => _difficultyScore = v), accent),
                _buildScoreRow('Distraction', _distractionScore, (v) => setState(() => _distractionScore = v), accent),
              ],

              // Optional blocker note
              if (_showBlocker) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _blockerCtrl,
                  style: FlowTypography.bodySmall(color: FlowColors.textPrimaryOf(context)),
                  decoration: InputDecoration(
                    hintText: 'Anything get in the way? (optional)',
                    hintStyle: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: FlowRadii.cardRadius,
                      borderSide: BorderSide(color: FlowColors.border(context)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: FlowRadii.cardRadius,
                      borderSide: BorderSide(color: FlowColors.border(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: FlowRadii.cardRadius,
                      borderSide: BorderSide(color: accent),
                    ),
                    fillColor: FlowColors.surfaceElevated(context),
                    filled: true,
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _submit,
                    child: Text(
                      'Done',
                      style: FlowTypography.labelMedium(color: accent).copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],

              if (!_showBlocker && _feeling != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Center(
                    child: Text(
                      'Auto-closing in 5s...',
                      style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
                    ),
                  ),
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreRow(String title, int currentVal, ValueChanged<int> onChanged, Color accent) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            children: List.generate(5, (idx) {
              final val = idx + 1;
              final isSel = currentVal == val;
              return GestureDetector(
                onTap: () {
                  FlowHaptics.selection();
                  onChanged(val);
                },
                child: Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: isSel ? accent : FlowColors.surfaceElevated(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isSel ? accent : FlowColors.border(context)),
                  ),
                  child: Center(
                    child: Text(
                      '$val',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSel ? Colors.black : FlowColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
