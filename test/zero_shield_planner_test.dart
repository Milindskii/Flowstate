import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/ai_economy_sheets.dart';
import 'package:flowstate/components/edit_task_sheet.dart';
import 'package:flowstate/components/noya_shield_gate.dart';
import 'package:flowstate/components/reschedule_task_sheet.dart';
import 'package:flowstate/components/routines_sheet.dart';
import 'package:flowstate/models/ai_plan_models.dart';
import 'package:flowstate/models/task_item.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/providers/flow_provider.dart';
import 'package:flowstate/providers/theme_provider.dart';
import 'package:flowstate/screens/add_task_sheet.dart';
import 'package:flowstate/screens/brain_dump_sheet.dart';
import 'package:flowstate/services/ai_plan_service.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/auth_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/services/routine_service.dart';
import 'package:flowstate/services/timezone_service.dart';

import 'support/date_picker_helpers.dart';

/// A signed-in account with ZERO Shields and its free AI plan spent. Shields pay for AI only: every ordinary
/// planner action below must work, must never touch an AI endpoint, and the one genuinely AI action must explain
/// itself (Noya) instead of dead-ending.
class _ZeroShieldApi extends ApiService {
  final List<String> calls = [];
  bool statusUnreachable = false;
  int routineCount = 1;

  List<String> get aiCalls => [for (final c in calls) if (c == 'POST /api/v1/ai/plan') c];

  Map<String, dynamic> status() {
    final now = DateTime.now().toUtc();
    return {
      'is_pro': false,
      'free_use_available': false,
      'free_uses_consumed': 1,
      'free_uses_remaining': 0,
      'shields_available': 0,
      'shield_cost': 2,
      'shield_cost_replan': 1,
      'can_afford_shield_plan': false,
      'can_use_ai': false,
      'requires_shield': true,
      'shield_max': 3,
      'server_now': now.toIso8601String(),
      'next_shield_refill_at': now.add(const Duration(days: 2, hours: 14, minutes: 1)).toIso8601String(),
    };
  }

  @override
  Future<dynamic> get(String endpoint, {Map<String, dynamic>? queryParams}) async {
    calls.add('GET $endpoint');
    if (endpoint == '/api/v1/ai/status') {
      if (statusUnreachable) throw const ApiException('offline');
      return status();
    }
    if (endpoint == '/api/v1/routines') {
      return [
        if (routineCount > 0)
          {'id': 'r1', 'title': 'Gym', 'kind': 'fixed', 'recurrence': 'daily', 'start_hhmm': '16:00', 'estimated_minutes': 60, 'summary': 'Daily at 4:00 PM'}
      ];
    }
    if (endpoint == '/api/v1/tasks') return {'items': [], 'total': 0};
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> post(String endpoint, {dynamic body}) async {
    calls.add('POST $endpoint');
    if (endpoint == '/api/v1/tasks' && body is Map) {
      return {...Map<String, dynamic>.from(body), 'id': 'task-server-1'};
    }
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> patch(String endpoint, {dynamic body}) async {
    calls.add('PATCH $endpoint');
    if (endpoint.startsWith('/api/v1/routines/')) routineCount = routineCount; // accepted
    return <String, dynamic>{...(body is Map ? Map<String, dynamic>.from(body) : {}), 'id': endpoint.split('/').last};
  }

  @override
  Future<dynamic> put(String endpoint, {dynamic body}) async {
    calls.add('PUT $endpoint');
    return <String, dynamic>{...(body is Map ? Map<String, dynamic>.from(body) : {}), 'id': endpoint.split('/').last};
  }

  @override
  Future<dynamic> delete(String endpoint) async {
    calls.add('DELETE $endpoint');
    if (endpoint.startsWith('/api/v1/routines/')) routineCount = 0;
    return <String, dynamic>{};
  }
}

const _user = AuthUser(id: 'user-zero', email: 'zero@flowstate.local', name: 'Zero', onboardingCompleted: true);

void main() {
  late _ZeroShieldApi api;
  late AppStateProvider app;

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock().stopTimer();
    SharedPreferences.setMockInitialValues({kGeminiPrivacyAcceptedKey: true});
    TimezoneService.overrideForTesting = () async => 'Asia/Kolkata';
    api = _ZeroShieldApi();
    app = AppStateProvider(customApi: api, initialUser: _user);
    app.setOnboardingCompleteForTesting(true);
  });
  tearDown(() => FlowClock().stopTimer());

  Widget host(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AppStateProvider>.value(value: app),
          ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
          ChangeNotifierProvider<FlowProvider>(create: (_) => FlowProvider(api: api)),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      );

  Future<void> bigScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
  }

  group('zero Shields: the ordinary planner works', () {
    testWidgets('create a task with a type, duration, priority, date and a FIXED time', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(host(const AddTaskSheet()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Dentist appointment');
      await tester.tap(find.byKey(const Key('add_task_preset_tomorrow')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add_task_time_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').hitTestable().first); // the picker opens on 10:00 AM
      await tester.pumpAndSettle();
      expect(find.text('10:00 AM'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('add_task_submit_button')));
      await tester.tap(find.byKey(const Key('add_task_submit_button')));
      await tester.pumpAndSettle();

      final created = app.tasks.firstWhere((t) => t.title == 'Dentist appointment');
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      expect(created.scheduledStart, isNotNull);
      expect(created.scheduledStart!.day, tomorrow.day);
      expect((created.scheduledStart!.hour, created.scheduledStart!.minute), (10, 0));
      expect(api.calls, contains('POST /api/v1/tasks'));
      expect(api.calls.where((c) => c.contains('/ai/')), isEmpty, reason: 'no AI, no Shield check');
    });

    testWidgets('edit a task: title, date and time', (tester) async {
      await bigScreen(tester);
      const task = TaskItem(
          id: 'task-e', title: 'Read paper', durationMinutes: 45, difficulty: TaskDifficulty.medium, deadline: 'Today', category: 'Study');
      app.setTasksForTesting([task]);
      await tester.pumpWidget(host(const EditTaskSheet(task: task)));
      await tester.pumpAndSettle();

      // ONE date control and ONE time control
      expect(find.byKey(const Key('edit_task_date_button')), findsOneWidget);
      expect(find.byKey(const Key('edit_task_time_button')), findsOneWidget);
      expect(find.text('DATE'), findsOneWidget);
      expect(find.text('TIME'), findsOneWidget);
      expect(find.text('Pick date'), findsOneWidget);
      expect(find.text('Pick time'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Read the paper twice');
      await pickDateVia(tester, find.byKey(const Key('edit_task_date_button')), DateTime.now().add(const Duration(days: 1)));
      await tester.tap(find.byKey(const Key('edit_task_time_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done').hitTestable().first);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      final saved = app.tasks.firstWhere((t) => t.id == 'task-e');
      expect(saved.title, 'Read the paper twice');
      expect(saved.scheduledStart, isNotNull);
      expect(api.calls.where((c) => c.contains('/ai/')), isEmpty);
    });

    testWidgets('reschedule a task manually: one date control, one time control, no AI', (tester) async {
      await bigScreen(tester);
      const task = TaskItem(
          id: 'task-r', title: 'Write report', durationMinutes: 60, difficulty: TaskDifficulty.high, deadline: 'Today', category: 'Work');
      app.setTasksForTesting([task]);
      await tester.pumpWidget(host(Builder(
          builder: (ctx) => TextButton(onPressed: () => RescheduleTaskSheet.show(ctx, task), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('reschedule_date_picker_button')), findsOneWidget);
      expect(find.byKey(const Key('reschedule_time_picker_button')), findsOneWidget);
      expect(find.text('CALENDAR DATE'), findsNothing);
      expect(find.text('CLOCK TIME'), findsNothing);
      expect(find.text('Pick Date'), findsNothing);

      await pickDateVia(tester, find.byKey(const Key('reschedule_date_picker_button')), DateTime.now().add(const Duration(days: 2)));
      await tester.tap(find.byKey(const Key('reschedule_confirm_button')));
      await tester.pumpAndSettle();

      final moved = app.tasks.firstWhere((t) => t.id == 'task-r');
      expect(moved.deadlineAt?.day, DateTime.now().add(const Duration(days: 2)).day);
      expect(api.calls.where((c) => c.contains('/ai/')), isEmpty);
    });

    testWidgets('routines: view, retime and delete', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(host(RoutinesSheet(service: RoutineService(api: api))));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routine_tile_r1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('routine_tile_r1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK').hitTestable().first);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('PATCH /api/v1/routines/r1')), hasLength(1));

      await tester.tap(find.byKey(const Key('routine_delete_r1')));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('DELETE /api/v1/routines/r1')), hasLength(1));
      expect(find.byKey(const Key('routines_empty')), findsOneWidget);
      expect(api.calls.where((c) => c.contains('/ai/')), isEmpty);
    });

    testWidgets('typing a plain fixed-time task into Build My Day plans it locally: no AI call, no Shield', (tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(host(Builder(
          builder: (ctx) => TextButton(onPressed: () => showBrainDumpSheet(ctx), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('brain_dump_text_field')), 'Dentist at 3pm');
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('noya_shield_gate')), findsNothing, reason: 'not an AI action: no Shield UI');
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(api.aiCalls, isEmpty);
    });
  });

  group('zero Shields: the one genuinely AI action', () {
    Future<void> openAndAsk(WidgetTester tester) async {
      await bigScreen(tester);
      await tester.pumpWidget(host(Builder(
          builder: (ctx) => TextButton(onPressed: () => showBrainDumpSheet(ctx), child: const Text('open')))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('brain_dump_text_field')),
        'I need to finish the report. Also call the bank. Then I want to study for the exam because it is soon.',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();
    }

    testWidgets('Noya explains: what needs Shields, the cost, the balance, the next free Shield, how to earn', (tester) async {
      await openAndAsk(tester);

      expect(find.byKey(const Key('noya_shield_gate')), findsOneWidget);
      expect(find.text("You're out of Shields."), findsOneWidget);
      expect(find.text('An AI plan needs 2 Shields. You have 0.'), findsOneWidget);
      expect(find.text('Your next free Shield is available in 2d 14h.'), findsOneWidget);
      expect(find.byKey(const Key('shield_gate_ways')), findsOneWidget);
      expect(find.byKey(const Key('shield_gate_earn')), findsOneWidget);
      expect(find.byKey(const Key('shield_gate_later')), findsOneWidget);
      expect(api.aiCalls, isEmpty, reason: 'nothing was sent to the AI and nothing was charged');
      expect(find.byKey(const Key('ai_failure_card')), findsNothing, reason: 'not the generic dead-end');
    });

    testWidgets('"Maybe later" keeps the text; "Plan it myself" is the manual way on, with zero Shields', (tester) async {
      await openAndAsk(tester);
      await tester.tap(find.byKey(const Key('shield_gate_later')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noya_shield_gate')), findsNothing);
      expect(find.textContaining('finish the report'), findsOneWidget, reason: 'the dump is still there');

      await tester.tap(find.byKey(const Key('brain_dump_build_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('use_basic_planner_button')));
      await tester.pumpAndSettle();
      expect(find.text('YOUR PLAN'), findsOneWidget);
      expect(api.aiCalls, isEmpty);
    });

    testWidgets('an unreachable server is reported as unreachable: no invented free plan, no invented Shields', (tester) async {
      api.statusUnreachable = true;
      expect(await AIPlanService(api: api).getUsageStatus(), isNull);
      await openAndAsk(tester);
      expect(find.byKey(const Key('noya_shield_gate')), findsNothing);
      expect(api.aiCalls, isEmpty, reason: 'without a verified allowance the app never calls the AI');
    });
  });

  group('the Shield wait is the server\'s clock', () {
    test('formatting reads like Noya says it', () {
      expect(formatShieldWait(const Duration(days: 2, hours: 14, minutes: 5)), '2d 14h');
      expect(formatShieldWait(const Duration(days: 3)), '3d');
      expect(formatShieldWait(const Duration(hours: 5, minutes: 20)), '5h 20m');
      expect(formatShieldWait(const Duration(minutes: 12)), '12m');
      expect(formatShieldWait(const Duration(seconds: 30)), 'under a minute');
    });

    test('status counts down from the server-measured wait; the device clock only supplies elapsed time', () {
      final s = AIUsageStatus.fromJson({
        ..._ZeroShieldApi().status(),
        'server_now': '2026-10-08T12:00:00Z',
        'next_shield_refill_at': '2026-10-11T12:00:00Z',
      });
      expect(s.untilNextShield, const Duration(days: 3));
      final readAt = s.readAt!;
      expect(s.untilNextShieldAt(readAt), const Duration(days: 3));
      expect(s.untilNextShieldAt(readAt.add(const Duration(hours: 5))), const Duration(days: 2, hours: 19));
      // a device clock jumped BACKWARDS or a decade ahead: never negative, never a free Shield
      expect(s.untilNextShieldAt(readAt.subtract(const Duration(days: 9))), const Duration(days: 3));
      expect(s.untilNextShieldAt(readAt.add(const Duration(days: 4000))), Duration.zero);
    });

    test('a response without a balance is zero Shields, never two', () {
      expect(AIUsageStatus.fromJson(const {}).shieldsAvailable, 0);
    });
  });
}
