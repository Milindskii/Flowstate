import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import '../theme/flow_motion.dart';
import '../core/focus_navigation.dart';
import '../components/companion/companion_graphic.dart';
import 'task_feedback_sheet.dart';

/// "What Should I Do?" Central Recommendation & Decision Screen
///
/// Features:
/// 1. "DO THIS NOW" primary recommendation UX
/// 2. Multi-dimensional task attributes: Duration, Energy Demand, Importance, Category
/// 3. Transparent "Why now?" explanations
/// 4. Decoupled Focus Session: focus session != task completion
/// 5. Immediate Replanning on "Later": "Okay. I'll move it. Next good window: Tomorrow · 9:30 AM"
/// 6. Actionable Override Learning: "Choose something else" with real reasons
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

  bool _showFeedback = false;
  int _completedElapsedMinutes = 0;

  // Replanning state on "Later"
  bool _isLaterFlow = false;
  Map<String, dynamic>? _nextWindow;
  bool _isSubmittingLater = false;

  // Override / "Choose something else" state
  bool _isOverrideFlow = false;
  String _selectedReason = 'wrong_timing';

  static const List<Map<String, String>> _overrideReasons = [
    {'code': 'wrong_timing', 'label': 'Wrong timing'},
    {'code': 'too_tired', 'label': 'Too tired'},
    {'code': 'something_more_important', 'label': 'Something more important'},
    {'code': 'too_difficult', 'label': 'Too difficult'},
    {'code': 'deadline_changed', 'label': 'Deadline changed'},
    {'code': 'dont_feel_like_it', 'label': "Don't feel like it"},
  ];

  @override
  void initState() {
    super.initState();
    _currentTask = widget.task;
  }

  void _startFocusSession() {
    FlowHaptics.lightTap();
    Navigator.of(context).pop();
    openFocusRitual(context, task: _currentTask);
  }

  void _pauseFocusSession() {
    FlowHaptics.lightTap();
    _timer?.cancel();
    setState(() {
      _isSessionActive = false;
    });
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    provider.clearActiveFocusTask();

    try {
      Provider.of<FlowProvider>(context, listen: false).abandonSession();
    } catch (_) {}
  }

  void _completeSession() {
    FlowHaptics.success();
    _timer?.cancel();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final elapsedMinutes = (_elapsedSeconds / 60).ceil();

    // Critical invariant: Focus session completion != task completion
    // The task stays in_progress until the user explicitly marks it complete in feedback.
    provider.clearActiveFocusTask();

    try {
      Provider.of<FlowProvider>(context, listen: false).completeSession(
        taskCompleted: false,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _completedElapsedMinutes = elapsedMinutes > 0 ? elapsedMinutes : 1;
        _showFeedback = true;
      });
    }
  }

  Future<void> _handleLater() async {
    FlowHaptics.selection();
    final provider = Provider.of<AppStateProvider>(context, listen: false);

    setState(() {
      _isLaterFlow = true;
      _isSubmittingLater = true;
    });

    final res = await provider.recordOverride(reason: 'later');

    if (mounted) {
      setState(() {
        _isSubmittingLater = false;
        if (res != null && res['next_window'] is Map<String, dynamic>) {
          _nextWindow = res['next_window'] as Map<String, dynamic>;
        } else {
          _nextWindow = {
            'label': 'Tomorrow · 9:30 AM',
            'suggested_date': DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T')[0],
            'suggested_time': '09:30',
          };
        }
      });
    }
  }

  Future<void> _confirmMoveToNextWindow() async {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);
    final targetLabel = _nextWindow?['label'] ?? 'Tomorrow · 9:30 AM';

    final updated = _currentTask.copyWith(
      scheduledTime: _nextWindow?['suggested_time'] ?? '9:30 AM',
      deadline: targetLabel,
    );
    provider.updateTask(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved "${_currentTask.title}" to $targetLabel'),
        duration: const Duration(seconds: 2),
      ),
    );

    await provider.refreshTodayData();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickAnotherTime() async {
    FlowHaptics.lightTap();
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (date != null && mounted) {
      final time = await showTimePicker(
        context: context,
        initialTime: const TimeOfDay(hour: 9, minute: 30),
      );
      if (time != null && mounted) {
        final provider = Provider.of<AppStateProvider>(context, listen: false);
        final formattedTime = time.format(context);
        final targetLabel = '${date.month}/${date.day} · $formattedTime';
        final updated = _currentTask.copyWith(
          scheduledTime: formattedTime,
          deadline: targetLabel,
        );
        provider.updateTask(updated);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rescheduled "${_currentTask.title}" to $targetLabel'),
            duration: const Duration(seconds: 2),
          ),
        );
        await provider.refreshTodayData();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    }
  }

  void _openChooseSomethingElse() {
    FlowHaptics.selection();
    setState(() {
      _isOverrideFlow = true;
      _selectedReason = 'wrong_timing';
    });
  }

  void _switchTaskWithReason(TaskItem alternativeTask) {
    FlowHaptics.success();
    final provider = Provider.of<AppStateProvider>(context, listen: false);

    // Record override to backend for future personalization
    provider.recordOverride(
      reason: _selectedReason,
      chosenTaskId: alternativeTask.id,
    );

    setState(() {
      _currentTask = alternativeTask;
      _isOverrideFlow = false;
      _isSessionActive = false;
      _elapsedSeconds = 0;
    });
    _timer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switched to: "${alternativeTask.title}"'),
        duration: const Duration(seconds: 2),
      ),
    );
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

    final state = Provider.of<AppStateProvider>(context);

    // Fallback reasons if backend did not provide explanation strings
    final defaultReasons = [
      _currentTask.deadline.isNotEmpty ? _currentTask.deadline : 'Due soon',
      'Matches your available energy window',
      'High priority focus item for today',
    ];

    final reasons = state.recommendationReasons.isNotEmpty
        ? state.recommendationReasons
        : defaultReasons;

    // Post-focus feedback view
    if (_showFeedback) {
      return Container(
        decoration: BoxDecoration(
          color: FlowColors.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
          border: Border(
            top: BorderSide(color: FlowColors.border(context), width: 1.0),
          ),
        ),
        child: TaskFeedbackContent(
          taskId: _currentTask.id,
          taskTitle: _currentTask.title,
          showTaskCompletion: true,
          actualMinutes: _completedElapsedMinutes,
          showHandle: true,
          onSubmit: (fb) {
            state.recordTaskFeedback(
              taskId: _currentTask.id,
              actualMinutes: fb.actualMinutes,
              feeling: fb.feeling,
              durationFeedback: fb.durationFeedback,
              blockerNote: fb.blockerNote,
            );
            if (fb.taskFinished) {
              state.toggleTaskCompletion(_currentTask.id);
            }
          },
          onDismiss: () {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
        ),
      );
    }

    // "Later" Rescheduling View
    if (_isLaterFlow) {
      final nextWindowLabel = _nextWindow?['label'] ?? 'Tomorrow · 9:30 AM';
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
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: FlowSpacing.pageMargin(context),
              vertical: 24.0,
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
                const SizedBox(height: 20),

                Text(
                  "Okay. I'll move it.",
                  style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Next good window:',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: FlowRadii.cardRadius,
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.event_available_rounded, color: accent, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          nextWindowLabel,
                          style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (_isSubmittingLater)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _confirmMoveToNextWindow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: FlowColors.textInverse,
                        elevation: 0,
                        shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                      ),
                      child: Text(
                        'Move there',
                        style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Center(
                    child: TextButton(
                      onPressed: _pickAnotherTime,
                      child: Text(
                        'Pick another time',
                        style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    // "Choose Something Else" Override Picker View
    if (_isOverrideFlow) {
      final pendingAlternatives = state.tasks
          .where((t) => !t.isCompleted && t.id != _currentTask.id)
          .toList();

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
                const SizedBox(height: 16),

                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: FlowColors.textPrimaryOf(context),
                      onPressed: () => setState(() => _isOverrideFlow = false),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Choose something else',
                      style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                Text(
                  'Why this task right now?',
                  style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),

                // Reasons Chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _overrideReasons.map((r) {
                    final code = r['code']!;
                    final label = r['label']!;
                    final isSelected = _selectedReason == code;
                    return GestureDetector(
                      onTap: () {
                        FlowHaptics.selection();
                        setState(() => _selectedReason = code);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? accent.withValues(alpha: 0.15) : FlowColors.surfaceElevated(context),
                          borderRadius: FlowRadii.pillRadius,
                          border: Border.all(color: isSelected ? accent : FlowColors.border(context)),
                        ),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? accent : FlowColors.textPrimaryOf(context),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                Text(
                  'Select a task to do instead:',
                  style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),

                if (pendingAlternatives.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Text(
                        'No other pending tasks available.',
                        style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                      ),
                    ),
                  )
                else
                  ...pendingAlternatives.map((task) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: FlowColors.surfaceElevated(context),
                        borderRadius: FlowRadii.cardRadius,
                        border: Border.all(color: FlowColors.border(context)),
                      ),
                      child: ListTile(
                        onTap: () => _switchTaskWithReason(task),
                        title: Text(
                          task.title,
                          style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          '${task.durationMinutes} min · ${task.energyRequired} energy · ${task.category}',
                          style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                        ),
                        trailing: Icon(Icons.chevron_right_rounded, color: FlowColors.textMutedOf(context)),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      );
    }

    // Default "DO THIS NOW" Recommendation Card
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
              const SizedBox(height: 16),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: FlowRadii.pillRadius,
                          border: Border.all(color: accent.withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.bolt_rounded, size: 12, color: accent),
                            const SizedBox(width: 4),
                            Text(
                              'DO THIS NOW',
                              style: FlowTypography.labelSmall(color: accent).copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'What should I do?',
                        style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 22.0,
                        ),
                      ),
                    ],
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
              const SizedBox(height: 18),

              // Recommendation details with smooth transition
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

                      // Task Title (Hero)
                      Text(
                        _currentTask.title,
                        style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 22.0,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Metadata Attribute Chips Row
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChip(
                            icon: Icons.timer_outlined,
                            text: '${_currentTask.durationMinutes} min',
                            context: context,
                          ),
                          _buildChip(
                            icon: Icons.flash_on_rounded,
                            text: '${_currentTask.energyRequired} energy',
                            context: context,
                            color: accent,
                          ),
                          _buildChip(
                            icon: Icons.flag_outlined,
                            text: '${_currentTask.importanceLabel} importance',
                            context: context,
                          ),
                          _buildChip(
                            text: _currentTask.category,
                            context: context,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // "Why?" Section
                      Text(
                        'Why?',
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...reasons.take(3).map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 6.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 3.0),
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
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

              // Action Buttons
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: KeyedSubtree(
                  key: ValueKey(_isSessionActive),
                  child: !_isSessionActive
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Primary Start Button
                            FlowPressScale(
                              onTap: _startFocusSession,
                              child: SizedBox(
                                width: double.infinity,
                                height: 50,
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
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // "Not feeling this?" Section
                            Text(
                              'Not feeling this?',
                              style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // Override Actions Row: [ Choose something else ] [ Later ]
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _openChooseSomethingElse,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: BorderSide(color: FlowColors.border(context)),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: FlowRadii.buttonRadius,
                                      ),
                                    ),
                                    child: Text(
                                      'Choose something else',
                                      style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _handleLater,
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      side: BorderSide(color: FlowColors.border(context)),
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: FlowRadii.buttonRadius,
                                      ),
                                    ),
                                    child: Text(
                                      'Later',
                                      style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Running · ${_formatElapsed(_elapsedSeconds)} elapsed',
                                      style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Builder(
                                      builder: (context) {
                                        FlowProvider? flow;
                                        try {
                                          flow = Provider.of<FlowProvider>(context, listen: true);
                                        } catch (_) {}
                                        if (flow == null) return const SizedBox.shrink();
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CompanionGraphic(species: flow.companion.species, size: 14),
                                            const SizedBox(width: 5),
                                            Text(
                                              '${flow.companion.name} is focusing · +${_elapsedSeconds ~/ 60} XP',
                                              style: FlowTypography.bodySmall(color: FlowColors.mint).copyWith(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
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

  Widget _buildChip({
    IconData? icon,
    required String text,
    required BuildContext context,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: FlowColors.surfaceElevated(context),
        borderRadius: FlowRadii.pillRadius,
        border: Border.all(color: FlowColors.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color ?? FlowColors.textSecondaryOf(context)),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: FlowTypography.bodySmall(color: color ?? FlowColors.textSecondaryOf(context)).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
