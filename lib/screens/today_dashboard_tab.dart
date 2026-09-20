import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/break_session_card.dart';
import '../components/compact_readiness_card.dart';
import '../components/right_now_task_card.dart';
import '../components/timeline_current_time_marker.dart';
import '../components/timeline_item_widget.dart';
import '../components/framer_motion_wrapper.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'add_task_sheet.dart';
import 'task_feedback_sheet.dart';
import 'what_should_i_do_screen.dart';

/// FLOWSTATE — TODAY ACTION SCREEN
///
/// Principles:
/// OPEN → UNDERSTAND → ACT
/// Target 5-Level Visual Hierarchy:
/// 1. Header (Good morning, [Name] 👋 + Date)
/// 2. Small readiness/context line (✦ Ready for a good session / Learning your rhythm)
/// 3. ONE primary task (HERO: DO THIS NOW)
/// 4. Minimal upcoming timeline (TIME  TITLE  DURATION + Current-time marker)
/// 5. Small What Now action docked at bottom-right
class TodayDashboardTab extends StatefulWidget {
  const TodayDashboardTab({super.key});

  @override
  State<TodayDashboardTab> createState() => _TodayDashboardTabState();
}

class _TodayDashboardTabState extends State<TodayDashboardTab> {
  bool _showFullDay = false;
  Timer? _taskTimer;
  int _elapsedSeconds = 0;

  String _formatTodayDate() {
    final now = DateTime.now();
    return DateFormat('EEEE, MMMM d').format(now);
  }

  void _startTaskTimer() {
    _taskTimer?.cancel();
    setState(() {
      _elapsedSeconds = 0;
    });
    _taskTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _elapsedSeconds++;
        });
      }
    });
  }

  void _pauseTaskTimer() {
    _taskTimer?.cancel();
    if (mounted) {
      setState(() {});
    }
  }

  void _stopTaskTimer() {
    _taskTimer?.cancel();
    if (mounted) {
      setState(() {
        _elapsedSeconds = 0;
      });
    }
  }

  @override
  void dispose() {
    _taskTimer?.cancel();
    super.dispose();
  }

  void _openAddTaskSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.darkCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (_) => const AddTaskSheet(),
    );
  }

  void _navigateToWhatNow(BuildContext context, TaskItem task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => WhatShouldIDoScreen(task: task),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context).accentColor;
    } catch (_) {}

    // 1. Loading State: "Building your day..."
    if (state.isLoading) {
      return Scaffold(
        backgroundColor: FlowColors.darkBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Building your day...',
                style: FlowTypography.bodyLarge(color: FlowColors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Error State: "We couldn’t update your plan."
    if (state.errorMessage != null && state.tasks.isEmpty) {
      return Scaffold(
        backgroundColor: FlowColors.darkBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, color: FlowColors.textMuted, size: 48),
                const SizedBox(height: 16),
                Text(
                  'We couldn’t update your plan.',
                  style: FlowTypography.titleMedium().copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Check your connection or try again.',
                  style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () => state.refreshTodayData(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final recommended = state.recommendedTask;
    final bool isCurrentRunning =
        recommended != null && state.activeFocusTask?.id == recommended.id;

    return Scaffold(
      backgroundColor: FlowColors.background(context),
      // 5. Small "✦ What now?" escape hatch docked at bottom-right
      floatingActionButton: recommended != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 4.0, right: 2.0),
              child: FramerMotionPressScale(
                onTap: () {
                  FlowHaptics.selection();
                  _navigateToWhatNow(context, recommended);
                },
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: FlowColors.surface(context),
                    borderRadius: FlowRadii.pillRadius,
                    border: Border.all(color: FlowColors.border(context), width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: FlowColors.softShadow(context),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: FlowRadii.pillRadius,
                      onTap: () {
                        FlowHaptics.selection();
                        _navigateToWhatNow(context, recommended);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '✦',
                              style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'What now?',
                              style: FlowTypography.labelSmall(color: FlowColors.textSecondary).copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: FlowSpacing.pageMargin(context),
            vertical: 18.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header: Staggered entrance
              FramerMotionFadeSlide(
                delay: Duration.zero,
                translateY: 8,
                child: _buildHeader(context, state, accent),
              ),
              const SizedBox(height: 22),

              // 2. Lifecycle Switch: New User vs Populated Day
              if (state.isNewUser) ...[
                FramerMotionFadeSlide(
                  delay: const Duration(milliseconds: 60),
                  translateY: 10,
                  child: _buildNewUserEmptyState(context, state, accent),
                ),
              ] else ...[
                // 2. Small readiness/context line (non-dominant)
                FramerMotionFadeSlide(
                  delay: const Duration(milliseconds: 60),
                  translateY: 10,
                  child: CompactReadinessCard(
                    readiness: state.readiness,
                  ),
                ),
                const SizedBox(height: 24),

                // 3. ONE Primary Task (The HERO: DO THIS NOW) or Active Break Session
                if (state.isBreakActive) ...[
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 120),
                    translateY: 12,
                    child: BreakSessionCard(
                      nextTask: recommended,
                      onFinish: () {
                        setState(() {});
                      },
                    ),
                  ),
                  const SizedBox(height: 28),
                ] else if (recommended != null) ...[
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 120),
                    translateY: 12,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(recommended.id),
                        child: RightNowTaskCard(
                          task: recommended,
                          reasons: state.todayData?.recommendation?.reasons,
                          isRunning: isCurrentRunning,
                          elapsedSeconds: _elapsedSeconds,
                          onStart: () {
                            state.setActiveFocusTask(recommended);
                            _startTaskTimer();
                          },
                          onPause: () {
                            state.clearActiveFocusTask();
                            _pauseTaskTimer();
                          },
                          onComplete: () {
                            _stopTaskTimer();
                            final completedTask = recommended;
                            final elapsedMins = (_elapsedSeconds / 60).ceil();
                            state.toggleTaskCompletion(completedTask.id);
                            state.clearActiveFocusTask();
                            showTaskFeedbackSheet(
                              context,
                              taskId: completedTask.id,
                              actualMinutes: elapsedMins > 0 ? elapsedMins : 1,
                              onSubmit: (feedback) {
                                state.recordTaskFeedback(
                                  taskId: completedTask.id,
                                  actualMinutes: feedback.actualMinutes,
                                  feeling: feedback.feeling,
                                  durationFeedback: feedback.durationFeedback,
                                  blockerNote: feedback.blockerNote,
                                );
                              },
                            );
                          },
                          onReschedule: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Rescheduling to next available block...'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                            state.optimizeSchedule();
                          },
                          onTakeBreak: () => state.startBreakSession(minutes: 15),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                ],

                // 4. Minimal Upcoming Timeline
                FramerMotionFadeSlide(
                  delay: const Duration(milliseconds: 180),
                  translateY: 10,
                  child: _buildTimelineSection(context, state, accent, recommended),
                ),
              ],

              // Clearance so content never overlaps with floating What Now pill or nav bar
              const SizedBox(height: 72),
            ],
          ),
        ),
      ),
    );
  }

  /// 1. Top Bar: Clean editorial header
  /// Good morning, [Name] 👋 / Thursday, September 18 / Subtle avatar
  Widget _buildHeader(BuildContext context, AppStateProvider state, Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.formattedGreeting,
                style: FlowTypography.headlineMedium().copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 23.0,
                  letterSpacing: -0.3,
                  color: FlowColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _formatTodayDate(),
                    style: FlowTypography.bodyMedium(color: FlowColors.textSecondary).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (state.isOffline && state.lastUpdatedAt != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('•', style: FlowTypography.labelSmall(color: FlowColors.textMuted)),
                    ),
                    InkWell(
                      onTap: () => state.refreshTodayData(),
                      child: Text(
                        'Last updated ${DateFormat('h:mm a').format(state.lastUpdatedAt!)} · Offline',
                        style: FlowTypography.labelSmall(color: FlowColors.warning),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        // Small, subtle avatar
        GestureDetector(
          onTap: () => state.setNavIndex(4), // Navigate to Profile
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: FlowColors.darkCardElevated,
              shape: BoxShape.circle,
              border: Border.all(color: FlowColors.darkBorder, width: 1.0),
            ),
            child: Center(
              child: Text(
                state.greetingName.isNotEmpty ? state.greetingName[0].toUpperCase() : 'U',
                style: FlowTypography.labelSmall(color: FlowColors.textSecondary).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNewUserEmptyState(BuildContext context, AppStateProvider state, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "What's on your plate?",
          style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Tell Flowstate what you need to do and we'll shape your day.",
          style: FlowTypography.bodyLarge(color: FlowColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 24),

        // [ Build my day ]
        FramerMotionPressScale(
          onTap: () {
            FlowHaptics.lightTap();
            _openAddTaskSheet(context);
          },
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () {
                FlowHaptics.lightTap();
                _openAddTaskSheet(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: FlowColors.textInverse,
                elevation: 0,
                shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
              ),
              child: Text(
                'Build my day',
                style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // [ Tell Flowstate what I need to do ]
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: () {
              FlowHaptics.lightTap();
              _openAddTaskSheet(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: FlowColors.textPrimaryOf(context),
              side: BorderSide(color: FlowColors.border(context), width: 1.0),
              shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
            ),
            child: Text(
              'Tell Flowstate what I need to do',
              style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Tiny visual example: "Add 3 tasks. We'll help organize them."
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: FlowColors.surface(context),
            borderRadius: FlowRadii.inputRadius,
            border: Border.all(color: FlowColors.border(context), width: 1.0),
          ),
          child: Row(
            children: [
              Text('✦', style: TextStyle(color: accent, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add 3 tasks. We’ll help organize them.',
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 4. Minimal Upcoming Timeline
  /// Time + subtle vertical line + Title + Duration
  /// Shows next 3-4 items, omitting the primary hero task to avoid repetition.
  Widget _buildTimelineSection(
    BuildContext context,
    AppStateProvider state,
    Color accent,
    TaskItem? recommended,
  ) {
    if (state.schedule.isEmpty) return const SizedBox.shrink();

    // Filter out the primary task so it is not repeated immediately
    final filteredSchedule = state.schedule.where((item) {
      if (recommended == null) return true;
      return item.id != recommended.id &&
          item.title.toLowerCase() != recommended.title.toLowerCase();
    }).toList();

    if (filteredSchedule.isEmpty) return const SizedBox.shrink();

    // Show only the next 3-4 relevant events unless expanded
    final displayItems = _showFullDay
        ? filteredSchedule
        : filteredSchedule.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: TODAY + View full day →
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TODAY',
              style: FlowTypography.badgeText(color: FlowColors.textSecondary).copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                fontSize: 11,
              ),
            ),
            if (filteredSchedule.length > 4)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showFullDay = !_showFullDay;
                  });
                },
                child: Text(
                  _showFullDay ? 'Show less ↑' : 'View full day →',
                  style: FlowTypography.labelSmall(color: accent).copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Subtle Current-Time Marker
        const TimelineCurrentTimeMarker(),
        const SizedBox(height: 6),

        // Minimal Upcoming Timeline Items
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayItems.length,
          itemBuilder: (context, index) {
            final item = displayItems[index];
            final isLast = index == displayItems.length - 1;

            return FramerMotionFadeSlide(
              delay: Duration(milliseconds: 200 + (index * 40)),
              translateY: 8,
              child: TimelineItemWidget(
                item: item,
                isLast: isLast,
              ),
            );
          },
        ),
      ],
    );
  }
}
