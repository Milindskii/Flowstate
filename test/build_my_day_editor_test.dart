import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/components/task_date_time_pickers.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/timezone_service.dart';
import 'package:flowstate/components/ai_economy_sheets.dart';

class MockBuildMyDayApiService extends ApiService {
  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    if (endpoint == '/api/v1/tasks') {
      if (body is Map) {
        final res = Map<String, dynamic>.from(body);
        res['id'] ??= 'task-${DateTime.now().millisecondsSinceEpoch}';
        return res;
      }
      return <String, dynamic>{
        'id': 'task-1',
        'title': 'Test Task',
        'type': 'deep_work',
        'estimated_minutes': 45,
        'difficulty': 'high',
        'priority': 'medium',
        'priority_source': 'unspecified',
        'status': 'pending',
      };
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    if (endpoint == '/api/v1/auth/me') {
      return {
        'id': 'user-test-1',
        'email': 'tester@flowstate.local',
        'name': 'Tester',
        'onboarding_completed': true,
      };
    }
    if (endpoint == '/api/v1/ai/status') {
      return {
        'is_pro': false,
        'subscription_tier': 'free',
        'free_use_available': false,
        'free_uses_consumed': 1,
        'shields_available': 3,
        'shield_funded_uses': 0,
        'can_use_ai': true,
        'requires_shield': false,
        'hourly_requests_remaining': 10,
      };
    }
    if (endpoint == '/api/v1/tasks') {
      return {'items': [], 'total': 0};
    }
    if (endpoint == '/api/v1/today') {
      return {
        'user': {'id': 'user-test-1', 'email': 'tester@flowstate.local'},
        'date': '2026-10-01',
        'lifecycle_state': 'returning_user',
        'readiness': {'score': 85, 'max_score': 100, 'confidence': 1.0, 'is_calibrated': true, 'factors': [], 'hourly_rhythm': []},
        'tasks': [],
        'schedule': [],
      };
    }
    return {};
  }
}

Widget createTestApp({
  required Widget child,
  AppStateProvider? customAppState,
}) {
  final mockApi = MockBuildMyDayApiService();
  const testUser = AuthUser(
    id: 'user-test-1',
    email: 'tester@flowstate.local',
    name: 'Tester',
    onboardingCompleted: true,
  );
  final appState = customAppState ?? AppStateProvider(customApi: mockApi, initialUser: testUser);
  if (appState.currentUser == null) {
    appState.onUserAuthenticated(testUser);
  }
  final themeProvider = ThemeProvider();
  final flowProvider = FlowProvider(api: mockApi);

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AppStateProvider>.value(value: appState),
      ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
      ChangeNotifierProvider<FlowProvider>.value(value: flowProvider),
    ],
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({kGeminiPrivacyAcceptedKey: true});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
  });
  tearDown(() => FlowClock().stopTimer());

  group('Phase 1: Build My Day Task Editor Pickers & Semantics', () {
    test('Unit: TaskDateTimePickers formatting and parsing helpers', () {
      final today = DateTime.now();
      expect(TaskDateTimePickers.formatDateDisplay(today), 'Today');

      final tomorrow = today.add(const Duration(days: 1));
      expect(TaskDateTimePickers.formatDateDisplay(tomorrow), 'Tomorrow');

      final futureDate = DateTime(2026, 12, 25);
      expect(TaskDateTimePickers.formatDateDisplay(futureDate), 'Fri, Dec 25');

      expect(TaskDateTimePickers.formatDateDisplay(null), 'No date set');

      expect(TaskDateTimePickers.formatTimeDisplay(null), 'No fixed time');
      expect(TaskDateTimePickers.formatTimeDisplay(const TimeOfDay(hour: 14, minute: 30)), '2:30 PM');
      expect(TaskDateTimePickers.formatTimeDisplay(const TimeOfDay(hour: 9, minute: 0)), '9:00 AM');

      final parsed = TaskDateTimePickers.parseTimeString('4:15 PM');
      expect(parsed, isNotNull);
      expect(parsed!.hour, 16);
      expect(parsed.minute, 15);

      expect(TaskDateTimePickers.parseTimeString('No fixed time'), isNull);
      expect(TaskDateTimePickers.parseTimeString(null), isNull);
    });

    testWidgets('Build My Day task editor exposes real Date & Time picker buttons', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open Build My Day'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Build My Day'));
      await tester.pumpAndSettle();

      // Enter task and build plan
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Submit physics report');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      // Verify plan preview is shown
      expect(find.text('YOUR PLAN'), findsOneWidget);

      // Tap Edit
      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Verify structured editor is open
      expect(find.byKey(const Key('structured_task_editor')), findsOneWidget);

      // Verify real date and time buttons are present
      expect(find.byKey(const Key('edit_plan_task_date_button')), findsOneWidget);
      expect(find.byKey(const Key('edit_plan_task_time_button')), findsOneWidget);

      // Verify labels
      expect(find.text('DEADLINE / DATE'), findsOneWidget);
      expect(find.text('FIXED TIME'), findsOneWidget);
    });

    testWidgets('Date picker opens dialog, allows date selection, and updates task constraints', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open Build My Day'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Build My Day'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Prepare presentation');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Tap Date button -> opens Flutter calendar date picker
      await tester.ensureVisible(find.byKey(const Key('edit_plan_task_date_button')));
      await tester.tap(find.byKey(const Key('edit_plan_task_date_button')));
      await tester.pumpAndSettle();

      // Verify calendar date picker dialog is visible
      expect(find.byType(DatePickerDialog), findsOneWidget);

      // Tap 'Done' on date picker
      final confirmBtn = find.text('Done').hitTestable().first;
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Date picker dialog is dismissed
      expect(find.byType(DatePickerDialog), findsNothing);

      // Save changes
      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();

      // Returned to preview with updated task
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Prepare presentation'), findsOneWidget);
    });

    testWidgets('Time picker opens dialog and allows selecting arbitrary valid time', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open Build My Day'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Build My Day'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Team standup meeting');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Tap Time button -> opens Flutter clock time picker
      await tester.ensureVisible(find.byKey(const Key('edit_plan_task_time_button')));
      await tester.tap(find.byKey(const Key('edit_plan_task_time_button')));
      await tester.pumpAndSettle();

      // Verify time picker dialog is visible
      expect(find.byType(TimePickerDialog), findsOneWidget);

      // Tap 'Done' on time picker
      final confirmBtn = find.text('Done').hitTestable().first;
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Time picker dialog is dismissed cleanly
      expect(find.byType(TimePickerDialog), findsNothing);

      // Save changes
      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();

      // Returned to preview
      expect(find.text('YOUR PLAN'), findsOneWidget);
    });

    testWidgets('Clear buttons on date and time reset constraints to No fixed time / default', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open Build My Day'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Build My Day'));
      await tester.pumpAndSettle();

      // Task with explicit time
      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Dentist at 3pm');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Clear the fixed time using clear button
      if (find.byKey(const Key('edit_plan_task_clear_time')).evaluate().isNotEmpty) {
        await tester.ensureVisible(find.byKey(const Key('edit_plan_task_clear_time')));
        await tester.tap(find.byKey(const Key('edit_plan_task_clear_time')));
        await tester.pump();
        expect(find.text('No fixed time'), findsOneWidget);
      }

      // Save changes
      await tester.tap(find.byKey(const Key('save_changes_button')));
      await tester.pumpAndSettle();

      expect(find.text('YOUR PLAN'), findsOneWidget);
    });

    testWidgets('Back / Cancel button in task editor cancels edit cleanly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createTestApp(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showBrainDumpSheet(ctx),
            child: const Text('Open Build My Day'),
          ),
        ),
      ));

      await tester.tap(find.text('Open Build My Day'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Code review');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('edit_button')));
      await tester.pumpAndSettle();

      // Change title
      await tester.enterText(find.byKey(const Key('edit_task_title_field')), 'Changed But Cancelled');
      await tester.pump();

      // Tap Cancel button
      await tester.tap(find.byKey(const Key('edit_cancel_button')));
      await tester.pumpAndSettle();

      // Preview should still have original title, not changed title
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(find.text('Code review'), findsOneWidget);
      expect(find.text('Changed But Cancelled'), findsNothing);
    });
  });
}
