import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../components/flow_bottom_nav.dart';
import '../providers/app_state_provider.dart';
import '../theme/flow_colors.dart';
import 'today_dashboard_tab.dart';
import 'task_inbox_tab.dart';
import 'calendar_tab.dart';
import 'insights_tab.dart';
import 'profile_settings_tab.dart';

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
