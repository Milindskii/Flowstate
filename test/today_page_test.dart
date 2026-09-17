import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:flowstate/screens/today_dashboard_tab.dart';
import 'package:flowstate/providers/app_state_provider.dart';

void main() {
  Widget createTestWidget(AppStateProvider provider) {
    return ChangeNotifierProvider<AppStateProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: TodayDashboardTab(),
      ),
    );
  }

  testWidgets('Renders Today page with populated tasks and Right Now card', (WidgetTester tester) async {
    final provider = AppStateProvider();
    await tester.pumpWidget(createTestWidget(provider));
    await tester.pumpAndSettle();

    // Verify dynamic greeting
    expect(find.textContaining('Good morning'), findsOneWidget);

    // Verify RIGHT NOW section
    expect(find.text('RIGHT NOW'), findsOneWidget);

    // Verify "Start" button exists
    expect(find.text('Start'), findsOneWidget);

    // Verify "What now?" floating pill exists
    expect(find.text('What now?'), findsOneWidget);

    // Verify TODAY timeline section exists
    expect(find.text('TODAY'), findsOneWidget);
  });

  testWidgets('Renders empty state when user has no tasks', (WidgetTester tester) async {
    final provider = AppStateProvider();
    provider.clearAllTasksForNewUserState();

    await tester.pumpWidget(createTestWidget(provider));
    await tester.pumpAndSettle();

    // Verify New User greeting
    expect(find.text('Good morning 👋'), findsOneWidget);

    // Verify Empty state title
    expect(find.text('Let’s build your day.'), findsOneWidget);

    // Verify call to actions
    expect(find.text('Add a task'), findsOneWidget);
    expect(find.text('Tell Flowstate what I need to do'), findsOneWidget);
  });
}
