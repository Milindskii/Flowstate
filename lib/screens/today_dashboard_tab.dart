import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/break_session_card.dart';
import '../components/companion/companion_graphic.dart';
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
  bool _showFullDay = false;

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

    // 1. Loading State: Shimmer Skeleton
    if (state.isLoading) {
      return const TodayDashboardSkeleton();
    }



    final recommended = state.recommendedTask;
    final bool isCurrentRunning =
        recommended != null && state.activeFocusTask?.id == recommended.id;
    final bool hasAnyTasks = state.tasks.isNotEmpty ||
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
                          style: FlowTypography.badgeText(color: FlowColors.textSecondary).copyWith(
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
    switch (state.todayState) {
      case TodayState.newUser:
        return "Let's build your first plan.";
      case TodayState.learning:
        return "What are we getting done today?";
      case TodayState.calibrated:
        return "Ready for a good session?";
      case TodayState.completed:
        return "Nice work today. Take a breather.";
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
                  color: FlowColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _getHeaderSubtitle(state, hasAnyTasks),
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
        // Header actions: Flow Companion Pill + User Avatar
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFlowHeaderPill(context),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => state.setNavIndex(4), // Navigate to Profile
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  shape: BoxShape.circle,
                  border: Border.all(color: FlowColors.border(context), width: 1.0),
                ),
                child: Center(
                  child: Text(
                    state.greetingName.isNotEmpty ? state.greetingName[0].toUpperCase() : 'U',
                    style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
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
                CompanionGraphic(
                  species: companion?.species ?? 'fox',
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  '$name · L$level',
                  style: FlowTypography.labelSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
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
                      fontSize: 11,
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
    FlowProvider? flowProvider;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: true);
    } catch (_) {}

    final companion = flowProvider?.companion;
    final companionName = companion?.name ?? 'Noya';
    final species = companion?.species ?? 'fox';
    final isDark = FlowColors.isDark(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. HERO: Build My Day
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
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: FlowColors.accentCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(FlowRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded, size: 12, color: FlowColors.accentCyan),
                    const SizedBox(width: 5),
                    Text(
                      'DAY PLANNER',
                      style: FlowTypography.labelSmall(color: FlowColors.accentCyan).copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "What's on your plate?",
                style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Add everything you need to get done and we'll organize it.",
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)).copyWith(
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),

              // Primary CTA: [ Build my day ]
              FramerMotionPressScale(
                onTap: () {
                  FlowHaptics.lightTap();
                  showBrainDumpSheet(context);
                },
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('hero_build_my_day_button'),
                    onPressed: () {
                      FlowHaptics.lightTap();
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
                  'Dump everything at once or add tasks individually.',
                  textAlign: TextAlign.center,
                  style: FlowTypography.bodySmall(color: FlowColors.textMutedOf(context)).copyWith(
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 2. FLOW HERO
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: FlowColors.surface(context),
            borderRadius: BorderRadius.circular(FlowRadii.cardLarge),
            border: Border.all(
              color: isDark ? FlowColors.borderDark : const Color(0xFFE2E8F0),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 14,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: + FLOW & 25 min badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '✦ FLOW',
                    style: FlowTypography.badgeText(color: FlowColors.accentCyan).copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      fontSize: 11,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? FlowColors.surfaceElevated(context) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(FlowRadii.pill),
                    ),
                    child: Text(
                      '25 min',
                      style: FlowTypography.labelSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Companion + Text Row (NO circle aura, winking fox sits directly on card)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/companions/fox_winking.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => CompanionGraphic(
                      species: species,
                      size: 64,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lock in with $companionName.',
                          style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '25 minutes. One thing. No distractions.',
                          style: FlowTypography.bodySmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Button: Soft Ice-Blue / Cyan Pill "Start Flow" with lightning bolt
              FramerMotionPressScale(
                onTap: () {
                  FlowHaptics.lightTap();
                  openFocusRitual(context, initialMinutes: 25);
                },
                child: Container(
                  width: double.infinity,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? FlowColors.cyan.withValues(alpha: 0.16) : const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(FlowRadii.button),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      key: const Key('hero_start_flow_button'),
                      borderRadius: BorderRadius.circular(FlowRadii.button),
                      onTap: () {
                        FlowHaptics.lightTap();
                        openFocusRitual(context, initialMinutes: 25);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.bolt_rounded,
                            size: 20,
                            color: isDark ? FlowColors.cyan : const Color(0xFF0284C7),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Start Flow',
                            style: FlowTypography.labelLarge(
                              color: isDark ? FlowColors.cyan : const Color(0xFF0284C7),
                            ).copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
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
                SizedBox(
                  width: 44,
                  height: 44,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      (companion?.species ?? 'fox').toLowerCase().trim() == 'otter' || (companion?.species ?? '').toLowerCase().trim() == 'ludo'
                          ? 'assets/images/companions/otter.png'
                          : ((companion?.species ?? '').toLowerCase().trim() == 'owl' || (companion?.species ?? '').toLowerCase().trim() == 'aria'
                              ? 'assets/images/companions/owl.png'
                              : ((companion?.species ?? '').toLowerCase().trim() == 'capybara' || (companion?.species ?? '').toLowerCase().trim() == 'boba'
                                  ? 'assets/images/companions/capybara.png'
                                  : ((companion?.species ?? '').toLowerCase().trim() == 'cat' || (companion?.species ?? '').toLowerCase().trim() == 'mochi'
                                      ? 'assets/images/companions/cat.png'
                                      : 'assets/images/companions/fox_winking.png'))),
                      width: 44,
                      height: 44,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => CompanionGraphic(
                        species: companion?.species ?? 'fox',
                        size: 44,
                      ),
                    ),
                  ),
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
                        '25 min · Focus with $name',
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
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton.icon(
                onPressed: () {
                  FlowHaptics.lightTap();
                  openFocusRitual(context, initialMinutes: 25);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: FlowColors.surfaceElevated(context),
                  foregroundColor: FlowColors.textPrimaryOf(context),
                  elevation: 0,
                  side: BorderSide(color: FlowColors.border(context)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                ),
                icon: const Icon(Icons.bolt_rounded, size: 16, color: FlowColors.accentCyan),
                label: const Text('Start Flow'),
              ),
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
    final completedCount = state.todaySnapshot?.completedCount ??
        state.tasks.where((t) => t.isCompleted).length;
    final focusMinutes = completedCount * 25;

    FlowProvider? flowProvider;
    try {
      flowProvider = Provider.of<FlowProvider>(context, listen: false);
    } catch (_) {}
    final companion = flowProvider?.companion;

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
                children: [
                  Text(
                    'Nice work today',
                    style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  CompanionGraphic(
                    species: companion?.species ?? 'fox',
                    size: 24,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$completedCount ${completedCount == 1 ? 'task' : 'tasks'} completed'
                '${focusMinutes > 0 ? ' · $focusMinutes min focused' : ''}',
                style: FlowTypography.titleSmall(color: FlowColors.textSecondaryOf(context)).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You kept your Flow going.',
                style: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
              ),
              const SizedBox(height: 20),
              // Tomorrow section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FlowColors.surfaceElevated(context),
                  borderRadius: FlowRadii.inputRadius,
                  border: Border.all(color: FlowColors.border(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tomorrow',
                      style: FlowTypography.badgeText(color: FlowColors.accentCyan).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Prepare for your next focus session',
                      style: FlowTypography.bodyMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: () {
                    FlowHaptics.lightTap();
                    _openAddTaskSheet(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: FlowColors.textInverse,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Plan tomorrow'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Optional Flow CTA (Keep your momentum alive)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: FlowColors.surface(context),
            borderRadius: BorderRadius.circular(FlowRadii.card),
            border: Border.all(color: FlowColors.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '✦ FLOW',
                style: FlowTypography.badgeText(color: FlowColors.accentCyan).copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Keep your momentum alive.',
                style: FlowTypography.bodyMedium(color: FlowColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    FlowHaptics.lightTap();
                    openFocusRitual(context, initialMinutes: 25);
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: FlowColors.textPrimaryOf(context),
                    side: BorderSide(color: FlowColors.border(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                  ),
                  icon: const Icon(Icons.bolt_rounded, size: 18, color: FlowColors.accentCyan),
                  label: const Text('Start 25 min Flow'),
                ),
              ),
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
    FlowHaptics.lightTap();
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
                const SizedBox(height: 18),
                Text(
                  'Move it?',
                  style: FlowTypography.headlineMedium(color: FlowColors.textPrimaryOf(context)).copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Next good window',
                  style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: FlowColors.surfaceElevated(context),
                    borderRadius: FlowRadii.inputRadius,
                    border: Border.all(color: FlowColors.border(context)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 18, color: FlowColors.accentCyan),
                      const SizedBox(width: 8),
                      Text(
                        'Tomorrow · 9:30 AM',
                        style: FlowTypography.titleSmall(color: FlowColors.textPrimaryOf(context)).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      state.optimizeSchedule();
                      state.refreshTodayData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Moved "${task.title}" to tomorrow 9:30 AM · Replanning day...'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: FlowColors.textInverse,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                    ),
                    child: const Text('Move there'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      state.optimizeSchedule();
                      state.refreshTodayData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Rescheduling to next available slot...'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: FlowColors.textPrimaryOf(context),
                      side: BorderSide(color: FlowColors.border(context)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FlowRadii.button)),
                    ),
                    child: const Text('Choose another time'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

    if (filteredSchedule.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'UP NEXT',
            style: FlowTypography.badgeText(color: FlowColors.textSecondary).copyWith(
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
              borderRadius: BorderRadius.circular(FlowRadii.card),
              border: Border.all(color: FlowColors.border(context)),
            ),
            child: Text(
              'Nothing else planned today.',
              style: FlowTypography.bodyMedium(color: FlowColors.textMutedOf(context)),
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
                onTap: () => _showTimelineInspection(context, item, state),
                onComplete: () {
                  FlowHaptics.success();
                  state.toggleTaskCompletion(item.id);
                  try {
                    Provider.of<FlowProvider>(context, listen: false).completeSession(
                      taskCompleted: true,
                    );
                  } catch (_) {}
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Completed "${item.title}"'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                onStart: () {
                  TaskItem? matching;
                  try {
                    matching = state.tasks.firstWhere(
                      (t) => t.id == item.id || t.title.toLowerCase() == item.title.toLowerCase(),
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

  void _showTimelineInspection(
    BuildContext context,
    ScheduleItem item,
    AppStateProvider state,
  ) {
    FlowHaptics.lightTap();
    TaskItem matchingTask;
    try {
      matchingTask = state.tasks.firstWhere(
        (t) => t.id == item.id || t.title.toLowerCase() == item.title.toLowerCase(),
      );
    } catch (_) {
      matchingTask = TaskItem(
        id: item.id,
        title: item.title,
        durationMinutes: item.durationMinutes,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: item.type,
        isCompleted: false,
      );
    }

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
                          state.optimizeSchedule();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(color: FlowColors.border(context)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowRadii.button),
                          ),
                        ),
                        child: Text(
                          'Reschedule',
                          style: FlowTypography.labelMedium(color: FlowColors.textSecondaryOf(context)),
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
                          backgroundColor: FlowColors.mint,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(FlowRadii.button),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: Text(
                          'Focus Ritual',
                          style: FlowTypography.labelLarge(color: Colors.black).copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
