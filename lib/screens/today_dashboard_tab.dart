import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/noya_motion_view.dart';
import '../components/shield_popups.dart';
import '../components/shield_welcome_card.dart';
import '../components/today_so_far.dart';
import '../components/break_session_card.dart';
import '../components/noya_companion_view.dart';
import '../components/compact_readiness_card.dart';
import '../components/right_now_task_card.dart';
import '../components/timeline_current_time_marker.dart';
import '../components/timeline_item_widget.dart';
import '../components/framer_motion_wrapper.dart';
import '../models/task_item.dart';
import '../models/schedule_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_haptics.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_spacing.dart';
import '../theme/flow_typography.dart';
import 'add_task_sheet.dart';
import 'brain_dump_sheet.dart';
import 'task_feedback_sheet.dart';
import 'what_should_i_do_screen.dart';
import 'flow_screen.dart';
import '../components/skeleton_loaders.dart';
import '../components/edit_task_sheet.dart';
import '../components/reschedule_task_sheet.dart';
import '../core/focus_navigation.dart';
import '../models/today_model.dart';

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
  final GlobalKey<ShieldWelcomeCardState> _welcomeKey = GlobalKey<ShieldWelcomeCardState>();
  bool _showFullDay = false;
  FlowProvider? _flow;
  bool _streakPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        final flowProvider = Provider.of<FlowProvider>(context, listen: false);
        appState.onTaskCompletedForFlow = flowProvider.recordTaskCompletionLocally;
        appState.onFlowNeedsRefresh = flowProvider.loadOverview;
        _flow = flowProvider..addListener(_maybePromptStreakRestore);
        // The Shield pill and the streak restore offer read the server's overview: fetch it once when signed in.
        if (appState.isAuthenticated && !flowProvider.hasServerShieldBalance) flowProvider.loadOverview();
        _maybePromptStreakRestore();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _flow?.removeListener(_maybePromptStreakRestore);
    super.dispose();
  }

  /// When the server reports a restorable streak, Noya offers the restore once (per day and streak).
  void _maybePromptStreakRestore() {
    final flow = _flow;
    if (_streakPromptShown || flow == null || !mounted || !flow.streakRecovery.eligible) return;
    if (ModalRoute.of(context)?.isCurrent != true) return; // never on top of another sheet or dialog
    _streakPromptShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) StreakRestorePopup.maybeShow(context);
    });
  }

  void _openAddTaskSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FlowColors.surface(context),
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

    // 1. Loading State: Shimmer Skeleton
    if (state.isLoading) {
      return const TodayDashboardSkeleton();
    }

    final recommended = state.recommendedTask;
    final bool isCurrentRunning =
        recommended != null && state.activeFocusTask?.id == recommended.id;
    // TODAY's tasks only: a new day with nothing planned yet is an empty day, even when yesterday was all done.
    final bool hasAnyTasks = !state.todayCompletion.isEmptyDay ||
        (state.todaySnapshot != null &&
            (state.todaySnapshot!.upcomingTimeline.isNotEmpty ||
                state.todaySnapshot!.currentRecommendation != null));

    return Scaffold(
      backgroundColor: Colors.transparent,
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
                            Icon(Icons.auto_awesome_rounded, color: accent, size: 14),
                            const SizedBox(width: 6),
                            Text(
                              'What now?',
                              style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
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
        child: RefreshIndicator(
          onRefresh: () => state.refreshTodayData(),
          color: accent,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  child: _buildHeader(context, state, accent, hasAnyTasks),
                ),
                const SizedBox(height: 22),

                // 2. Lifecycle Switch: New User / Empty State vs Completed vs Active Day with Tasks
                if (!hasAnyTasks) ...[
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 60),
                    translateY: 10,
                    child: _buildNewUserEmptyState(context, state, accent),
                  ),
                ] else if (state.todayState == TodayState.completed) ...[
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 60),
                    translateY: 10,
                    child: _buildDayCompletedState(context, state, accent),
                  ),
                ] else ...[
                  // 2. Small readiness/context line (non-dominant): YOUR RHYTHM
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 60),
                    translateY: 10,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR RHYTHM',
                          style: FlowTypography.badgeText(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        CompactReadinessCard(
                          readiness: state.readiness,
                        ),
                      ],
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
                    // Case A: User completed at least 1 task, and pending tasks remain
                    // Case A: finished moments so far, as calm history above what's next.
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: TodaySoFar(),
                    ),
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
                            elapsedSeconds: 0,
                            onStart: () {
                              FlowHaptics.lightTap();
                              openFocusRitual(context, task: recommended);
                            },
                            onFocusRitual: () {
                              FlowHaptics.lightTap();
                              openFocusRitual(context, task: recommended);
                            },
                            onPause: () {
                              state.clearActiveFocusTask();
                              try {
                                Provider.of<FlowProvider>(context, listen: false).abandonSession();
                              } catch (_) {}
                            },
                            onComplete: () {
                              final completedTask = recommended;
                              state.toggleTaskCompletion(completedTask.id);
                              state.clearActiveFocusTask();

                              try {
                                Provider.of<FlowProvider>(context, listen: false).completeSession(
                                  taskCompleted: true,
                                );
                              } catch (_) {}

                              showTaskFeedbackSheet(
                                context,
                                taskId: completedTask.id,
                                actualMinutes: 25,
                                onSubmit: (feedback) {
                                  state.recordTaskFeedback(
                                    taskId: completedTask.id,
                                    actualMinutes: feedback.actualMinutes,
                                    feeling: feedback.feeling,
                                    durationFeedback: feedback.durationFeedback,
                                    blockerNote: feedback.blockerNote,
                                    energyScore: feedback.energyScore,
                                    focusScore: feedback.focusScore,
                                    difficultyScore: feedback.difficultyScore,
                                    distractionScore: feedback.distractionScore,
                                    completedAt: feedback.completedAt,
                                  );
                                },
                              );
                            },
                            onReschedule: () {
                              _showLaterSheet(context, recommended, state, accent);
                            },
                            onTakeBreak: () => state.startBreakSession(minutes: 15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // 4. YOUR FLOW: Compact flow card on active today
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 150),
                    translateY: 10,
                    child: _buildTodayFlowCard(context, state, accent),
                  ),
                  const SizedBox(height: 28),

                  // 5. Minimal Upcoming Timeline: UP NEXT
                  FramerMotionFadeSlide(
                    delay: const Duration(milliseconds: 180),
                    translateY: 10,
                    child: _buildTimelineSection(context, state, accent, recommended),
                  ),
                ],

              // Tomorrow: its own section, only when tomorrow has open tasks. Never part of today's timeline.
              _buildTomorrowSection(context, state),

              // Clearance so content never overlaps with floating What Now pill or nav bar
              const SizedBox(height: 72),
            ],
          ),
        ),
      ),
    ),
  );
  }

  /// 1. Top Bar: Clean editorial header
  String _getHeaderSubtitle(AppStateProvider state, bool hasAnyTasks) {
    if (!hasAnyTasks || state.todayState == TodayState.newUser) {
      return "Let's build your first plan.";
    }
    final now = DateTime.now();
    final currentHour = now.hour + (now.minute / 60.0);
    final bedtimeHour = state.personalData.bedtimeHour;
    final isAtOrPastBedtime = bedtimeHour >= 18.0
        ? (currentHour >= bedtimeHour || currentHour < 5.0)
        : (bedtimeHour < 6.0
            ? (currentHour >= bedtimeHour && currentHour < 6.0)
            : (currentHour >= bedtimeHour));
    final isDayActuallyFinished = isAtOrPastBedtime;

    switch (state.todayState) {
      case TodayState.newUser:
        return "Let's build your first plan.";
      case TodayState.learning:
        return "What are we getting done today?";
      case TodayState.calibrated:
        return "Ready for a good session?";
      case TodayState.completed:
        return isDayActuallyFinished
            ? "Nice work today. Time to wind down."
            : "All scheduled tasks completed for today";
    }
  }

  Widget _buildHeader(BuildContext context, AppStateProvider state, Color accent, bool hasAnyTasks) {
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
                  color: FlowColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _getHeaderSubtitle(state, hasAnyTasks),
                    style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (state.isOffline && state.lastUpdatedAt != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('•', style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context))),
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
        // Header actions: Noya's companion pill and the server's Shield balance. Profile lives in the bottom
        // navigation, so no second avatar here.
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildFlowHeaderPill(context),
            const SizedBox(height: 6),
            const ShieldBalancePill(),
          ],
        ),
      ],
    );
  }

  Widget _buildFlowHeaderPill(BuildContext context) {
    FlowProvider? flowProvider;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: true);
    } catch (_) {}

    final companion = flowProvider?.companion;
    final streak = flowProvider?.profile.currentStreak ?? 0;
    final name = companion?.name ?? 'Noya';
    final level = companion?.level ?? 1;

    return Semantics(
      button: true,
      label: '$name Level $level, $streak day streak. Open Flow hub.',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(FlowRadii.pill),
          onTap: () {
            FlowHaptics.selection();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FlowScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: FlowColors.surfaceElevated(context),
              borderRadius: BorderRadius.circular(FlowRadii.pill),
              border: Border.all(
                color: FlowColors.mint.withValues(alpha: 0.35),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: FlowColors.mint.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const NoyaCompanionView(
                  state: NoyaState.idle,
                  size: 28,
                ),
                const SizedBox(width: 6),
                Text(
                  '$name · L$level',
                  style: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                if (streak > 0) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.local_fire_department_rounded, size: 13, color: Color(0xFFF97316)),
                  const SizedBox(width: 2),
                  Text(
                    '${streak}d',
                    style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNewUserEmptyState(BuildContext context, AppStateProvider state, Color accent) {
    final isDark = FlowColors.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. HERO: Build My Day (Flowstate's Signature Planning Feature)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: FlowColors.surface(context),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? [FlowColors.surfaceDark, const Color(0xFF141F32)]
                  : [Colors.white, const Color(0xFFF0F9FF)],
            ),
            borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
            border: Border.all(
              color: isDark
                  ? FlowColors.borderDark
                  : FlowColors.accentCyan.withValues(alpha: 0.22),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: FlowColors.accentCyan.withValues(alpha: isDark ? 0.08 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 13, color: FlowColors.accentCyan),
                    const SizedBox(width: 5),
                    Text(
                      'AI DAY PLANNER',
                      style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "What's on your plate?",
                          style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tell Flowstate everything you need to do, and it figures out when each thing fits.',
                          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontSize: 13.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const NoyaCompanionView(
                    state: NoyaState.encouraging,
                    size: 76.0,
                    showAmbientGlow: true,
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // One-time "2 Shields added" welcome; its arrow points at the button right below it.
              ShieldWelcomeCard(key: _welcomeKey),

              // Primary CTA: [ Build my day ]
              FramerMotionPressScale(
                onTap: () {
                  FlowHaptics.lightTap();
                  _welcomeKey.currentState?.dismiss();
                  showBrainDumpSheet(context);
                },
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('hero_build_my_day_button'),
                    onPressed: () {
                      FlowHaptics.lightTap();
                      _welcomeKey.currentState?.dismiss();
                      showBrainDumpSheet(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 2,
                      shadowColor: accent.withValues(alpha: 0.35),
                      shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: Text(
                      'Build my day',
                      style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Secondary text action: [ + Add one task ]
              Center(
                child: TextButton(
                  key: const Key('hero_add_one_task_button'),
                  onPressed: () {
                    FlowHaptics.selection();
                    _openAddTaskSheet(context);
                  },
                  child: Text(
                    '+ Add one task',
                    style: FlowTypography.labelLarge(color: accent).copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 2),

              // Small hint
              Center(
                child: Text(
                  'Dump everything at once or add tasks individually. Flowstate finds the best focus windows.',
                  textAlign: TextAlign.center,
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Compact Flow Card on Active Today
  Widget _buildTodayFlowCard(BuildContext context, AppStateProvider state, Color accent) {
    FlowProvider? flowProvider;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: true);
    } catch (_) {}

    final companion = flowProvider?.companion;
    final streak = flowProvider?.profile.currentStreak ?? 0;
    final xp = companion?.companionXp ?? flowProvider?.profile.lifetimeFlow ?? 0;
    final level = companion?.level ?? 1;
    final name = companion?.name ?? 'Noya';

    return InkWell(
      onTap: () {
        FlowHaptics.selection();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FlowScreen()),
        );
      },
      borderRadius: BorderRadius.circular(FlowRadii.card),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlowColors.surface(context),
          borderRadius: BorderRadius.circular(FlowRadii.card),
          border: Border.all(color: FlowColors.border(context), width: 1.0),
          boxShadow: [
            BoxShadow(
              color: FlowColors.softShadow(context),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt_rounded, size: 14, color: FlowColors.accentCyan),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'YOUR FLOW',
                          overflow: TextOverflow.ellipsis,
                          style: FlowTypography.badgeText(color: FlowColors.accentCyan).copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Flow Hub →',
                  style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Living Noya: hops on a completion, celebrates the last task of the day.
                NoyaMotionView(
                  mood: NoyaMood.rest,
                  size: 48,
                  reactions: flowProvider?.animController.reactions,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        streak > 0
                            ? '$name · L$level · $xp XP · $streak d'
                            : '$name · L$level · $xp XP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Focus companion · Flow Hub',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Flow Hub & Companion',
                    overflow: TextOverflow.ellipsis,
                    style: FlowTypography.labelSmall(color: FlowColors.textMutedOf(context)),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Open Hub',
                      style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: FlowColors.accentCyan),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Completed Day State
  Widget _buildDayCompletedState(
    BuildContext context,
    AppStateProvider state,
    Color accent,
  ) {
    final completedCount = state.todayCompletion.completedToday.length;
    final now = DateTime.now();

    final bedtimeHour = state.personalData.bedtimeHour; // e.g. 23.0 (11:00 PM)
    final currentHour = now.hour + (now.minute / 60.0);
    // Day genuinely finished boundary: strictly at or past configured bedtime
    final isAtOrPastBedtime = bedtimeHour >= 18.0
        ? (currentHour >= bedtimeHour || currentHour < 5.0)
        : (bedtimeHour < 6.0
            ? (currentHour >= bedtimeHour && currentHour < 6.0)
            : (currentHour >= bedtimeHour));

    final hasUpcomingTasks = state.tasks.any((t) =>
        !t.isCompleted &&
        t.status != TaskStatus.cancelled &&
        t.status != TaskStatus.archived &&
        t.scheduledStart != null &&
        t.scheduledStart!.isAfter(now));

    final isDayActuallyFinished = isAtOrPastBedtime && !hasUpcomingTasks;

    final String headline;
    final String subtitle;
    final String primaryButtonLabel;
    final VoidCallback primaryButtonAction;
    final String secondaryButtonLabel;
    final VoidCallback secondaryButtonAction;

    // Every task of today is done: Noya curls up, and adding more is one tap away.
    headline = 'All done for today!';
    primaryButtonLabel = 'Add more tasks';
    primaryButtonAction = () {
      FlowHaptics.lightTap();
      _openAddTaskSheet(context);
    };
    if (isDayActuallyFinished) {
      // Past the configured bedtime: the next step is tomorrow.
      subtitle = "Nice work. Time to wind down.";
      secondaryButtonLabel = 'Plan tomorrow';
      secondaryButtonAction = () {
        FlowHaptics.selection();
        _openAddTaskSheet(context);
      };
    } else {
      subtitle = "Nice work. Rest, or add a little more.";
      secondaryButtonLabel = 'Build My Day';
      secondaryButtonAction = () {
        FlowHaptics.selection();
        showBrainDumpSheet(context);
      };
    }

    const NoyaState completionNoyaState = NoyaState.sleepy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Completed celebration card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: FlowColors.surface(context),
            borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
            border: Border.all(color: FlowColors.mint.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: FlowColors.mint.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const NoyaCompanionView(
                    key: Key('all_done_noya'),
                    state: completionNoyaState,
                    size: 76.0,
                    showAmbientGlow: true,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headline,
                          key: const Key('all_done_headline'),
                          style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (completedCount > 0) ...[
                const SizedBox(height: 14),
                const TodaySoFar(),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  key: const Key('completed_state_primary_button'),
                  onPressed: primaryButtonAction,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: FlowColors.textInverse,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          primaryButtonLabel,
                          style: FlowTypography.labelMedium(color: FlowColors.textInverse).copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              ...[
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    key: const Key('completed_state_secondary_button'),
                    onPressed: secondaryButtonAction,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accent,
                      backgroundColor: FlowColors.surfaceElevated(context),
                      side: BorderSide(
                        color: accent.withValues(alpha: FlowColors.isDark(context) ? 0.45 : 0.35),
                        width: 1.0,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(FlowRadii.button),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            secondaryButtonLabel == 'Build My Day'
                                ? Icons.auto_awesome_rounded
                                : Icons.calendar_today_rounded,
                            size: 18,
                            color: accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            secondaryButtonLabel,
                            style: FlowTypography.labelMedium(
                              color: accent,
                            ).copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Replan Sheet for "Later" Action
  void _showLaterSheet(
    BuildContext context,
    TaskItem task,
    AppStateProvider state,
    Color accent,
  ) {
    RescheduleTaskSheet.show(context, task);
  }


  /// 4. Minimal Upcoming Timeline
  /// Time + subtle vertical line + Title + Duration
  /// Shows next 3-4 items, omitting the primary hero task to avoid repetition.
  /// TOMORROW: tomorrow's open tasks (backend `tomorrow_tasks`), kept apart from today's execution view.
  Widget _buildTomorrowSection(BuildContext context, AppStateProvider state) {
    final tasks = state.todaySnapshot?.tomorrowTasks ?? const <TomorrowTask>[];
    if (tasks.isEmpty) return const SizedBox.shrink();

    const maxRows = 5;
    final shown = tasks.take(maxRows).toList();
    final more = tasks.length - shown.length;
    final muted = FlowColors.textSecondaryOf(context);

    return Padding(
      key: const Key('today_tomorrow_section'),
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOMORROW',
            style: FlowTypography.badgeText(color: muted).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: FlowColors.surface(context),
              borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
              border: Border.all(color: FlowColors.border(context), width: 1.0),
            ),
            child: Column(
              children: [
                for (final t in shown)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    child: Row(
                      key: Key('tomorrow_task_${t.id}'),
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(
                            t.startTime == null ? 'Anytime' : DateFormat('h:mm a').format(t.startTime!),
                            style: FlowTypography.labelSmall(color: muted).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context))
                                .copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${t.durationMinutes}m', style: FlowTypography.labelSmall(color: muted)),
                      ],
                    ),
                  ),
                if (more > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('+$more more', style: FlowTypography.labelSmall(color: muted)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineSection(
    BuildContext context,
    AppStateProvider state,
    Color accent,
    TaskItem? recommended,
  ) {
    if (state.schedule.isEmpty) return const SizedBox.shrink();

    final completedIds = state.tasks.where((t) => t.isCompleted).map((t) => t.id).toSet();
    final knownIds = state.tasks.map((t) => t.id).toSet();

    // Filter out completed tasks and the primary task so it is not repeated immediately
    final filteredSchedule = state.schedule.where((item) {
      final cleanId = item.id.startsWith('sched-') ? item.id.substring(6) : item.id;
      final isItemDone = item.isCompleted ||
          completedIds.contains(item.id) ||
          completedIds.contains(cleanId) ||
          (item.taskId != null && completedIds.contains(item.taskId));
      if (isItemDone) return false;

      if (recommended == null) return true;
      // The same task by id. A same-named task on another day (or later today) is a different task and stays listed.
      final linkedId = item.taskId ?? cleanId;
      final linksToAnyTask = knownIds.contains(linkedId) || knownIds.contains(item.id);
      return item.id != recommended.id &&
          linkedId != recommended.id &&
          (linksToAnyTask || item.title.toLowerCase() != recommended.title.toLowerCase());
    }).toList();

    if (filteredSchedule.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UP NEXT',
            style: FlowTypography.badgeText(color: FlowColors.textSecondaryOf(context)).copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: FlowColors.surface(context),
              borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const NoyaCompanionView(
                  state: NoyaState.celebrating,
                  size: 44,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "You're clear for today.",
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Your planned tasks are done.',
                        style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    FlowHaptics.selection();
                    _openAddTaskSheet(context);
                  },
                  child: Text(
                    '+ Add a task',
                    style: FlowTypography.labelMedium(color: accent).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Show only the next 3-4 relevant events unless expanded
    final displayItems = _showFullDay
        ? filteredSchedule
        : filteredSchedule.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header: UP NEXT + View full day →
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'UP NEXT',
              style: FlowTypography.badgeText(color: FlowColors.textSecondaryOf(context)).copyWith(
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
              child: FlowTimelineRow(
                item: item,
                isLast: isLast,
                onTap: () => _showTimelineInspection(context, item, state),
                onDoThisNow: () {
                  FlowHaptics.selection();
                  state.setPreferredActiveTask(item.id);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('"${item.title}" is now your top task.'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                onComplete: () => _confirmAndCompleteTimelineTask(context, item, state),
                onStart: () {
                  TaskItem? matching;
                  try {
                    matching = state.tasks.firstWhere(
                      (t) =>
                          t.id == item.id ||
                          (item.taskId != null && t.id == item.taskId) ||
                          (item.id.startsWith('sched-') && t.id == item.id.substring(6)) ||
                          t.title.toLowerCase() == item.title.toLowerCase(),
                    );
                  } catch (_) {}
                  openFocusRitual(context, task: matching);
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmAndCompleteTimelineTask(
    BuildContext context,
    ScheduleItem item,
    AppStateProvider state,
  ) async {
    FlowHaptics.selection();

    // Resolve matching task item
    TaskItem matchingTask;
    try {
      matchingTask = state.tasks.firstWhere(
        (t) =>
            t.id == item.id ||
            (item.taskId != null && t.id == item.taskId) ||
            (item.id.startsWith('sched-') && t.id == item.id.substring(6)) ||
            t.title.toLowerCase() == item.title.toLowerCase(),
      );
    } catch (_) {
      matchingTask = TaskItem(
        id: item.taskId ?? (item.id.startsWith('sched-') ? item.id.substring(6) : item.id),
        title: item.title,
        durationMinutes: item.durationMinutes,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: item.type,
        isCompleted: false,
      );
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FlowColors.surface(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
          side: BorderSide(color: FlowColors.border(context)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FlowColors.mint.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_rounded, color: FlowColors.mint, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Complete Task?',
                style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Mark "${matchingTask.title}" as completed?',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(
              'Cancel',
              style: FlowTypography.labelMedium(color: FlowColors.textMutedOf(context)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: FlowColors.mint,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: const RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
              elevation: 0,
            ),
            child: Text(
              'Mark Done',
              style: FlowTypography.buttonPrimary(color: Colors.black).copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    FlowHaptics.success();
    state.toggleTaskCompletion(matchingTask.id);

    try {
      Provider.of<FlowProvider>(this.context, listen: false).completeSession(
        taskCompleted: true,
      );
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(this.context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Completed "${matchingTask.title}"',
                style: FlowTypography.bodyMedium(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: FlowColors.mint,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    showTaskFeedbackSheet(
      this.context,
      taskId: matchingTask.id,
      actualMinutes: matchingTask.durationMinutes,
      onSubmit: (feedback) {
        state.recordTaskFeedback(
          taskId: matchingTask.id,
          actualMinutes: feedback.actualMinutes,
          feeling: feedback.feeling,
          durationFeedback: feedback.durationFeedback,
          blockerNote: feedback.blockerNote,
          energyScore: feedback.energyScore,
          focusScore: feedback.focusScore,
          difficultyScore: feedback.difficultyScore,
          distractionScore: feedback.distractionScore,
          completedAt: feedback.completedAt,
        );
      },
    );
  }

  void _showTimelineInspection(
    BuildContext context,
    ScheduleItem item,
    AppStateProvider state,
  ) {
    FlowHaptics.lightTap();
    TaskItem matchingTask;
    try {
      matchingTask = state.tasks.firstWhere(
        (t) =>
            t.id == item.id ||
            (item.taskId != null && t.id == item.taskId) ||
            (item.id.startsWith('sched-') && t.id == item.id.substring(6)) ||
            t.title.toLowerCase() == item.title.toLowerCase(),
      );
    } catch (_) {
      matchingTask = TaskItem(
        id: item.taskId ?? (item.id.startsWith('sched-') ? item.id.substring(6) : item.id),
        title: item.title,
        durationMinutes: item.durationMinutes,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: item.type,
        isCompleted: false,
      );
    }

    Color accent = FlowColors.accentCyan;
    try {
      accent = Provider.of<ThemeProvider>(context, listen: false).resolveAccent(context);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      backgroundColor: FlowColors.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(FlowRadii.cardLarge)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: FlowSpacing.pageMargin(context),
              vertical: 20,
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
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.tagBg,
                        borderRadius: BorderRadius.circular(FlowRadii.chip),
                      ),
                      child: Text(
                        item.tagText,
                        style: FlowTypography.badgeText(color: item.tagColor).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${item.time} ${item.period} · ${item.durationMinutes} min',
                      style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  item.title,
                  style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          state.setPreferredActiveTask(matchingTask.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"${matchingTask.title}" is now your top task.'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: FlowColors.border(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowRadii.button),
                          ),
                        ),
                        child: Text(
                          'Do this now',
                          style: FlowTypography.labelMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          openFocusRitual(context, task: matchingTask);
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: FlowColors.textInverse,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowRadii.button),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          'Start Focus',
                          style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        key: const Key('timeline_task_later_button'),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          RescheduleTaskSheet.show(context, matchingTask);
                        },
                        icon: const Icon(Icons.schedule_rounded, size: 16),
                        label: const Text('Later'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          EditTaskSheet.show(context, matchingTask);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _confirmAndCompleteTimelineTask(context, item, state);
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                        label: const Text('Done'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _confirmAndDeleteTimelineTask(context, matchingTask, state);
                    },
                    icon: const Icon(Icons.delete_outline_rounded, size: 16, color: FlowColors.error),
                    label: Text(
                      'Delete Task',
                      style: FlowTypography.labelSmall(color: FlowColors.error).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmAndDeleteTimelineTask(
    BuildContext context,
    TaskItem task,
    AppStateProvider state,
  ) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: FlowColors.surfaceElevated(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.cardLarge)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: FlowColors.error, size: 24),
            const SizedBox(width: 8),
            Text(
              'Delete Task?',
              style: FlowTypography.titleMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${task.title}"? This action cannot be undone.',
          style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(
              'Cancel',
              style: FlowTypography.labelLarge(color: FlowColors.textSecondaryOf(context)),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              FlowHaptics.selection();
              state.removeTask(task.id);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Task "${task.title}" deleted.'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: FlowColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
