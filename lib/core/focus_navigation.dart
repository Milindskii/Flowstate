import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_item.dart';
import '../providers/app_state_provider.dart';
import '../providers/flow_provider.dart';
import '../screens/focus_ritual_screen.dart';
import '../theme/flow_haptics.dart';

/// Single canonical entry point for all focus sessions in Flowstate.
///
/// Guarantees:
/// 1. Every focus entry point routes to the unified FocusRitualScreen.
/// 2. Mode A (Task focus) vs Mode B (Free Flow) is handled explicitly.
/// 3. Upon session exit/return, Today data and Flow progression are refreshed to prevent stale UI.
Future<void> openFocusRitual(
  BuildContext context, {
  TaskItem? task,
  int initialMinutes = 25,
}) async {
  FlowHaptics.lightTap();
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FocusRitualScreen(
        task: task,
        initialMinutes: initialMinutes,
      ),
    ),
  );
  if (context.mounted) {
    try {
      Provider.of<AppStateProvider>(context, listen: false).refreshTodayData();
    } catch (_) {}
    try {
      Provider.of<FlowProvider>(context, listen: false).loadOverview();
    } catch (_) {}
  }
}
