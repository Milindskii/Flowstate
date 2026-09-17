import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/flow_bottom_nav.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import '../theme/flow_radii.dart';
import '../theme/flow_typography.dart';
import 'today_dashboard_tab.dart';
import 'task_inbox_tab.dart';
import 'calendar_tab.dart';
import 'insights_tab.dart';
import 'profile_settings_tab.dart';
import 'what_should_i_do_screen.dart';

/// Root Mobile Shell coordinating bottom navigation and the 5 destinations
class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const List<Widget> _tabs = [
    TodayDashboardTab(),
    TaskInboxTab(),
    CalendarTab(),
    InsightsTab(),
    ProfileSettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppStateProvider>(context);

    return Scaffold(
      backgroundColor: FlowColors.darkBackground,
      // Prominent thumb action on Today tab: "What should I do now?"
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: state.currentNavIndex == 0
          ? Padding(
              padding: const EdgeInsets.only(bottom: 56.0), // Ergonomic thumb zone above sticky bar
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: FlowRadii.buttonRadius,
                  gradient: FlowColors.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: FlowColors.cyan.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: FlowRadii.buttonRadius,
                    splashColor: Colors.white.withOpacity(0.25),
                    onTap: () {
                      final task = state.recommendedTask;
                      if (task != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => WhatShouldIDoScreen(task: task),
                          ),
                        );
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: FlowColors.textInverse,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'What should I do now?',
                            style: FlowTypography.labelLarge(color: FlowColors.textInverse).copyWith(
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
      body: IndexedStack(
        index: state.currentNavIndex,
        children: _tabs,
      ),
      bottomNavigationBar: FlowBottomNav(
        currentIndex: state.currentNavIndex,
        onTap: (idx) => state.setNavIndex(idx),
      ),
    );
  }
}
