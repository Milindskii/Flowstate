import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/flow_ambient_background.dart';
import '../components/flow_bottom_nav.dart';
import '../components/noya_thinking.dart';
import '../components/companion/noya_reaction_controller.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_motion.dart';
import 'today_dashboard_tab.dart';
import 'task_inbox_tab.dart';
import 'calendar_tab.dart';
import 'insights_tab.dart';
import 'profile_settings_tab.dart';

/// Root Mobile Shell coordinating bottom navigation and the 5 destinations.
/// Integrates the luminous FlowAmbientBackground across all tabs to ensure
/// the entire app feels clean, alive, and cohesive without blank or sterile surfaces.
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const List<Widget> _tabs = [
    TodayDashboardTab(),
    TaskInboxTab(),
    CalendarTab(),
    InsightsTab(),
    ProfileSettingsTab(),
  ];

  OnboardingVisualState _getTabVisualState(int index) {
    switch (index) {
      case 0:
        // Today Tab: Time-aligned circadian ambient wash
        final hour = DateTime.now().hour;
        if (hour >= 5 && hour < 12) {
          return OnboardingVisualState.morningBright;
        } else if (hour >= 12 && hour < 18) {
          return OnboardingVisualState.focusActive;
        } else if (hour >= 18 && hour < 22) {
          return OnboardingVisualState.twilight;
        } else {
          return OnboardingVisualState.settling;
        }
      case 1:
        // Tasks Inbox: Energizing focus mint & cyan
        return OnboardingVisualState.focusActive;
      case 2:
        // Calendar: Twilight planning clarity
        return OnboardingVisualState.twilight;
      case 3:
        // Insights: Crisp bright clarity
        return OnboardingVisualState.morningBright;
      case 4:
        // Profile: Balanced neutral slate
        return OnboardingVisualState.neutral;
      default:
        return OnboardingVisualState.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);
    final navIndex = state.currentNavIndex;

    try {
      final flow = Provider.of<FlowProvider>(context, listen: false);
      state.onTaskCompletedForFlow ??= flow.recordTaskCompletionLocally;
      state.onFlowNeedsRefresh ??= flow.loadOverview;
      // One visible Noya reaction per completion: a hop, or a celebration for the last task of
      // the day (the reaction controller caps celebrations at 3 per day).
      state.onTaskCompletedForNoya ??= (task, {required bool lastOfDay}) {
        flow.animController.reactions.react(lastOfDay ? NoyaReaction.celebrate : NoyaReaction.taskDone);
      };
    } catch (_) {}

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && navIndex > 0) {
          state.setNavIndex(0);
        }
      },
      child: Scaffold(
        backgroundColor: FlowColors.background(context),
        body: Stack(
          children: [
            FlowAmbientBackground(
              visualState: _getTabVisualState(navIndex),
              child: FlowFadeIndexedStack(
                index: navIndex,
                children: _tabs,
              ),
            ),
            // Noya "thinking" the moment any tracked async work starts; nothing when idle.
            const SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: IgnorePointer(child: NoyaBusyBadge()),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: FlowBottomNav(
          currentIndex: navIndex,
          onTap: (idx) => state.setNavIndex(idx),
        ),
      ),
    );
  }
}
