import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import '../theme/flow_motion.dart';
import 'task_feedback_sheet.dart';

/// Ultralight "What Now?" Decision Sheet / Screen
///
/// Header: What should I do?
/// Then:
/// I'd do this:
/// Finish ML Assignment
/// 90 min
/// Why?
/// • Due tomorrow
/// • Strong focus window
/// • Fits your available time
/// [ Start ]
/// Secondary: Give me something easier →
class WhatShouldIDoScreen extends StatefulWidget {
  final TaskItem task;

  const WhatShouldIDoScreen({
    super.key,
    required this.task,
  });

  @override
  State<WhatShouldIDoScreen> createState() => _WhatShouldIDoScreenState();
}

class _WhatShouldIDoScreenState extends State<WhatShouldIDoScreen> {
  late TaskItem _currentTask;
  bool _isSessionActive = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
  }

  void _startFocusSession() {
    FlowHaptics.lightTap();
    setState(() {
      _isSessionActive = true;
      _elapsedSeconds = 0;
    });

    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.setActiveFocusTask(_currentTask);

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _pauseFocusSession() {
    FlowHaptics.lightTap();
    _timer?.cancel();
    setState(() {
      _isSessionActive = false;
    });
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.clearActiveFocusTask();
  }

  void _completeSession() {
    FlowHaptics.success();
    _timer?.cancel();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final completedTask = _currentTask;
    final elapsedMinutes = (_elapsedSeconds / 60).ceil();
    provider.toggleTaskCompletion(completedTask.id);
    provider.clearActiveFocusTask();

    if (mounted) {
      Navigator.pop(context);
      showTaskFeedbackSheet(
        context,
        taskId: completedTask.id,
        actualMinutes: elapsedMinutes > 0 ? elapsedMinutes : 1,
        onSubmit: (fb) {
          provider.recordTaskFeedback(
            taskId: completedTask.id,
            actualMinutes: fb.actualMinutes,
            feeling: fb.feeling,
            durationFeedback: fb.durationFeedback,
            blockerNote: fb.blockerNote,
          );
        },
      );
    }
  }

  void _takeABreak() {
    FlowHaptics.lightTap();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    _timer?.cancel();
    provider.startBreakSession(minutes: 15);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Starting 15-minute recharge break.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _requestEasierTask() {
    FlowHaptics.selection();
    final state = Provider.of<AppStateProvider>(context, listen: false);
    final alternative = state.getEasierAlternativeTask(_currentTask);

    if (alternative != null) {
      setState(() {
        _currentTask = alternative;
        _isSessionActive = false;
        _elapsedSeconds = 0;
      });
      _timer?.cancel();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to: "${alternative.title}"'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is already your lowest-load pending task.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatElapsed(int totalSeconds) {
    final mins = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).resolveAccent(context);
    } catch (_) {}

    final defaultReasons = [
      'Due tomorrow',
      'Strong focus window',
      'Fits your available time',
    ];

    final state = Provider.of<AppStateProvider>(context);
    final reasons = state.recommendationReasons.isNotEmpty
        ? state.recommendationReasons
        : defaultReasons;

    return Container(
      decoration: BoxDecoration(
        color: FlowColors.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
        border: Border(
          top: BorderSide(color: FlowColors.border(context), width: 1.0),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: FlowSpacing.pageMargin(context),
            vertical: 20.0,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
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
              const SizedBox(height: 18),

              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'What should I do?',
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22.0,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      FlowHaptics.lightTap();
                      Navigator.pop(context);
                    },
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: FlowColors.surfaceElevated(context),
                        shape: BoxShape.circle,
                        border: Border.all(color: FlowColors.border(context), width: 1.0),
                      ),
                      child: Icon(Icons.close_rounded, size: 18, color: FlowColors.textSecondaryOf(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Recommendation details with smooth keyed recalculation animation
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_currentTask.id),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "I'd do this:" label
                      Row(
                        children: [
                          Text('✦', style: TextStyle(color: accent, fontSize: 13)),
                          const SizedBox(width: 6),
                          Text(
                            "I'd do this:",
                            style: FlowTypography.labelMedium(color: accent).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Task Title (Prominent Hero)
                      Text(
                        _currentTask.title,
                        style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 20.0,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Duration
                      Text(
                        '${_currentTask.durationMinutes} min',
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // "Why?" + 3 concise bullets
                      Text(
                        'Why?',
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...reasons.take(3).map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 2.0),
                                child: Text('•', style: TextStyle(color: FlowColors.textSecondaryOf(context), fontSize: 14)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r,
                                  style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons with inline state transition
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_isSessionActive),
                  child: !_isSessionActive
                      ? Column(
                          children: [
                            // Primary Start Button
                            FlowPressScale(
                              onTap: _startFocusSession,
                              child: SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _startFocusSession,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accent,
                                    foregroundColor: FlowColors.textInverse,
                                    elevation: 0,
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: FlowRadii.buttonRadius,
                                    ),
                                  ),
                                  child: Text(
                                    'Start',
                                    style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Secondary: Give me something easier →
                            Center(
                              child: GestureDetector(
                                onTap: _requestEasierTask,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Text(
                                    'Give me something easier →',
                                    style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Tertiary: Take a break (15 min)
                            Center(
                              child: GestureDetector(
                                onTap: _takeABreak,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  child: Text(
                                    'Take a break (15 min)',
                                    style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: FlowColors.surfaceElevated(context),
                            borderRadius: FlowRadii.buttonRadius,
                            border: Border.all(color: accent.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: FlowColors.successOf(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Running · ${_formatElapsed(_elapsedSeconds)} elapsed',
                                  style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _pauseFocusSession,
                                child: Text('Pause', style: TextStyle(color: FlowColors.textSecondaryOf(context), fontSize: 13)),
                              ),
                              ElevatedButton(
                                onPressed: _completeSession,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: FlowColors.successOf(context),
                                  foregroundColor: FlowColors.textInverse,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: const RoundedRectangleBorder(borderRadius: FlowRadii.pillRadius),
                                ),
                                child: const Text('Done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
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
}
