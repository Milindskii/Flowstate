import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/components/day_path/day_route_geometry.dart';
import 'package:flowstate/components/day_path/day_route_painter.dart';
import 'package:flowstate/components/flow_day_path.dart';
import 'package:flowstate/components/task_interactive_controls.dart';
import 'package:flowstate/models/schedule_item.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/calendar_tab.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_motion.dart';
import 'package:flowstate/theme/flow_theme.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
  });

  tearDown(() {
    FlowClock().stopTimer();
  });

  Widget wrapWithTheme(Widget child, {AppStateProvider? provider, bool isDark = true}) {
    final theme = isDark ? FlowTheme.darkTheme() : FlowTheme.lightTheme();
    if (provider != null) {
      return ChangeNotifierProvider<AppStateProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: child),
        ),
      );
    }
    return MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    );
  }

  /// The geometry the screen actually paints (one source of truth).
  DayRouteGeometry paintedGeometry(WidgetTester tester) =>
      (tester.widget<CustomPaint>(find.byKey(const Key('flow_day_route'))).painter as DayRoutePainter).geometry;

  bool traveledBetween(DayRouteGeometry g, String a, String b) {
    final ya = g.stopById(a).center.dy, yb = g.stopById(b).center.dy;
    final flags = [
      for (var i = 0; i < g.sampleYs.length; i++)
        if (g.sampleYs[i] > ya && g.sampleYs[i] < yb) g.sampleStates[i] == RouteSegmentState.traveled
    ];
    return flags.isNotEmpty && flags.every((t) => t);
  }

  ScheduleItem makeItem({
    required String id,
    required String title,
    required String time,
    required String period,
    int durationMinutes = 30,
    bool isCompleted = false,
    bool isSkipped = false,
    bool isCompletedAfterDeviation = false,
    bool isFailed = false,
  }) {
    return ScheduleItem(
      id: id,
      title: title,
      time: time,
      period: period,
      durationMinutes: durationMinutes,
      type: 'Task',
      tagText: isSkipped ? 'SKIPPED' : (isCompleted ? 'DONE' : 'TASK'),
      isCompleted: isCompleted,
      isSkipped: isSkipped,
      isCompletedAfterDeviation: isCompletedAfterDeviation,
      isFailed: isFailed,
    );
  }

  group('Dynamic Day Path 12 State Transitions & Core Roadmap Semantics', () {
    testWidgets('1. Four planned tasks -> blue route A -> B -> C -> D', (WidgetTester tester) async {
      final items = [
        makeItem(id: 'item-a', title: 'Task A', time: '9:00', period: 'AM', durationMinutes: 30),
        makeItem(id: 'item-b', title: 'Task B', time: '11:00', period: 'AM', durationMinutes: 45),
        makeItem(id: 'item-c', title: 'Task C', time: '1:00', period: 'PM', durationMinutes: 60),
        makeItem(id: 'item-d', title: 'Task D', time: '3:00', period: 'PM', durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapWithTheme(
          FlowDayPath(
            items: items,
            nowItemId: null,
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final id in ['item-a', 'item-b', 'item-c', 'item-d']) {
        expect(find.byKey(Key('path_node_$id')), findsOneWidget);
        expect(find.byKey(Key('path_skipped_$id')), findsNothing);
        expect(find.byKey(Key('path_failed_$id')), findsNothing);
      }
    });

    testWidgets('2 & 3. Skip B -> B is a yellow skipped node and the road runs on through it', (WidgetTester tester) async {
      final items = [
        makeItem(id: 'item-a', title: 'Task A', time: '9:00', period: 'AM', durationMinutes: 30),
        makeItem(id: 'item-b', title: 'Task B', time: '11:00', period: 'AM', durationMinutes: 45, isSkipped: true),
        makeItem(id: 'item-c', title: 'Task C', time: '1:00', period: 'PM', durationMinutes: 60),
        makeItem(id: 'item-d', title: 'Task D', time: '3:00', period: 'PM', durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapWithTheme(
          FlowDayPath(
            items: items,
            nowItemId: null,
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // B is rendered as yellow skipped stop
      expect(find.byKey(const Key('path_skipped_item-b')), findsOneWidget);
      expect(find.textContaining('Skipped'), findsOneWidget);

      // The road is continuous: it runs through B (and A, C, D) and stays the normal blue, not removed or bent away.
      final g = paintedGeometry(tester);
      expect(g.stopById('item-b').role, StopRouteRole.skipped);
      for (final id in ['item-a', 'item-b', 'item-c', 'item-d']) {
        expect(g.distanceToRoute(g.stopById(id).center), lessThan(0.5));
      }
      expect(g.sampleStates.every((s) => s == RouteSegmentState.ahead), isTrue, reason: 'nothing walked: all blue');
    });

    testWidgets('4. Complete A -> A and traveled segment become green', (WidgetTester tester) async {
      final items = [
        makeItem(id: 'item-a', title: 'Task A', time: '9:00', period: 'AM', durationMinutes: 30, isCompleted: true),
        makeItem(id: 'item-b', title: 'Task B', time: '11:00', period: 'AM', durationMinutes: 45),
        makeItem(id: 'item-c', title: 'Task C', time: '1:00', period: 'PM', durationMinutes: 60),
        makeItem(id: 'item-d', title: 'Task D', time: '3:00', period: 'PM', durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapWithTheme(
          FlowDayPath(
            items: items,
            nowItemId: 'item-b',
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // A is completed check
      expect(find.byKey(const Key('path_check_item-a')), findsOneWidget);
      // The stretch A -> B (NOW) is walked (green); beyond NOW the road ahead is still blue.
      final g = paintedGeometry(tester);
      expect(traveledBetween(g, 'item-a', 'item-b'), isTrue);
      expect(traveledBetween(g, 'item-b', 'item-c'), isFalse);
    });

    testWidgets('5. Complete C after skipping B -> C completes normally', (WidgetTester tester) async {
      final items = [
        makeItem(id: 'item-a', title: 'Task A', time: '9:00', period: 'AM', durationMinutes: 30, isCompleted: true),
        makeItem(id: 'item-b', title: 'Task B', time: '11:00', period: 'AM', durationMinutes: 45, isSkipped: true),
        makeItem(id: 'item-c', title: 'Task C', time: '1:00', period: 'PM', durationMinutes: 60, isCompleted: true),
        makeItem(id: 'item-d', title: 'Task D', time: '3:00', period: 'PM', durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapWithTheme(
          FlowDayPath(
            items: items,
            nowItemId: null,
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('path_check_item-a')), findsOneWidget);
      expect(find.byKey(const Key('path_skipped_item-b')), findsOneWidget);
      expect(find.byKey(const Key('path_check_item-c')), findsOneWidget);
      // A -> B is still the blue road into the skipped stop; B -> C was walked (green); beyond C it is blue.
      final g = paintedGeometry(tester);
      expect(g.stopById('item-b').role, StopRouteRole.skipped);
      expect(traveledBetween(g, 'item-a', 'item-b'), isFalse);
      expect(traveledBetween(g, 'item-b', 'item-c'), isTrue);
      expect(traveledBetween(g, 'item-c', 'item-d'), isFalse);
    });

    testWidgets('6. Complete B later -> B shows yellow/gold completed after deviation state', (WidgetTester tester) async {
      final items = [
        makeItem(id: 'item-a', title: 'Task A', time: '9:00', period: 'AM', durationMinutes: 30, isCompleted: true),
        makeItem(
          id: 'item-b',
          title: 'Task B',
          time: '11:00',
          period: 'AM',
          durationMinutes: 45,
          isCompleted: true,
          isCompletedAfterDeviation: true,
        ),
        makeItem(id: 'item-c', title: 'Task C', time: '1:00', period: 'PM', durationMinutes: 60, isCompleted: true),
        makeItem(id: 'item-d', title: 'Task D', time: '3:00', period: 'PM', durationMinutes: 30),
      ];

      await tester.pumpWidget(
        wrapWithTheme(
          FlowDayPath(
            items: items,
            nowItemId: null,
            reflectionFor: (_) => null,
            completedAtFor: (_) => null,
            onTap: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('path_check_item-b')), findsOneWidget);
      expect(find.textContaining('Recovered'), findsOneWidget);
      // History is kept: B is marked recovered and the road into it is orange, on the very same line as the rest.
      final g = paintedGeometry(tester);
      final b = g.stopById('item-b');
      expect(b.role, StopRouteRole.recovered);
      expect(g.distanceToRoute(b.center), lessThan(0.5));
      final orange = [
        for (var i = 0; i < g.sampleYs.length; i++)
          if (g.sampleStates[i] == RouteSegmentState.recovered) Offset(g.sampleXs[i], g.sampleYs[i])
      ];
      expect(orange, isNotEmpty);
      for (final p in orange) {
        expect(g.distanceToRoute(p), lessThan(1e-6), reason: 'orange follows the canonical route');
        expect(p.dy, inInclusiveRange(g.stopById('item-a').center.dy, b.center.dy));
      }
    });

    testWidgets('7. Unresolved task past sleep boundary -> red cross', (WidgetTester tester) async {
      final provider = AppStateProvider();
      provider.setDemoMode(true);
      final pastDate = DateTime(2026, 10, 1);
      final task = TaskItem(
        id: 'task-unresolved',
        title: 'Unresolved Task From Past',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Past',
        category: 'Work',
        scheduledStart: DateTime(2026, 10, 1, 9, 0),
        scheduledEnd: DateTime(2026, 10, 1, 9, 45),
        isCompleted: false,
      );
      provider.setTasksForTesting([task]);
      await provider.loadCalendarDay(pastDate);

      await tester.pumpWidget(
        wrapWithTheme(
          const CalendarTab(),
          provider: provider,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('path_failed_sched-task-unresolved')), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.textContaining('Unfinished'), findsOneWidget);
    });

    test('8. Restart app -> route state persists', () async {
      SharedPreferences.setMockInitialValues({
        'flowstate_skipped_task_ids': ['persisted-skipped-task'],
        'flowstate_completed_after_deviation_task_ids': ['persisted-recovered-task'],
      });

      final provider = AppStateProvider();
      provider.setDemoMode(true);
      await provider.routeStatesReady;

      expect(provider.skippedTaskIds.contains('persisted-skipped-task'), isTrue);
      expect(provider.completedAfterDeviationTaskIds.contains('persisted-recovered-task'), isTrue);
    });

    testWidgets('9. Navigate away/back -> route state persists', (WidgetTester tester) async {
      final provider = AppStateProvider();
      provider.setDemoMode(true);
      final now = DateTime.now();
      final taskA = TaskItem(
        id: 'task-nav-a',
        title: 'Task A',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        scheduledStart: DateTime(now.year, now.month, now.day, 9, 0),
        scheduledEnd: DateTime(now.year, now.month, now.day, 9, 30),
      );
      provider.setTasksForTesting([taskA]);
      await provider.loadCalendarDay(now);

      provider.skipTask('task-nav-a');
      expect(provider.skippedTaskIds.contains('task-nav-a'), isTrue);

      // Mount Calendar
      await tester.pumpWidget(wrapWithTheme(const CalendarTab(), provider: provider));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path_skipped_sched-task-nav-a')), findsOneWidget);

      // Navigate away (replace tree with empty container)
      await tester.pumpWidget(wrapWithTheme(const SizedBox.shrink(), provider: provider));
      await tester.pumpAndSettle();

      // Navigate back
      await tester.pumpWidget(wrapWithTheme(const CalendarTab(), provider: provider));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('path_skipped_sched-task-nav-a')), findsOneWidget);
    });

    testWidgets('10. Change selected date -> route recalculates from that date tasks', (WidgetTester tester) async {
      final provider = AppStateProvider();
      provider.setDemoMode(true);
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));

      final taskToday = TaskItem(
        id: 'task-today',
        title: 'Task Today Unique Title',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        scheduledStart: DateTime(today.year, today.month, today.day, 10, 0),
        scheduledEnd: DateTime(today.year, today.month, today.day, 10, 30),
      );
      final taskTomorrow = TaskItem(
        id: 'task-tomorrow',
        title: 'Task Tomorrow Unique Title',
        durationMinutes: 45,
        difficulty: TaskDifficulty.medium,
        deadline: 'Tomorrow',
        category: 'Study',
        scheduledStart: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 0),
        scheduledEnd: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 45),
      );

      provider.setTasksForTesting([taskToday, taskTomorrow]);
      await provider.loadCalendarDay(today);

      await tester.pumpWidget(wrapWithTheme(const CalendarTab(), provider: provider));
      await tester.pumpAndSettle();
      expect(find.text('Task Today Unique Title'), findsOneWidget);
      expect(find.text('Task Tomorrow Unique Title'), findsNothing);

      // Switch date to tomorrow
      await provider.loadCalendarDay(tomorrow);
      await tester.pumpAndSettle();
      expect(find.text('Task Tomorrow Unique Title'), findsOneWidget);
      expect(find.text('Task Today Unique Title'), findsNothing);
    });

    testWidgets('11. Reduced motion -> no movement animation', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                expect(FlowMotion.isReducedMotion(context), isTrue);
                expect(
                  FlowMotion.responsiveDuration(context, const Duration(milliseconds: 380)),
                  Duration.zero,
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pump();
    });

    testWidgets('12. No red failure state appears merely because the task is unfinished', (WidgetTester tester) async {
      final provider = AppStateProvider();
      provider.setDemoMode(true);
      final now = DateTime.now();
      // Configure bedtime at 23:00
      provider.updatePersonalData(provider.personalData.copyWith(bedtime: '23:00'));

      final unfinishedTask = TaskItem(
        id: 'task-pending-daytime',
        title: 'Daytime Pending Review',
        durationMinutes: 30,
        difficulty: TaskDifficulty.medium,
        deadline: 'Today',
        category: 'Work',
        scheduledStart: DateTime(now.year, now.month, now.day, 8, 0),
        scheduledEnd: DateTime(now.year, now.month, now.day, 8, 30),
        isCompleted: false,
      );
      provider.setTasksForTesting([unfinishedTask]);
      await provider.loadCalendarDay(now);

      await tester.pumpWidget(wrapWithTheme(const CalendarTab(), provider: provider));
      await tester.pumpAndSettle();

      // If user is awake, task is not failed
      if (now.hour < 23 && now.hour >= 5) {
        expect(find.byKey(const Key('path_failed_sched-task-pending-daytime')), findsNothing);
        expect(find.text('Unfinished'), findsNothing);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
      }
    });
  });

  group('PrioritySelector 4-Tier Semantic Controls', () {
    testWidgets('6. Renders Low, Medium, High, Urgent with correct colors and selection', (WidgetTester tester) async {
      TaskPriority selectedPriority = TaskPriority.low;

      await tester.pumpWidget(
        wrapWithTheme(
          StatefulBuilder(
            builder: (context, setState) {
              return PrioritySelector(
                priority: selectedPriority,
                onChanged: (p) => setState(() => selectedPriority = p),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);

      // Tap Urgent
      await tester.tap(find.text('Urgent'));
      await tester.pumpAndSettle();
      expect(selectedPriority, TaskPriority.urgent);

      // Tap High
      await tester.tap(find.text('High'));
      await tester.pumpAndSettle();
      expect(selectedPriority, TaskPriority.high);
    });
  });
}
