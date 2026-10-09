import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flowstate/components/replan_new_task_sheet.dart';
import 'package:flowstate/providers/app_state_provider.dart';
import 'package:flowstate/screens/replan_day_sheet.dart';
import 'package:flowstate/services/api_service.dart';
import 'package:flowstate/services/flow_clock.dart';
import 'package:flowstate/theme/flow_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  setUp(() {
    FlowClock.enableAutoTick = false;
    FlowClock.debugNowOverride = null;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    FlowClock.debugNowOverride = null;
  });

  group('Replan New Task Quick Add Time Flow', () {
    testWidgets('1. Quick Add opens with manual "Pick a time" control, not automatic Noya pick', (tester) async {
      final fixedNow = DateTime(2026, 10, 9, 14, 0);
      FlowClock.debugNowOverride = () => fixedNow;

      ReplanNewTaskResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await ReplanNewTaskSheet.show(
                    ctx,
                    selectedDate: DateTime(2026, 10, 9),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // UI displays "Pick a time" by default, NOT an automatic Noya pick
      expect(find.text('Pick a time'), findsOneWidget);
      expect(find.text('Start time'), findsOneWidget);
      expect(find.textContaining("Noya's pick"), findsNothing);
      expect(find.textContaining('Today at'), findsNothing);

      // Enter title
      await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Fix critical bug');
      await tester.pump();

      // Plan it is enabled without forcing manual selection
      final submitFinder = find.byKey(const Key('replan_new_task_submit'));
      expect(submitFinder, findsOneWidget);
      expect(find.text('Plan it'), findsOneWidget);

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.title, 'Fix critical bug');
      expect(result!.minutes, 45);
      expect(result!.time, isNull);
      expect(result!.isNoyaPick, isTrue);
    });

    testWidgets('2. Explicit time selection sets fixed time and isNoyaPick is false', (tester) async {
      ReplanNewTaskResult? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: FlowTheme.lightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  result = await ReplanNewTaskSheet.show(
                    ctx,
                    initialTime: const TimeOfDay(hour: 8, minute: 30),
                    selectedDate: DateTime(2026, 10, 9),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Starts at 8:30 AM'), findsOneWidget);
      expect(find.text('Fixed time selected by you'), findsOneWidget);
      expect(find.text('Fixed time'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Team code review');
      await tester.pump();

      await tester.tap(find.byKey(const Key('replan_new_task_submit')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.time, const TimeOfDay(hour: 8, minute: 30));
      expect(result!.isNoyaPick, isFalse);
    });

    testWidgets('3. Successful persistence payload: sends start_time and constraint_type fixed_start', (tester) async {
      final fixedNow = DateTime(2026, 10, 5, 8, 0);
      FlowClock.debugNowOverride = () => fixedNow;

      Map<String, dynamic>? capturedBody;
      final mockClient = MockClient((request) async {
        if (request.url.path.contains('/replan')) {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'plan_id': 'test-plan-123',
              'plan_diff': {
                'plan_id': 'test-plan-123',
                'selected_date': '2026-10-05',
                'items': [
                  {
                    'task_id': 'new-task-1',
                    'title': 'Deploy hotfix',
                    'change_type': 'new',
                    'new_time': '8:30 AM',
                    'new_start': '2026-10-05T08:30:00Z',
                    'new_end': '2026-10-05T09:15:00Z',
                    'duration_minutes': 45,
                    'is_fixed': true,
                    'time_locked': true,
                  }
                ],
                'conflicts': [],
                'issues': [],
              },
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });

      final provider = AppStateProvider(customApi: ApiService(client: mockClient));
      await tester.pumpWidget(
        ChangeNotifierProvider<AppStateProvider>.value(
          value: provider,
          child: MaterialApp(
            theme: FlowTheme.lightTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showReplanDaySheet(context, selectedDate: DateTime(2026, 10, 5)),
                  child: const Text('Open Replan'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Replan'));
      await tester.pumpAndSettle();

      // Tap urgent work arrived chip
      await tester.tap(find.text('Urgent work arrived'));
      await tester.pumpAndSettle();

      // Enter task title
      await tester.enterText(find.byKey(const Key('replan_new_task_title')), 'Deploy hotfix');
      await tester.pump();

      // Pick time
      await tester.tap(find.byKey(const Key('replan_new_task_time')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.byKey(const Key('replan_new_task_submit')));
      await tester.pumpAndSettle();

      // Verify the payload sent to the backend
      expect(capturedBody, isNotNull);
      final quickAdd = capturedBody!['quick_add'] as Map<String, dynamic>?;
      expect(quickAdd, isNotNull);
      expect(quickAdd!['title'], 'Deploy hotfix');
      expect(quickAdd['duration_minutes'], 45);
      expect(quickAdd['start_time'], isNotNull);
      expect(quickAdd['constraint_type'], 'fixed_start');
      expect(quickAdd['is_preferred'], isNot(true));

      // Verify chat displays the time
      expect(find.textContaining('Urgent: Deploy hotfix · 45 min at', skipOffstage: false), findsOneWidget);
    });
  });
}
