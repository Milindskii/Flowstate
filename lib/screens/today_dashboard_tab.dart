import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../components/compact_readiness_card.dart';
import '../components/right_now_task_card.dart';
import '../components/timeline_item_widget.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'add_task_sheet.dart';
import 'what_should_i_do_screen.dart';

/// Screen 4: Redesigned Today Execution Screen
/// Focuses purely on: "What should I do right now?", "Why?", and "What's next?"
class TodayDashboardTab extends StatefulWidget {
  const TodayDashboardTab({super.key});

  @override
  State<TodayDashboardTab> createState() => _TodayDashboardTabState();
}

class _TodayDashboardTabState extends State<TodayDashboardTab> {
  bool _showEarlierItems = false;

  String _formatTodayDate() {
    final now = DateTime.now();
    return DateFormat('EEEE, MMM d').format(now);
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
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WhatShouldIDoScreen(task: task),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    // 1. Loading State
    if (state.isLoading) {
      return Scaffold(
        backgroundColor: FlowColors.darkBackground,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(FlowColors.cyan),
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

    // 2. Error State
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
                    backgroundColor: FlowColors.cyan,
                    foregroundColor: FlowColors.textInverse,
                    shape: RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
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

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      // Small, non-intrusive floating "What now?" pill docked at bottom-right
      floatingActionButton: recommended != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 8.0, right: 4.0),
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: FlowRadii.pillRadius,
                  gradient: FlowColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: FlowColors.cyan.withOpacity(0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: FlowRadii.pillRadius,
                    onTap: () => _navigateToWhatNow(context, recommended),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: FlowColors.textInverse,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'What now?',
                            style: FlowTypography.labelMedium(color: FlowColors.textInverse).copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header (Dynamic user name, date, avatar)
              _buildHeader(context, state),
              const SizedBox(height: 20),

              // 2. Lifecycle Switch: New User vs Populated Day
              if (state.isNewUser) ...[
                _buildNewUserEmptyState(context, state),
              ] else ...[
                // Compact Readiness Card
                CompactReadinessCard(
                  readiness: state.readiness,
                  onTap: () => state.setNavIndex(3), // Navigate to Insights
                ),
                const SizedBox(height: 22),

                // Primary "RIGHT NOW" Task
                if (recommended != null) ...[
                  RightNowTaskCard(
                    task: recommended,
                    onStart: () {
                      state.setActiveFocusTask(recommended);
                      _navigateToWhatNow(context, recommended);
                    },
                    onReschedule: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Rescheduling task to next available focus block...'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      state.optimizeSchedule();
                    },
                  ),
                  const SizedBox(height: 24),
                ],

                // 3. Chronological Today Timeline
                _buildTimelineSection(context, state),
              ],

              // Safe bottom clearance so content is never obscured by FAB or bottom nav
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Bar: Dynamic user greeting, current date, avatar
  Widget _buildHeader(BuildContext context, AppStateProvider state) {
    final greeting = state.isNewUser ? 'Good morning 👋' : 'Good morning, ${state.greetingName} 👋';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: FlowTypography.headlineMedium().copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTodayDate(),
              style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
            ),
          ],
        ),
        // User Avatar / Profile tap
        GestureDetector(
          onTap: () => state.setNavIndex(4), // Navigate to Profile
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: FlowColors.darkCard,
              shape: BoxShape.circle,
              border: Border.all(color: FlowColors.darkBorder, width: 1.0),
            ),
            child: Center(
              child: Text(
                state.greetingName.isNotEmpty ? state.greetingName[0].toUpperCase() : 'U',
                style: FlowTypography.titleMedium(color: FlowColors.cyan).copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Empty state for new users: "Let's build your day."
  Widget _buildNewUserEmptyState(BuildContext context, AppStateProvider state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: FlowColors.darkCard,
        borderRadius: FlowRadii.cardLargeRadius,
        border: Border.all(color: FlowColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: FlowColors.cyan.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wb_sunny_outlined, color: FlowColors.cyan, size: 26),
          ),
          const SizedBox(height: 18),
          Text(
            'Let’s build your day.',
            style: FlowTypography.headlineMedium().copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'You have no tasks planned yet. Add what you need to get done and Flowstate will organize it around your available focus windows.',
            style: FlowTypography.bodyLarge(color: FlowColors.textSecondary),
          ),
          const SizedBox(height: 24),

          // Primary: Add a task
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () => _openAddTaskSheet(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add a task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: FlowColors.cyan,
                foregroundColor: FlowColors.textInverse,
                shape: RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
                textStyle: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Secondary: Tell Flowstate what I need to do
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () => _openAddTaskSheet(context),
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: FlowColors.textPrimary),
              label: Text('Tell Flowstate what I need to do', style: FlowTypography.labelMedium().copyWith(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: FlowColors.darkBorder),
                shape: RoundedRectangleBorder(borderRadius: FlowRadii.buttonRadius),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Calendar connection prompt
          InkWell(
            onTap: () async {
              await state.calendarService.connectGoogleCalendar();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Google Calendar linked successfully!')),
              );
            },
            borderRadius: FlowRadii.inputRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: FlowColors.mint, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Connect Google Calendar to sync commitments',
                    style: FlowTypography.labelSmall(color: FlowColors.mint).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Clean Chronological Today Timeline with "Show earlier" collapsible toggle
  Widget _buildTimelineSection(BuildContext context, AppStateProvider state) {
    if (state.schedule.isEmpty) return const SizedBox.shrink();

    // Determine past vs upcoming items
    final schedule = state.schedule;
    final int splitIndex = (schedule.length > 2) ? 1 : 0;
    final pastItems = schedule.sublist(0, splitIndex);
    final upcomingItems = schedule.sublist(splitIndex);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title + See All
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'TODAY',
              style: FlowTypography.titleMedium().copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
            ),
            GestureDetector(
              onTap: () => state.setNavIndex(2), // Navigate to Calendar tab
              child: Text(
                'Full Day',
                style: FlowTypography.labelMedium(color: FlowColors.cyan).copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Earlier items collapsible button
        if (pastItems.isNotEmpty) ...[
          InkWell(
            onTap: () {
              setState(() {
                _showEarlierItems = !_showEarlierItems;
              });
            },
            borderRadius: FlowRadii.inputRadius,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Icon(
                    _showEarlierItems ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: FlowColors.textMuted,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _showEarlierItems ? 'Hide earlier items' : 'Show earlier (${pastItems.length} completed)',
                    style: FlowTypography.labelSmall(color: FlowColors.textMuted).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_showEarlierItems)
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: pastItems.length,
              itemBuilder: (ctx, idx) {
                return Opacity(
                  opacity: 0.65,
                  child: TimelineItemWidget(
                    item: pastItems[idx],
                    isLast: false,
                  ),
                );
              },
            ),
          const SizedBox(height: 6),
        ],

        // Upcoming timeline blocks
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: upcomingItems.length,
          itemBuilder: (context, index) {
            final item = upcomingItems[index];
            final isLast = index == upcomingItems.length - 1;
            return TimelineItemWidget(item: item, isLast: isLast);
          },
        ),
      ],
    );
  }
}
