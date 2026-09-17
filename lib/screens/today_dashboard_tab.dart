import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/readiness_hero_card.dart';
import '../components/recommended_task_card.dart';
import '../components/timeline_item_widget.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_typography.dart';
import 'what_should_i_do_screen.dart';

/// Screen 4: Today Dashboard
/// The primary home screen showing readiness, recommended next task, and timeline schedule.
class TodayDashboardTab extends StatelessWidget {
  const TodayDashboardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar: Greeting & Avatar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Good morning, Alex',
                        style: FlowTypography.headlineMedium().copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Monday, Oct 24',
                        style: FlowTypography.bodyMedium(color: FlowColors.textSecondary),
                      ),
                    ],
                  ),
                  // User Avatar
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: FlowColors.darkCard,
                      shape: BoxShape.circle,
                      border: Border.all(color: FlowColors.darkBorder, width: 1.0),
                    ),
                    child: Center(
                      child: Text(
                        'A',
                        style: FlowTypography.titleMedium(color: FlowColors.cyanLight).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Hero Readiness Card
              ReadinessHeroCard(
                readiness: state.readiness,
                onTap: () {
                  // Switch to Insights tab
                  state.setNavIndex(3);
                },
              ),
              const SizedBox(height: 28),

              // Recommended Next Task
              if (state.recommendedTask != null)
                RecommendedTaskCard(
                  task: state.recommendedTask!,
                  onStart: () {
                    state.setActiveFocusTask(state.recommendedTask);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WhatShouldIDoScreen(task: state.recommendedTask!),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 28),

              // Today's Schedule Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Today's Schedule",
                    style: FlowTypography.titleMedium().copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      // Switch to Calendar tab
                      state.setNavIndex(2);
                    },
                    child: Text(
                      'See All',
                      style: FlowTypography.labelMedium(color: FlowColors.cyanLight).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Timeline Schedule List
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.schedule.length,
                itemBuilder: (context, index) {
                  final item = state.schedule[index];
                  final isLast = index == state.schedule.length - 1;
                  return TimelineItemWidget(item: item, isLast: isLast);
                },
              ),

              // Bottom safe clearance for floating thumb button
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }
}
